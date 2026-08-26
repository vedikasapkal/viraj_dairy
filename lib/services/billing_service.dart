// =============================================================================
// BILLING SERVICE
// lib/services/billing_service.dart
//
// PAYMENT STATUS RULE
// -----------------------------------------------------------------------------
// 1. New order: paymentStatus = null/empty  => NOT Pending, NOT Paid.
// 2. Bill is "Paid" only when ALL orders in that billing cycle are "Paid".
// 3. This service NEVER auto-changes an unpaid order to "Pending".
//
// =============================================================================
// FIX (this version) — THE "AUTO SPLIT / JUMPS TO NEXT DATE" BUG
// -----------------------------------------------------------------------------
// The OLD buildCustomerCycles() anchored every cycle to the customer's very
// FIRST order ever, then chopped time into fixed 48-hour slots counted
// forward from that anchor FOREVER (slot = elapsedTime ~/ 48h). That meant:
//   - If a customer went quiet for a while and then placed one more order,
//     it could land in slot #6 or #7 purely because of the calendar gap,
//     even though only 2 orders exist. The UI then shows "Bill #7" out of
//     nowhere — this LOOKS like the app auto-created/auto-moved bills, but
//     it never touched your data. It was a numbering artifact.
//   - Worse: `customer_payment_screen.dart` had its OWN SEPARATE copy of
//     this logic (`_createBillingCycles`) that used a DIFFERENT algorithm
//     (sequential, restarting after each cycle matures). So the admin
//     screen and the customer screen could show different bill boundaries
//     for the exact same orders.
//
// THE FIX: one single algorithm, used everywhere (admin + customer):
//   - The first not-yet-billed order opens a cycle.
//   - The cycle is EXACTLY 48 real calendar hours from that order's
//     timestamp.
//   - Every order that arrives before the cycle matures joins that cycle.
//   - The next order placed AFTER maturity opens the next cycle.
//   - Cycles are never re-opened or re-numbered later — bill #1 stays
//     bill #1 forever once orders are assigned to it.
// This is deterministic from the stored order timestamps alone, so simply
// reopening the app / rebuilding the widget can never change past bills.
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/item_model.dart';

class BillingService {
  // ===========================================================================
  // STATIC CONFIGURATION
  // ===========================================================================

  static const String adminUpiId = 'merchant@upi';
  static const String adminName = 'Viraj Dairy';

  // ===========================================================================
  // 48 HOUR BILLING WINDOW
  // ===========================================================================

  static const Duration billingDuration = Duration(hours: 48);

  // ===========================================================================
  // DELIVERY CHARGE
  // ===========================================================================

  static const double deliveryChargePerDay = 5.0;
  static const int billingDays = 2;

  /// Rs. 5 x 2 days = Rs. 10
  static double get deliveryCharge => deliveryChargePerDay * billingDays;

  // ===========================================================================
  // DATE HELPERS
  // ===========================================================================

  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

    // Firestore Timestamp objects expose seconds/nanoseconds and a toDate()
    // method. We avoid a hard dependency on cloud_firestore here, so we
    // duck-type it — this also fixes silently-failed parsing of any
    // 'orderDate' Timestamp fields that slipped into an order map.
    try {
      final dynamic maybeTimestamp = value;
      if (maybeTimestamp.runtimeType.toString() == 'Timestamp') {
        final DateTime converted = maybeTimestamp.toDate();
        return converted;
      }
    } catch (_) {
      // Not a Timestamp — fall through to string parsing.
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    return DateTime.tryParse(text);
  }

  /// Returns the best known creation time for an order.
  ///
  /// IMPORTANT: this NEVER falls back to DateTime.now(). Falling back to
  /// "now" was the source of a second, subtler bug — an order with a
  /// missing/unparsable date would silently get a NEW timestamp every time
  /// this method ran (i.e. every rebuild), which reshuffled which billing
  /// cycle it belonged to on every screen refresh. Instead we fall back to
  /// a fixed sentinel date so behaviour is at least stable, and we log it
  /// loudly so bad data gets noticed and fixed at the source.
  static DateTime getOrderCreatedAt(Map<String, dynamic> order) {
    final createdAt = parseDate(order['createdAt']);
    if (createdAt != null) return createdAt;

    final orderDate = parseDate(order['date']);
    if (orderDate != null) return orderDate;

    final legacyOrderDate = parseDate(order['orderDate']);
    if (legacyOrderDate != null) return legacyOrderDate;

    debugPrint(
      'BillingService: order ${order['id']} has no valid createdAt/date — '
      'using a fixed fallback date so billing cycles stay stable. '
      'Please fix this order\'s data.',
    );

    // Fixed sentinel (NOT DateTime.now()) so re-running this doesn't change
    // the cycle this order lands in.
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ===========================================================================
  // CALENDAR FORMATTING (day / date / month / year, clearly separated)
  // ===========================================================================

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Breaks a DateTime into clearly labelled calendar parts, so the UI can
  /// show "Day: Tuesday", "Date: 25", "Month: August", "Year: 2026" without
  /// any ambiguous formatting.
  static Map<String, String> getCalendarBreakdown(DateTime date) {
    final local = date.toLocal();

    return {
      'weekday': _weekdays[local.weekday - 1],
      'day': local.day.toString().padLeft(2, '0'),
      'monthName': _months[local.month - 1],
      'monthNumber': local.month.toString().padLeft(2, '0'),
      'year': local.year.toString(),
      'time':
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    };
  }

  /// Human-friendly single line, e.g. "Tuesday, 25 August 2026 • 10:30"
  static String formatCalendarLong(DateTime date) {
    final b = getCalendarBreakdown(date);
    return '${b['weekday']}, ${b['day']} ${b['monthName']} ${b['year']} • ${b['time']}';
  }

  /// Compact single line, e.g. "25/08/2026 10:30"
  static String formatCalendarShort(DateTime date) {
    final b = getCalendarBreakdown(date);
    return '${b['day']}/${b['monthNumber']}/${b['year']} ${b['time']}';
  }

  // ===========================================================================
  // BILL UNLOCK HELPERS
  // ===========================================================================

  static DateTime getMaturityTime(Map<String, dynamic> order) {
    return getOrderCreatedAt(order).add(billingDuration);
  }

  static bool isBillUnlocked(Map<String, dynamic> order) {
    final maturity = getMaturityTime(order);
    return !DateTime.now().isBefore(maturity);
  }

  static Duration getRemainingTime(Map<String, dynamic> order) {
    final maturity = getMaturityTime(order);
    final now = DateTime.now();
    if (!maturity.isAfter(now)) return Duration.zero;
    return maturity.difference(now);
  }

  // ===========================================================================
  // PAYMENT STATUS HELPERS
  // ===========================================================================

  /// Returns true ONLY when the database explicitly says Paid.
  static bool isOrderPaid(Map<String, dynamic> order) {
    final status =
        order['paymentStatus']?.toString().trim().toLowerCase() ?? '';
    return status == 'paid';
  }

  static bool isOrderUnpaid(Map<String, dynamic> order) {
    return !isOrderPaid(order);
  }

  /// null = not fully paid yet. 'Paid' = every order in the cycle is Paid.
  /// We intentionally never return "Pending" from here.
  static String? getCyclePaymentStatus(List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) return null;

    for (final order in orders) {
      if (!isOrderPaid(order)) return null;
    }
    return 'Paid';
  }

  // ===========================================================================
  // MONEY & UPI PARSING
  // ===========================================================================

  static double parseAmount(dynamic amount) {
    if (amount == null) return 0.0;
    if (amount is num) return amount.toDouble();

    final value = amount.toString().replaceAll(',', '');
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(value);

    if (match != null) {
      return double.tryParse(match.group(0)!) ?? 0.0;
    }
    return 0.0;
  }

  static String buildUpiUri({
    required double amount,
    required String note,
  }) {
    return 'upi://pay'
        '?pa=$adminUpiId'
        '&pn=${Uri.encodeComponent(adminName)}'
        '&am=${amount.toStringAsFixed(2)}'
        '&cu=INR'
        '&tn=${Uri.encodeComponent(note)}';
  }

  static String _money(double amount) => 'Rs. ${amount.toStringAsFixed(2)}';

  // ===========================================================================
  // CART TOTAL
  // ===========================================================================

  static String calculateCartTotal(List<CartItemModel> cart) {
    double total = 0;
    for (final item in cart) {
      total += parseAmount(item.price);
    }
    return '₹${total.toStringAsFixed(2)}';
  }

  static int parseAmountInt(String? amount) {
    if (amount == null) return 0;
    return int.tryParse(amount.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  // ===========================================================================
  // ORDER TOTAL
  // ===========================================================================

  static double orderTotal(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];

    if (items.isEmpty) {
      final fallbackTotal = order['totalAmount'] ??
          order['total'] ??
          order['grandTotal'] ??
          order['amount'] ??
          order['price'] ??
          0;
      return parseAmount(fallbackTotal);
    }

    double sum = 0;

    for (final rawItem in items) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);

      final qty = parseAmount(
        item['qty'] ?? item['quantity'] ?? item['count'] ?? 1,
      );

      final price = parseAmount(
        item['price'] ?? item['itemPrice'] ?? item['amount'] ?? item['rate'] ?? 0,
      );

      if (price == 0 && (item['total'] != null || item['itemTotal'] != null)) {
        sum += parseAmount(item['total'] ?? item['itemTotal']);
      } else {
        sum += qty * price;
      }
    }

    if (sum == 0) {
      final fallbackTotal = order['totalAmount'] ??
          order['total'] ??
          order['grandTotal'] ??
          order['amount'] ??
          0;
      return parseAmount(fallbackTotal);
    }

    return sum;
  }

  // ===========================================================================
  // BUILD CUSTOMER BILLING CYCLES  (SINGLE SOURCE OF TRUTH — SEQUENTIAL)
  //
  // This is the ONLY place cycles are computed. Both the admin dashboard
  // AND the customer payment screen must call this — do not re-implement
  // this logic anywhere else, that duplication is exactly what caused the
  // bug this version fixes.
  // ===========================================================================

  static List<Map<String, dynamic>> buildCustomerCycles(
    List<Map<String, dynamic>> customerOrders,
  ) {
    if (customerOrders.isEmpty) return [];

    final sorted = [...customerOrders]
      ..sort((a, b) => getOrderCreatedAt(a).compareTo(getOrderCreatedAt(b)));

    final List<Map<String, dynamic>> cycles = [];
    final now = DateTime.now();

    int index = 0;
    int billNumber = 1;

    while (index < sorted.length) {
      // ---------------------------------------------------------------------
      // A NEW CYCLE STARTS EXACTLY AT THIS ORDER'S OWN TIMESTAMP.
      // It is NEVER anchored to the customer's very first order ever —
      // that was the bug. Each cycle is independent once the previous one
      // has matured.
      // ---------------------------------------------------------------------

      final start = getOrderCreatedAt(sorted[index]);
      final maturity = start.add(billingDuration);

      final List<Map<String, dynamic>> cycleOrders = [];

      while (index < sorted.length &&
          getOrderCreatedAt(sorted[index]).isBefore(maturity)) {
        cycleOrders.add(sorted[index]);
        index++;
      }

      double ordersSubtotal = 0;
      for (final order in cycleOrders) {
        ordersSubtotal += orderTotal(order);
      }

      final String? paymentStatus = getCyclePaymentStatus(cycleOrders);
      final double cycleDeliveryCharge = deliveryCharge;
      final double total = ordersSubtotal + cycleDeliveryCharge;
      final bool isUnlocked = !now.isBefore(maturity);

      cycles.add(<String, dynamic>{
        'billNumber': billNumber,
        'cycleId':
            'bill_${cycleOrders.first['id']}_${start.millisecondsSinceEpoch}',
        'orders': cycleOrders,
        'firstOrderTime': start,
        'maturityTime': maturity,
        'ordersSubtotal': ordersSubtotal,
        'deliveryCharge': cycleDeliveryCharge,
        'totalAmount': total,
        'paymentStatus': paymentStatus, // null when unpaid, 'Paid' when done
        'isUnlocked': isUnlocked,
        // Ready-to-render calendar strings — no more manual date math in the UI.
        'startCalendarLong': formatCalendarLong(start),
        'endCalendarLong': formatCalendarLong(maturity),
        'startCalendarShort': formatCalendarShort(start),
        'endCalendarShort': formatCalendarShort(maturity),
        'startBreakdown': getCalendarBreakdown(start),
        'endBreakdown': getCalendarBreakdown(maturity),
      });

      billNumber++;
    }

    return cycles;
  }

  // ===========================================================================
  // CURRENT CUSTOMER BILL
  // ===========================================================================

  static Map<String, dynamic>? getCurrentCycle(
    List<Map<String, dynamic>> customerOrders,
  ) {
    final cycles = buildCustomerCycles(customerOrders);
    if (cycles.isEmpty) return null;

    for (final cycle in cycles) {
      final unlocked = cycle['isUnlocked'] == true;
      final paid = cycle['paymentStatus'] == 'Paid';
      if (unlocked && !paid) return cycle;
    }

    return cycles.last;
  }

  // ===========================================================================
  // ALL CUSTOMER CYCLES (for admin's aggregate view)
  // ===========================================================================

  static List<Map<String, dynamic>> getAllCustomerCycles(
    List<Map<String, dynamic>> allOrders,
  ) {
    final Map<String, List<Map<String, dynamic>>> byCustomer = {};

    for (final order in allOrders) {
      final mobile = order['customerMobile']?.toString() ??
          order['mobile']?.toString() ??
          order['phone']?.toString();

      if (mobile != null && mobile.isNotEmpty) {
        byCustomer.putIfAbsent(mobile, () => []).add(order);
      }
    }

    final List<Map<String, dynamic>> result = [];

    byCustomer.forEach((mobile, orders) {
      final cycle = getCurrentCycle(orders);
      if (cycle != null) {
        result.add({'customerMobile': mobile, ...cycle});
      }
    });

    return result;
  }

  // ===========================================================================
  // REMAINING TIME (for a cycle)
  // ===========================================================================

  static String getRemainingTimeForCycle(Map<String, dynamic> cycle) {
    final unlockTime =
        parseDate(cycle['maturityTime']) ?? parseDate(cycle['unlockTime']);

    if (unlockTime == null) return 'Unlocked';

    final difference = unlockTime.difference(DateTime.now());
    if (difference.isNegative) return 'Unlocked';

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;

    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m remaining';
    }
    return '${hours}h ${minutes}m remaining';
  }

  // ===========================================================================
  // PDF GENERATION
  // ===========================================================================

  static Future<Uint8List> generateBillPdf({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> cycle,
  }) async {
    final pdf = pw.Document();

    final List<Map<String, dynamic>> orders =
        List<Map<String, dynamic>>.from(cycle['orders'] ?? []);

    double ordersSubtotal = parseAmount(cycle['ordersSubtotal']);
    if (ordersSubtotal == 0 && orders.isNotEmpty) {
      for (final order in orders) {
        ordersSubtotal += orderTotal(order);
      }
    }

    double deliveryChargeAmt = parseAmount(cycle['deliveryCharge']);
    if (deliveryChargeAmt == 0) {
      deliveryChargeAmt = deliveryCharge;
    }

    final calculatedTotal = ordersSubtotal + deliveryChargeAmt;

    final customerName = customer['name']?.toString() ?? 'Customer';
    final customerMobile = customer['mobile']?.toString() ?? '';
    final billNumber = cycle['billNumber']?.toString() ?? '1';

    final firstOrderTime = parseDate(cycle['firstOrderTime']) ??
        (orders.isNotEmpty
            ? getOrderCreatedAt(orders.first)
            : DateTime.now());

    final maturityTime = parseDate(cycle['maturityTime']) ??
        firstOrderTime.add(const Duration(hours: 48));

    final Map<String, pw.ImageProvider> loadedImages = {};

    for (final order in orders) {
      final photoUrl =
          order['deliveryPhotoUrl'] ?? order['imageUrl'] ?? order['photo'];
      if (photoUrl == null) continue;

      final url = photoUrl.toString().trim();
      if (url.isEmpty) continue;

      try {
        loadedImages[order['id']?.toString() ?? ''] = await networkImage(url);
      } catch (_) {}
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'VIRAJ DAIRY',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Fresh & Pure Dairy Products',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'FINAL BILL',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text('Bill #$billNumber',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(
                      'Generated: ${formatCalendarShort(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Divider(color: PdfColors.blue900, thickness: 1.5),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CUSTOMER DETAILS',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.SizedBox(height: 5),
                      pw.Text('Name: $customerName',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Mobile: $customerMobile',
                          style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('BILLING WINDOW',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Started: ${formatCalendarLong(firstOrderTime)}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        'Unlocked: ${formatCalendarLong(maturityTime)}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        '48 Hours Completed',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'ORDER DETAILS',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
            pw.SizedBox(height: 10),
            ...orders.map((order) {
              final orderId = order['id']?.toString() ?? '';
              final orderDate = getOrderCreatedAt(order);
              final items = (order['items'] as List?) ?? [];
              final thisOrderTotal = orderTotal(order);
              final deliveryPhoto = loadedImages[orderId];

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 15),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Order #$orderId',
                          style: pw.TextStyle(
                              fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          formatCalendarShort(orderDate),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    if (items.isNotEmpty)
                      pw.TableHelper.fromTextArray(
                        headers: const ['Product', 'Qty', 'Price', 'Total'],
                        headerStyle: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          fontSize: 9,
                        ),
                        headerDecoration:
                            const pw.BoxDecoration(color: PdfColors.blue900),
                        cellStyle: const pw.TextStyle(fontSize: 9),
                        data: items.map((rawItem) {
                          final item = rawItem is Map
                              ? Map<String, dynamic>.from(rawItem)
                              : <String, dynamic>{};

                          final name = item['name']?.toString() ??
                              item['productName']?.toString() ??
                              'Product';

                          final qty = parseAmount(
                            item['qty'] ??
                                item['quantity'] ??
                                item['count'] ??
                                1,
                          );

                          final price = parseAmount(
                            item['price'] ??
                                item['itemPrice'] ??
                                item['amount'] ??
                                item['rate'] ??
                                0,
                          );

                          final itemTotal = price > 0
                              ? qty * price
                              : parseAmount(
                                  item['total'] ?? item['itemTotal'] ?? 0);

                          return [
                            name,
                            _formatQty(qty),
                            _money(price),
                            _money(itemTotal),
                          ];
                        }).toList(),
                      )
                    else
                      pw.Text(
                        'Dairy Products - ${_money(thisOrderTotal)}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    pw.SizedBox(height: 8),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'Order Total: ${_money(thisOrderTotal)}',
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    if (deliveryPhoto != null) ...[
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Delivery Proof',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Image(deliveryPhoto,
                          width: 110, height: 110, fit: pw.BoxFit.cover),
                    ],
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 5),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 260,
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4, vertical: 6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Orders Subtotal',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(_money(ordersSubtotal),
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Delivery Charges ($billingDays Days @ '
                          'Rs.${deliveryChargePerDay.toStringAsFixed(0)}/day)',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(_money(deliveryChargeAmt),
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue900),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('TOTAL BILL',
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _money(calculatedTotal),
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 25),
            pw.Divider(color: PdfColors.grey400),
            pw.Center(
              child: pw.Text(
                'Thank you for choosing Viraj Dairy.',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'This bill was automatically unlocked '
                'after completion of the 48-hour billing window.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // PRINT BILL
  // ===========================================================================

  static Future<void> printBill({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> cycle,
  }) async {
    final pdfBytes = await generateBillPdf(customer: customer, cycle: cycle);

    await Printing.layoutPdf(
      name: 'Viraj_Dairy_Bill_${DateTime.now().millisecondsSinceEpoch}.pdf',
      onLayout: (PdfPageFormat format) async {
        return pdfBytes;
      },
    );
  }

  // ===========================================================================
  // FORMAT HELPERS
  // ===========================================================================

  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toString();
  }
}