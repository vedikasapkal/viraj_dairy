// =============================================================================
// CUSTOMER PAYMENT SCREEN
// lib/screens/customer_payment_screen.dart
//
// EXACT 48-HOUR BILLING SYSTEM
//
// Order created:
//      13/08/2026 10:30:25
//
// Bill unlocks:
//      15/08/2026 10:30:25
//
// The exact timestamp is used.
// The app does NOT add 2 days from the current login time.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/database_service.dart';
import '../services/billing_service.dart';

class CustomerPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerPaymentScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerPaymentScreen> createState() =>
      _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState
    extends State<CustomerPaymentScreen> {
  final DatabaseService _db =
      DatabaseService();

  List<Map<String, dynamic>> _customerOrders = [];

  Map<String, dynamic>? _billingCycle;

  bool _loading = true;

  bool _refreshing = false;

  Timer? _timer;

  // ===========================================================================
  // ADMIN UPI
  // ===========================================================================

  static const String adminUpiId =
      '9850921154@paytm';

  static const String adminName =
      'Viraj Dairy Admin';

  @override
  void initState() {
    super.initState();

    _loadBilling();

    // Refresh database every 10 seconds.
    //
    // The countdown itself does NOT depend on this.
    // The countdown uses the permanent maturityTime.
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // LOAD ORDERS
  // ===========================================================================

  Future<void> _loadBilling() async {
    if (_refreshing) return;

    _refreshing = true;

    try {
      final allOrders =
          await _db.getAllOrders();

      final customerMobile =
          widget.customer['mobile']
                  ?.toString() ??
              '';

      final orders = allOrders.where(
        (order) {
          final mobile =
              order['customerMobile']
                      ?.toString() ??
                  '';

          return mobile == customerMobile;
        },
      ).toList();

      // ---------------------------------------------------------------
      // SORT BY ORIGINAL CREATED TIME
      // ---------------------------------------------------------------

      orders.sort(
        (a, b) {
          final aDate =
              BillingService.getOrderCreatedAt(
            a,
          );

          final bDate =
              BillingService.getOrderCreatedAt(
            b,
          );

          return aDate.compareTo(bDate);
        },
      );

      if (!mounted) return;

      setState(() {
        _customerOrders = orders;

        if (orders.isNotEmpty) {
          _billingCycle =
              _createCustomerCycle(
            orders,
          );
        } else {
          _billingCycle = null;
        }

        _loading = false;
      });
    } catch (e) {
      debugPrint(
        'Billing load error: $e',
      );

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  // ===========================================================================
  // CREATE CUSTOMER BILLING CYCLE
  // ===========================================================================

  Map<String, dynamic> _createCustomerCycle(
    List<Map<String, dynamic>> orders,
  ) {
    // -------------------------------------------------------------------------
    // IMPORTANT
    //
    // First order starts the 48-hour billing period.
    //
    // Example:
    //
    // First order:
    // 13 Aug 2026 11:20:30
    //
    // Bill:
    // 15 Aug 2026 11:20:30
    //
    // -------------------------------------------------------------------------

    final firstOrder =
        orders.first;

    final firstOrderTime =
        BillingService.getOrderCreatedAt(
      firstOrder,
    );

    final maturityTime =
        firstOrderTime.add(
      const Duration(hours: 48),
    );

    final now =
        DateTime.now();

    final isUnlocked =
        !now.isBefore(
      maturityTime,
    );

    double total = 0;

    bool allPaid = true;

    for (final order in orders) {
      total += BillingService.parseAmount(
        order['totalAmount'],
      );

      if ((order['paymentStatus'] ??
              'Pending') !=
          'Paid') {
        allPaid = false;
      }
    }

    return {
      'billNumber': 1,

      'cycleId':
          'bill_${firstOrder['id']}_${firstOrderTime.millisecondsSinceEpoch}',

      'orders': orders,

      'firstOrderTime':
          firstOrderTime,

      'maturityTime':
          maturityTime,

      'totalAmount':
          total,

      'paymentStatus':
          allPaid ? 'Paid' : 'Pending',

      'isUnlocked':
          isUnlocked,
    };
  }

  // ===========================================================================
  // EXACT REMAINING TIME
  // ===========================================================================

  Duration _getRemainingTime() {
    if (_billingCycle == null) {
      return Duration.zero;
    }

    final maturity =
        _billingCycle!['maturityTime']
            as DateTime;

    final now =
        DateTime.now();

    if (!maturity.isAfter(now)) {
      return Duration.zero;
    }

    return maturity.difference(now);
  }

  // ===========================================================================
  // COUNTDOWN
  // ===========================================================================

  String _formatCountdown(
    Duration duration,
  ) {
    final totalSeconds =
        duration.inSeconds;

    if (totalSeconds <= 0) {
      return '00d 00h 00m 00s';
    }

    final days =
        totalSeconds ~/ 86400;

    final hours =
        (totalSeconds % 86400) ~/ 3600;

    final minutes =
        (totalSeconds % 3600) ~/ 60;

    final seconds =
        totalSeconds % 60;

    return '${days.toString().padLeft(2, '0')}d '
        '${hours.toString().padLeft(2, '0')}h '
        '${minutes.toString().padLeft(2, '0')}m '
        '${seconds.toString().padLeft(2, '0')}s';
  }

  // ===========================================================================
  // DOWNLOAD / PRINT PDF
  // ===========================================================================

  Future<void> _downloadPdf() async {
    if (_billingCycle == null) return;

    final unlocked =
        _billingCycle!['isUnlocked'] ==
            true;

    if (!unlocked) {
      _showMessage(
        'Bill will be available after exactly 48 hours.',
      );

      return;
    }

    try {
      await BillingService.printBill(
        customer:
            widget.customer,
        cycle:
            _billingCycle!,
      );
    } catch (e) {
      _showMessage(
        'Could not generate PDF: $e',
      );
    }
  }

  // ===========================================================================
  // UPI URI
  // ===========================================================================

  String _getUpiUri() {
    final amount =
        BillingService.parseAmount(
      _billingCycle?['totalAmount'],
    );

    final billNumber =
        _billingCycle?['billNumber']
                ?.toString() ??
            '1';

    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': adminUpiId,
        'pn': adminName,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        'tn':
            'Viraj Dairy Bill #$billNumber',
      },
    );

    return uri.toString();
  }

  // ===========================================================================
  // OPEN UPI APP
  // ===========================================================================

  Future<void> _payUsingUpiApp() async {
    if (_billingCycle == null) return;

    if (_billingCycle!['isUnlocked'] !=
        true) {
      _showMessage(
        'Payment is locked until the 48-hour bill window is complete.',
      );

      return;
    }

    if (_billingCycle!['paymentStatus'] ==
        'Paid') {
      _showMessage(
        'This bill is already paid.',
      );

      return;
    }

    final uri =
        Uri.parse(
      _getUpiUri(),
    );

    try {
      final launched =
          await launchUrl(
        uri,
        mode:
            LaunchMode.externalApplication,
      );

      if (!launched) {
        _showMessage(
          'No UPI payment application found on this device.',
        );
      }
    } catch (e) {
      _showMessage(
        'Unable to open UPI payment app.',
      );
    }
  }

  // ===========================================================================
  // MESSAGE
  // ===========================================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }

  // ===========================================================================
  // FORMAT DATE
  // ===========================================================================

  String _formatDateTime(
    DateTime date,
  ) {
    final local =
        date.toLocal();

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

    return '$day/$month/$year '
        '$hour:$minute:$second';
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (_customerOrders.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text('My Billing'),
          backgroundColor:
              const Color(0xFF1E3A8A),
          foregroundColor:
              Colors.white,
        ),
        body:
            const Center(
          child:
              Text(
            'No orders found.',
          ),
        ),
      );
    }

    final cycle =
        _billingCycle!;

    final firstOrderTime =
        cycle['firstOrderTime']
            as DateTime;

    final maturityTime =
        cycle['maturityTime']
            as DateTime;

    final remaining =
        _getRemainingTime();

    final isUnlocked =
        !maturityTime.isAfter(
      DateTime.now(),
    );

    final totalAmount =
        BillingService.parseAmount(
      cycle['totalAmount'],
    );

    final isPaid =
        cycle['paymentStatus'] ==
            'Paid';

    return Scaffold(
      backgroundColor:
          const Color(0xFFF5F7FB),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFF1E3A8A),

        foregroundColor:
            Colors.white,

        title:
            const Text(
          'My Bills & Payments',
          style: TextStyle(
            fontSize: 17,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            icon:
                const Icon(Icons.refresh),

            onPressed:
                _loadBilling,
          ),
        ],
      ),

      body:
          RefreshIndicator(
        onRefresh:
            _loadBilling,

        child:
            SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(),

          padding:
              const EdgeInsets.all(16),

          child:
              Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [
              // ===============================================================
              // CUSTOMER CARD
              // ===============================================================

              Card(
                elevation: 2,

                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                ),

                child:
                    Padding(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),

                  child:
                      Row(
                    children: [
                      CircleAvatar(
                        radius:
                            28,

                        backgroundColor:
                            const Color(
                          0xFFE0E7FF,
                        ),

                        child:
                            const Icon(
                          Icons.person,
                          color:
                              Color(
                            0xFF1E3A8A,
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      Expanded(
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [
                            Text(
                              widget.customer['name'] ??
                                  'Customer',
                              style:
                                  const TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight
                                        .bold,
                                color: Color(
                                  0xFF1E293B,
                                ),
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              'Mobile: ${widget.customer['mobile'] ?? ''}',
                              style:
                                  const TextStyle(
                                fontSize: 13,
                                color: Color(
                                  0xFF64748B,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ===============================================================
              // BILLING STATUS & COUNTDOWN CARD
              // ===============================================================

              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '48-Hour Billing Status',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  FontWeight.bold,
                              color: Color(
                                0xFF1E3A8A,
                              ),
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration:
                                BoxDecoration(
                              color: isPaid
                                  ? Colors
                                      .green
                                      .withOpacity(
                                          0.1)
                                  : isUnlocked
                                      ? Colors
                                          .orange
                                          .withOpacity(
                                              0.1)
                                      : Colors.blue
                                          .withOpacity(
                                              0.1),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                12,
                              ),
                            ),
                            child: Text(
                              isPaid
                                  ? 'Paid'
                                  : isUnlocked
                                      ? 'Unlocked'
                                      : 'Locked',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    FontWeight.bold,
                                color: isPaid
                                    ? Colors
                                        .green[700]
                                    : isUnlocked
                                        ? Colors
                                            .orange[700]
                                        : Colors
                                            .blue[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'First Order Time:',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(
                                0xFF64748B,
                              ),
                            ),
                          ),
                          Text(
                            _formatDateTime(
                              firstOrderTime,
                            ),
                            style:
                                const TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w600,
                              color: Color(
                                0xFF1E293B,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Bill Unlocks At:',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(
                                0xFF64748B,
                              ),
                            ),
                          ),
                          Text(
                            _formatDateTime(
                              maturityTime,
                            ),
                            style:
                                const TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w600,
                              color: Color(
                                0xFF1E293B,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!isUnlocked) ...[
                        Container(
                          padding:
                              const EdgeInsets.all(
                            12,
                          ),
                          decoration:
                              BoxDecoration(
                            color: const Color(
                              0xFFFEF3C7,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              10,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.timer,
                                color: Color(
                                  0xFFD97706,
                                ),
                                size: 20,
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    const Text(
                                      'Time remaining until unlock:',
                                      style: TextStyle(
                                        fontSize:
                                            11,
                                        color: Color(
                                          0xFF92400E,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      height: 2,
                                    ),
                                    Text(
                                      _formatCountdown(
                                        remaining,
                                      ),
                                      style:
                                          const TextStyle(
                                        fontSize:
                                            15,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                        color: Color(
                                          0xFFB45309,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ===============================================================
              // TOTAL AMOUNT & PAYMENT ACTIONS CARD
              // ===============================================================

              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Bill Amount:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w600,
                              color: Color(
                                0xFF1E293B,
                              ),
                            ),
                          ),
                          Text(
                            '₹${totalAmount.toStringAsFixed(2)}',
                            style:
                                const TextStyle(
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                              color: Color(
                                0xFF1E3A8A,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _downloadPdf,
                              icon: const Icon(
                                Icons.picture_as_pdf,
                              ),
                              label: const Text(
                                'Download Bill',
                              ),
                              style:
                                  OutlinedButton
                                      .styleFrom(
                                foregroundColor:
                                    const Color(
                                  0xFF1E3A8A,
                                ),
                                side:
                                    const BorderSide(
                                  color: Color(
                                    0xFF1E3A8A,
                                  ),
                                ),
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  vertical: 12,
                                ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  (isUnlocked &&
                                          !isPaid)
                                      ? _payUsingUpiApp
                                      : null,
                              icon: const Icon(
                                Icons
                                    .payment_rounded,
                              ),
                              label: Text(
                                isPaid
                                    ? 'Paid'
                                    : 'Pay via UPI',
                              ),
                              style:
                                  ElevatedButton
                                      .styleFrom(
                                backgroundColor:
                                    const Color(
                                  0xFF1E3A8A,
                                ),
                                foregroundColor:
                                    Colors.white,
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  vertical: 12,
                                ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ===============================================================
              // QR CODE CARD (IF UNLOCKED & NOT PAID)
              // ===============================================================

              if (isUnlocked && !isPaid) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'Scan QR Code to Pay',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight.bold,
                            color: Color(
                              0xFF1E3A8A,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding:
                              const EdgeInsets.all(
                            12,
                          ),
                          decoration:
                              BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                            border:
                                Border.all(
                              color: Colors.grey
                                  .shade300,
                            ),
                          ),
                          child: QrImageView(
                            data: _getUpiUri(),
                            version:
                                QrVersions.auto,
                            size: 180.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'UPI ID: $adminUpiId',
                          style:
                              const TextStyle(
                            fontSize: 13,
                            color: Color(
                              0xFF64748B,
                            ),
                            fontWeight:
                                FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ===============================================================
              // ORDERS LIST HEADER
              // ===============================================================

              const Text(
                'Orders in this Billing Cycle',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),

              // ===============================================================
              // ORDERS LIST
              // ===============================================================

              ListView.builder(
                shrinkWrap: true,
                physics:
                    const NeverScrollableScrollPhysics(),
                itemCount:
                    _customerOrders.length,
                itemBuilder: (context, index) {
                  final order =
                      _customerOrders[index];

                  final createdAt =
                      BillingService.getOrderCreatedAt(
                    order,
                  );

                  final amount =
                      BillingService.parseAmount(
                    order['totalAmount'],
                  );

                  final paymentStatus =
                      order['paymentStatus'] ??
                          'Pending';

                  return Card(
                    elevation: 1,
                    margin:
                        const EdgeInsets.only(
                      bottom: 8,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      title: Text(
                        'Order #${order['id'] ?? (index + 1)}',
                        style:
                            const TextStyle(
                          fontSize: 14,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Created: ${_formatDateTime(createdAt)}',
                        style:
                            const TextStyle(
                          fontSize: 12,
                          color: Color(
                            0xFF64748B,
                          ),
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .end,
                        children: [
                          Text(
                            '₹${amount.toStringAsFixed(2)}',
                            style:
                                const TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.bold,
                              color: Color(
                                0xFF1E3A8A,
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 2,
                          ),
                          Text(
                            paymentStatus,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  FontWeight.w600,
                              color: paymentStatus ==
                                      'Paid'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}