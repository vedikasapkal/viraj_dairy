// =============================================================================
// BILLING SERVICE
// lib/services/billing_service.dart
//
// Responsibilities:
// 1. Calculate order totals
// 2. Parse amounts
// 3. Create/maintain exact 48-hour billing information
// 4. Generate customer/admin PDF
// =============================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/item_model.dart';

class BillingService {
  // Static configuration fields used across admin and customer screens
  static const String adminUpiId = 'merchant@upi'; // Replace with your actual UPI ID
  static const String adminName = 'Viraj Dairy';

  // ===========================================================================
  // 48 HOUR BILLING WINDOW
  // ===========================================================================

  static const Duration billingDuration = Duration(hours: 48);

  // ---------------------------------------------------------------------------
  // Parse DateTime safely
  // ---------------------------------------------------------------------------

  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return value;
    }

    final text = value.toString().trim();

    if (text.isEmpty) return null;

    return DateTime.tryParse(text);
  }

  // ---------------------------------------------------------------------------
  // Get the ORIGINAL order creation timestamp.
  //
  // IMPORTANT:
  // createdAt is checked FIRST.
  //
  // Do NOT use "date" first because date may only contain a calendar date
  // without the exact time.
  // ---------------------------------------------------------------------------

  static DateTime getOrderCreatedAt(Map<String, dynamic> order) {
    final createdAt = parseDate(order['createdAt']);

    if (createdAt != null) {
      return createdAt;
    }

    final orderDate = parseDate(order['date']);

    if (orderDate != null) {
      return orderDate;
    }

    // Only for old records that have no timestamp.
    //
    // New orders should NEVER reach this.
    return DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // Exact maturity time
  // ---------------------------------------------------------------------------

  static DateTime getMaturityTime(Map<String, dynamic> order) {
    return getOrderCreatedAt(order).add(billingDuration);
  }

  // ---------------------------------------------------------------------------
  // Is 48 hours completed?
  // ---------------------------------------------------------------------------

  static bool isBillUnlocked(Map<String, dynamic> order) {
    final maturity = getMaturityTime(order);

    return !DateTime.now().isBefore(maturity);
  }

  // ---------------------------------------------------------------------------
  // Remaining time
  // ---------------------------------------------------------------------------

  static Duration getRemainingTime(Map<String, dynamic> order) {
    final maturity = getMaturityTime(order);
    final now = DateTime.now();

    if (!maturity.isAfter(now)) {
      return Duration.zero;
    }

    return maturity.difference(now);
  }

  // ===========================================================================
  // MONEY & UPI
  // ===========================================================================

  static double parseAmount(dynamic amount) {
    if (amount == null) return 0.0;

    if (amount is num) {
      return amount.toDouble();
    }

    String value = amount.toString();

    value = value.replaceAll(',', '');

    value = value.replaceAll(
      RegExp(r'[^0-9.\-]'),
      '',
    );

    return double.tryParse(value) ?? 0.0;
  }

  /// Builds a standard UPI payment URI for QR codes and deep links
  static String buildUpiUri({required double amount, required String note}) {
    return 'upi://pay?pa=$adminUpiId&pn=${Uri.encodeComponent(adminName)}&am=${amount.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent(note)}';
  }

  // ===========================================================================
  // CART TOTAL
  // ===========================================================================

  static String calculateCartTotal(List<CartItemModel> cart) {
    double total = 0;

    for (final item in cart) {
      // Your model may store price as a String.
      final dynamic priceValue = item.price;

      final price = parseAmount(priceValue);

      // If your CartItemModel contains quantity use it.
      //
      // Because different versions of your model may have different fields,
      // the original behavior is kept as one item = one line amount.
      total += price;
    }

    return '₹${total.toStringAsFixed(2)}';
  }

  static int parseAmountInt(String? amount) {
    if (amount == null) return 0;

    return int.tryParse(
          amount.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
  }

  // ===========================================================================
  // CYCLE CREATION
  // ===========================================================================

  static Map<String, dynamic> createBillingCycle({
    required int cycleNumber,
    required List<Map<String, dynamic>> orders,
  }) {
    if (orders.isEmpty) {
      throw ArgumentError('Orders cannot be empty');
    }

    final firstOrder = orders.first;

    final firstOrderTime = getOrderCreatedAt(firstOrder);

    final maturityTime =
        firstOrderTime.add(const Duration(hours: 48));

    double total = 0;

    bool allPaid = true;

    final List<String> orderIds = [];

    for (final order in orders) {
      total += parseAmount(order['totalAmount']);

      orderIds.add(
        order['id']?.toString() ?? '',
      );

      if ((order['paymentStatus'] ?? 'Pending') != 'Paid') {
        allPaid = false;
      }
    }

    final now = DateTime.now();

    final unlocked = !now.isBefore(maturityTime);

    return {
      'cycleId': 'billing_${cycleNumber}_${firstOrderTime.millisecondsSinceEpoch}',

      'billNumber': cycleNumber,

      'orders': orders,

      'orderIds': orderIds,

      'firstOrderTime': firstOrderTime,

      'maturityTime': maturityTime,

      'totalAmount': total,

      'paymentStatus': allPaid ? 'Paid' : 'Pending',

      'isUnlocked': unlocked,

      'generatedAt': unlocked ? now : null,
    };
  }

  // ===========================================================================
  // CUSTOMER & ADMIN CYCLE RETRIEVAL HELPERS
  // ===========================================================================

  /// Finds the current pending billing cycle for a specific customer based on unpaid orders.
  static Map<String, dynamic>? getCustomerCycle({
    required List<Map<String, dynamic>> allOrders,
    required String customerMobile,
  }) {
    // Filter unpaid orders for this customer
    final customerOrders = allOrders.where((o) {
      final mobile = o['customerMobile']?.toString() ?? '';
      final paymentStatus = o['paymentStatus']?.toString() ?? 'Pending';
      return mobile == customerMobile && paymentStatus != 'Paid';
    }).toList();

    if (customerOrders.isEmpty) {
      return null; // No pending cycle / all paid
    }

    // Sort orders by timestamp/date if available
    customerOrders.sort((a, b) {
      final dateA = getOrderCreatedAt(a);
      final dateB = getOrderCreatedAt(b);
      return dateA.compareTo(dateB);
    });

    final earliestOrder = customerOrders.first;
    final createdAt = getOrderCreatedAt(earliestOrder);

    // 48 hours (2 days) locking period
    final unlockTime = createdAt.add(const Duration(hours: 48));
    final bool isUnlocked = DateTime.now().isAfter(unlockTime);

    double totalAmount = 0.0;
    for (var order in customerOrders) {
      totalAmount += parseAmount(order['totalAmount']);
    }

    return {
      'hasPendingCycle': true,
      'orders': customerOrders,
      'totalAmount': totalAmount,
      'firstOrderTime': createdAt,
      'maturityTime': unlockTime,
      'isUnlocked': isUnlocked,
    };
  }

  /// Retrieves cycles for all customers or processes multiple cycles
  static List<Map<String, dynamic>> getAllCustomerCycles(List<Map<String, dynamic>> allOrders) {
    final Map<String, List<Map<String, dynamic>>> groupedByCustomer = {};

    for (var order in allOrders) {
      final mobile = order['customerMobile']?.toString();
      if (mobile != null && mobile.isNotEmpty) {
        groupedByCustomer.putIfAbsent(mobile, () => []).add(order);
      }
    }

    List<Map<String, dynamic>> cycles = [];
    groupedByCustomer.forEach((mobile, orders) {
      final cycle = getCustomerCycle(allOrders: orders, customerMobile: mobile);
      if (cycle != null) {
        cycles.add({'customerMobile': mobile, ...cycle});
      }
    });

    return cycles;
  }

  /// Calculates remaining time string for a cycle
  static String getRemainingTimeForCycle(Map<String, dynamic> cycle) {
    final unlockTime = parseDate(cycle['maturityTime']) ?? parseDate(cycle['unlockTime']);
    if (unlockTime == null) return 'Unlocked';

    final difference = unlockTime.difference(DateTime.now());
    if (difference.isNegative) {
      return 'Unlocked';
    }

    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;
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
        List<Map<String, dynamic>>.from(
      cycle['orders'] ?? [],
    );

    final double totalAmount =
        parseAmount(cycle['totalAmount']);

    final customerName =
        customer['name']?.toString() ?? 'Customer';

    final customerMobile =
        customer['mobile']?.toString() ?? '';

    final billNumber =
        cycle['billNumber']?.toString() ?? '1';

    final firstOrderTime =
        parseDate(cycle['firstOrderTime']) ??
            getOrderCreatedAt(orders.first);

    final maturityTime =
        parseDate(cycle['maturityTime']) ??
            firstOrderTime.add(
              const Duration(hours: 48),
            );

    // -------------------------------------------------------------------------
    // Load delivery photos
    // -------------------------------------------------------------------------

    final Map<String, pw.ImageProvider> loadedImages = {};

    for (final order in orders) {
      final photoUrl =
          order['deliveryPhotoUrl'] ??
              order['imageUrl'] ??
              order['photo'];

      if (photoUrl == null) continue;

      final url = photoUrl.toString().trim();

      if (url.isEmpty) continue;

      try {
        loadedImages[
          order['id']?.toString() ?? ''
        ] = await networkImage(url);
      } catch (_) {
        // Photo unavailable - continue PDF generation.
      }
    }

    // -------------------------------------------------------------------------
    // PDF
    // -------------------------------------------------------------------------

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),

        build: (context) {
          return [
            // ================================================================
            // HEADER
            // ================================================================

            pw.Row(
              mainAxisAlignment:
                  pw.MainAxisAlignment.spaceBetween,

              children: [
                pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.start,

                  children: [
                    pw.Text(
                      'VIRAJ DAIRY',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight:
                            pw.FontWeight.bold,
                        color:
                            PdfColors.blue900,
                      ),
                    ),

                    pw.SizedBox(height: 3),

                    pw.Text(
                      'Fresh & Pure Dairy Products',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color:
                            PdfColors.grey700,
                      ),
                    ),
                  ],
                ),

                pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.end,

                  children: [
                    pw.Text(
                      'FINAL BILL',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight:
                            pw.FontWeight.bold,
                      ),
                    ),

                    pw.SizedBox(height: 3),

                    pw.Text(
                      'Bill #$billNumber',
                      style: const pw.TextStyle(
                        fontSize: 10,
                      ),
                    ),

                    pw.Text(
                      'Generated: ${_formatDateTime(DateTime.now())}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 15),

            pw.Divider(
              color: PdfColors.blue900,
              thickness: 1.5,
            ),

            pw.SizedBox(height: 12),

            // ================================================================
            // CUSTOMER DETAILS
            // ================================================================

            pw.Container(
              padding: const pw.EdgeInsets.all(12),

              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.grey400,
                ),
                borderRadius:
                    pw.BorderRadius.circular(6),
              ),

              child: pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,

                children: [
                  pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,

                    children: [
                      pw.Text(
                        'CUSTOMER DETAILS',
                        style: pw.TextStyle(
                          fontWeight:
                              pw.FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),

                      pw.SizedBox(height: 5),

                      pw.Text(
                        'Name: $customerName',
                        style: const pw.TextStyle(
                          fontSize: 10,
                        ),
                      ),

                      pw.Text(
                        'Mobile: $customerMobile',
                        style: const pw.TextStyle(
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),

                  pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.end,

                    children: [
                      pw.Text(
                        'BILLING WINDOW',
                        style: pw.TextStyle(
                          fontWeight:
                              pw.FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),

                      pw.SizedBox(height: 5),

                      pw.Text(
                        'Started: ${_formatDateTime(firstOrderTime)}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                        ),
                      ),

                      pw.Text(
                        'Unlocked: ${_formatDateTime(maturityTime)}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                        ),
                      ),

                      pw.Text(
                        '48 Hours Completed',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight:
                              pw.FontWeight.bold,
                          color:
                              PdfColors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // ================================================================
            // ORIGINAL ORDERS
            // ================================================================

            pw.Text(
              'ORDER DETAILS',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight:
                    pw.FontWeight.bold,
                color:
                    PdfColors.blue900,
              ),
            ),

            pw.SizedBox(height: 10),

            ...orders.map(
              (order) {
                final orderId =
                    order['id']?.toString() ?? '';

                final orderDate =
                    order['createdAt'] ??
                        order['date'] ??
                        '';

                final items =
                    (order['items'] as List?) ?? [];

                final orderTotal =
                    parseAmount(
                  order['totalAmount'],
                );

                final deliveryPhoto =
                    loadedImages[orderId];

                return pw.Container(
                  margin:
                      const pw.EdgeInsets.only(
                    bottom: 15,
                  ),

                  padding:
                      const pw.EdgeInsets.all(10),

                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color:
                          PdfColors.grey400,
                    ),
                    borderRadius:
                        pw.BorderRadius.circular(5),
                  ),

                  child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,

                    children: [
                      pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment.spaceBetween,

                        children: [
                          pw.Text(
                            'Order #$orderId',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  pw.FontWeight.bold,
                            ),
                          ),

                          pw.Text(
                            _formatDateTimeValue(
                              orderDate,
                            ),
                            style:
                                const pw.TextStyle(
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),

                      pw.SizedBox(height: 8),

                      // ------------------------------------------------------
                      // PRODUCT TABLE
                      // ------------------------------------------------------

                      if (items.isNotEmpty)
                        pw.Table.fromTextArray(
                          headers: const [
                            'Product',
                            'Qty',
                            'Price',
                            'Total',
                          ],

                          headerStyle:
                              pw.TextStyle(
                            fontWeight:
                                pw.FontWeight.bold,
                            color:
                                PdfColors.white,
                            fontSize: 9,
                          ),

                          headerDecoration:
                              const pw.BoxDecoration(
                            color:
                                PdfColors.blue900,
                          ),

                          cellStyle:
                              const pw.TextStyle(
                            fontSize: 9,
                          ),

                          data: items.map(
                            (item) {
                              final name =
                                  item['name']
                                      ?.toString() ??
                                      'Product';

                              final qty =
                                  parseAmount(
                                item['qty'] ??
                                    item['quantity'] ??
                                    1,
                              );

                              final price =
                                  parseAmount(
                                item['price'] ??
                                    item['amount'] ??
                                    0,
                              );

                              final itemTotal =
                                  qty * price;

                              return [
                                name,
                                qty.toString(),
                                '₹${price.toStringAsFixed(2)}',
                                '₹${itemTotal.toStringAsFixed(2)}',
                              ];
                            },
                          ).toList(),
                        )
                      else
                        pw.Text(
                          'Dairy Products',
                          style:
                              const pw.TextStyle(
                            fontSize: 9,
                          ),
                        ),

                      pw.SizedBox(height: 8),

                      pw.Align(
                        alignment:
                            pw.Alignment.centerRight,

                        child: pw.Text(
                          'Order Total: ₹${orderTotal.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight:
                                pw.FontWeight.bold,
                          ),
                        ),
                      ),

                      // ------------------------------------------------------
                      // DELIVERY PHOTO
                      // ------------------------------------------------------

                      if (deliveryPhoto != null) ...[
                        pw.SizedBox(height: 8),

                        pw.Text(
                          'Delivery Proof',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight:
                                pw.FontWeight.bold,
                          ),
                        ),

                        pw.SizedBox(height: 4),

                        pw.Image(
                          deliveryPhoto,
                          width: 110,
                          height: 110,
                          fit: pw.BoxFit.cover,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            // ================================================================
            // TOTAL
            // ================================================================

            pw.SizedBox(height: 5),

            pw.Container(
              alignment:
                  pw.Alignment.centerRight,

              child: pw.Container(
                padding:
                    const pw.EdgeInsets.all(12),

                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color:
                        PdfColors.blue900,
                  ),
                  borderRadius:
                      pw.BorderRadius.circular(5),
                ),

                child: pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.end,

                  children: [
                    pw.Text(
                      'TOTAL BILL',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight:
                            pw.FontWeight.bold,
                      ),
                    ),

                    pw.SizedBox(height: 4),

                    pw.Text(
                      '₹${totalAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight:
                            pw.FontWeight.bold,
                        color:
                            PdfColors.blue900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            pw.SizedBox(height: 25),

            pw.Divider(
              color: PdfColors.grey400,
            ),

            pw.Center(
              child: pw.Text(
                'Thank you for choosing Viraj Dairy.',
                style: const pw.TextStyle(
                  fontSize: 9,
                ),
              ),
            ),

            pw.Center(
              child: pw.Text(
                'This bill was automatically unlocked after completion of the 48-hour billing window.',
                style: pw.TextStyle(
                  fontSize: 8,
                  color:
                      PdfColors.grey600,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // PDF PRINT / SAVE
  // ===========================================================================

  static Future<void> printBill({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> cycle,
  }) async {
    final pdfBytes = await generateBillPdf(
      customer: customer,
      cycle: cycle,
    );

    await Printing.layoutPdf(
      name:
          'Viraj_Dairy_Bill_${DateTime.now().millisecondsSinceEpoch}.pdf',

      onLayout: (PdfPageFormat format) async {
        return pdfBytes;
      },
    );
  }

  // ===========================================================================
  // FORMAT HELPERS
  // ===========================================================================

  static String _formatDateTime(
    DateTime date,
  ) {
    final local = date.toLocal();

    final day =
        local.day.toString().padLeft(2, '0');

    final month =
        local.month.toString().padLeft(2, '0');

    final year =
        local.year.toString();

    final hour =
        local.hour.toString().padLeft(2, '0');

    final minute =
        local.minute.toString().padLeft(2, '0');

    final second =
        local.second.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute:$second';
  }

  static String _formatDateTimeValue(
    dynamic value,
  ) {
    final date = parseDate(value);

    if (date == null) {
      return value?.toString() ?? '';
    }

    return _formatDateTime(date);
  }
}