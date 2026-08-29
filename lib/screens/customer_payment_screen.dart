// =============================================================================
// CUSTOMER PAYMENT SCREEN
// lib/screens/customer_payment_screen.dart
//
// UPDATED: Billing reflects ONLY orders whose delivery status is
// 'Completed' (i.e. the delivery boy has captured proof and marked the
// order delivered). Orders that are placed but not yet delivered are shown
// in a separate "Awaiting Delivery" card and are NOT counted in any bill.
// Cancelled orders (every product unavailable) are excluded from BOTH the
// bill and the "Awaiting Delivery" list entirely. Individual cancelled
// products inside a delivered order are excluded from that order's total
// automatically by BillingService.orderTotal() and are shown in BillCard.
//
// REMOVED: The "Live Order Tracking" countdown card (and the running-cycle
// computation that only fed it) has been removed from this screen. All
// other billing behavior is unchanged.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/database_service.dart';
import '../services/billing_service.dart';
import '../widgets/bill_card.dart';

class CustomerPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerPaymentScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerPaymentScreen> createState() => _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends State<CustomerPaymentScreen> {
  final DatabaseService _db = DatabaseService();

  Timer? _timer;

  static const String adminUpiId = '9850921154@paytm';
  static const String adminName = 'Viraj Dairy Admin';

  static const Set<String> _deliveredStatuses = {'Completed', 'Delivered'};

  bool _isOrderDelivered(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? '';
    return _deliveredStatuses.contains(status);
  }

  bool _isOrderCancelled(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? '';
    return status == 'Cancelled';
  }

  @override
  void initState() {
    super.initState();

    // Periodic re-render kept for the BillCard countdown (the bill window
    // unlock timer inside BillCard still ticks independently). This screen
    // no longer has its own countdown text, but BillCard benefits from the
    // parent rebuilding periodically so its unlock state stays fresh.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // UPI HELPERS
  // ===========================================================================

  String _getUpiUri(Map<String, dynamic> cycle) {
    final amount = BillingService.parseAmount(cycle['totalAmount']);
    final billNumber = cycle['billNumber']?.toString() ?? '1';

    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': adminUpiId,
        'pn': adminName,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'Viraj Dairy Bill #$billNumber',
      },
    );

    return uri.toString();
  }

  Future<void> _payUsingUpiApp(Map<String, dynamic> cycle) async {
    if (cycle['isUnlocked'] != true) {
      _showMessage('Payment is locked until the 48-hour bill window is complete.');
      return;
    }

    if (cycle['paymentStatus'] == 'Paid') {
      _showMessage('This bill is already paid.');
      return;
    }

    final uri = Uri.parse(_getUpiUri(cycle));

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched) {
        _showMessage('No UPI payment application found on this device.');
        return;
      }

      _showMessage(
        'UPI opened. After successful payment, an admin must confirm it before this bill shows Paid.',
      );
    } catch (e) {
      debugPrint('UPI error: $e');
      _showMessage('Unable to open UPI payment app.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================================================================
  // CUSTOMER HEADER CARD
  // ===========================================================================

  Widget _buildCustomerCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFE0E7FF),
              child: const Icon(Icons.person, color: Color(0xFF1E3A8A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer['name']?.toString() ?? 'Customer',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mobile: ${widget.customer['mobile'] ?? ''}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // AWAITING DELIVERY CARD
  //
  // Orders placed but not yet delivered AND not cancelled. Excluded from
  // every billing cycle until delivery is confirmed.
  // ===========================================================================

  Widget _buildAwaitingDeliveryCard(List<Map<String, dynamic>> pendingOrders) {
    if (pendingOrders.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 17, color: Color(0xFF92400E)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Awaiting Delivery',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                  ),
                ),
                Text(
                  '${pendingOrders.length} order${pendingOrders.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'These orders are placed but not yet delivered. They will be added to '
              'your bill only once the delivery is completed.',
              style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF92400E)),
            ),
            const SizedBox(height: 10),
            ...pendingOrders.map((order) {
              final orderId = order['id']?.toString() ?? '';
              final placedAt = BillingService.getOrderCreatedAt(order);
              final amt = BillingService.orderTotal(order);
              final status = order['status']?.toString() ?? 'Pending';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions, size: 16, color: Color(0xFF92400E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order #$orderId', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Text(
                            'Placed: ${BillingService.formatCalendarShort(placedAt)}',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${amt.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(
                          status,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ONE BILL BLOCK: shared BillCard + UPI pay/QR section underneath
  // ===========================================================================

  Widget _buildBillBlock(
    Map<String, dynamic> cycle,
    Map<String, Map<String, dynamic>> billDocsByCycleId,
  ) {
    final cycleId = cycle['cycleId']?.toString() ?? '';
    final billDoc = billDocsByCycleId[cycleId];

    final isUnlocked = cycle['isUnlocked'] == true;
    final isPaid = cycle['paymentStatus']?.toString() == 'Paid';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BillCard(
          customer: widget.customer,
          cycle: cycle,
          billDoc: billDoc,
          onChanged: () {
            if (mounted) setState(() {});
          },
        ),
        if (isUnlocked && !isPaid) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _payUsingUpiApp(cycle),
                      icon: const Icon(Icons.payment_rounded),
                      label: Text('Pay Bill #${cycle['billNumber']} via UPI'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Scan QR to Pay Bill #${cycle['billNumber']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                  const SizedBox(height: 10),
                  QrImageView(data: _getUpiUri(cycle), version: QrVersions.auto, size: 160),
                  const SizedBox(height: 6),
                  Text('UPI ID: $adminUpiId', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ),
        ] else if (isUnlocked) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8)),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, size: 17, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment completed. This billing cycle is closed.',
                      style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final mobile = widget.customer['mobile']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        title: const Text('My Bills & Payments', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(
              child: Row(
                children: [
                  Icon(Icons.circle, size: 9, color: Colors.greenAccent),
                  SizedBox(width: 5),
                  Text('Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.streamOrdersForCustomer(mobile),
        builder: (context, orderSnap) {
          if (orderSnap.connectionState == ConnectionState.waiting && !orderSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allOrders = orderSnap.data ?? [];

          // -----------------------------------------------------------------
          // SPLIT ORDERS:
          //  - billableOrders: delivered -> counted in billing cycles.
          //  - pendingOrders: not yet delivered AND not cancelled -> shown
          //    in "Awaiting Delivery", excluded from all bills.
          //  - Cancelled orders appear in neither list.
          // -----------------------------------------------------------------

          final billableOrders = allOrders.where(_isOrderDelivered).toList();
          final pendingOrders = allOrders
              .where((o) => !_isOrderDelivered(o) && !_isOrderCancelled(o))
              .toList();

          final cycles = BillingService.buildCustomerCycles(billableOrders).reversed.toList();

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db.streamGeneratedBillsForCustomer(mobile),
            builder: (context, billSnap) {
              final bills = billSnap.data ?? [];

              final Map<String, Map<String, dynamic>> billDocsByCycleId = {
                for (final b in bills)
                  if (b['cycleId'] != null) b['cycleId'].toString(): b,
              };

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCustomerCard(),
                      const SizedBox(height: 18),
                      _buildAwaitingDeliveryCard(pendingOrders),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF1D4ED8)),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '48-Hour Billing Rule',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Each bill starts the moment a DELIVERED order first joins an open '
                                    'cycle and covers exactly the next 48 hours. Any order delivered inside '
                                    'that window joins the same bill. Once the window closes, the next '
                                    'delivered order automatically starts a brand new bill — even if that '
                                    'is days or months later. Orders that are placed but not yet delivered, '
                                    'and orders cancelled by delivery, never affect any bill. Individual '
                                    'products marked unavailable inside a delivered order are also excluded '
                                    'from that order\'s amount.',
                                    style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF1E3A8A)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Billing History',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                          ),
                          Text(
                            '${cycles.length} Bill${cycles.length == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (allOrders.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.receipt_long, size: 50, color: Colors.grey.shade400),
                                  const SizedBox(height: 10),
                                  const Text('No orders found.', style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                          ),
                        )
                      else if (billableOrders.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.local_shipping_outlined, size: 50, color: Colors.grey.shade400),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'No bills yet — your orders will appear here once delivered.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ...cycles.map((c) => _buildBillBlock(c, billDocsByCycleId)),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}