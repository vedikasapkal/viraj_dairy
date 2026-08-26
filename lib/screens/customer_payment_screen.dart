// =============================================================================
// CUSTOMER PAYMENT SCREEN
// lib/screens/customer_payment_screen.dart
//
// UPDATED: WhatsApp functionality removed from customer view.
// -----------------------------------------------------------------------------
// Everything else (BillCard per bill, UPI pay + QR section, live order tracking,
// and the 48-hour rule info box) remains intact and fully functional.
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

  @override
  void initState() {
    super.initState();

    // Only re-renders the countdown text every second — never touches or
    // recomputes billing cycles itself, so it can't cause any drift. The
    // actual data still comes live from the Firestore streams below.
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
  // UPI HELPERS (customer-side payment, kept separate from BillCard)
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

      // IMPORTANT: opening the UPI app does not mean payment succeeded.
      // paymentStatus only becomes "Paid" once your backend/admin confirms
      // it in Firestore — this screen never marks it Paid on its own.
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
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
  // LIVE "CURRENT ORDER TRACKING" CARD
  // ===========================================================================

  Widget _buildLiveOrderTrackingCard(List<Map<String, dynamic>> runningOrders) {
    if (runningOrders.isEmpty) return const SizedBox.shrink();

    String liveCountdown(Map<String, dynamic> order) {
      final remaining = BillingService.getRemainingTime(order);
      if (remaining == Duration.zero) return 'Unlocking...';

      final h = remaining.inHours;
      final m = remaining.inMinutes % 60;
      final s = remaining.inSeconds % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Live Order Tracking',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                ),
                const Spacer(),
                Text(
                  '${runningOrders.length} in current bill',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...runningOrders.map((order) {
              final orderId = order['id']?.toString() ?? '';
              final placedAt = BillingService.getOrderCreatedAt(order);
              final amt = BillingService.orderTotal(order);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top, size: 16, color: Color(0xFF1E3A8A)),
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
                          liveCountdown(order),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
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

        // -----------------------------------------------------------------
        // UPI PAY BUTTON + QR — only while unlocked and unpaid.
        // -----------------------------------------------------------------
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Scan QR to Pay Bill #${cycle['billNumber']}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  QrImageView(data: _getUpiUri(cycle), version: QrVersions.auto, size: 160),
                  const SizedBox(height: 6),
                  Text(
                    'UPI ID: $adminUpiId',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
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
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
              ),
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
        title: const Text(
          'My Bills & Payments',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
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

          final orders = orderSnap.data ?? [];
          final cycles = BillingService.buildCustomerCycles(orders).reversed.toList();

          final runningCycle = cycles.firstWhere(
            (c) => c['isUnlocked'] != true,
            orElse: () => const {},
          );

          final runningOrders = runningCycle.isEmpty
              ? <Map<String, dynamic>>[]
              : List<Map<String, dynamic>>.from(runningCycle['orders'] ?? []);

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
                      _buildLiveOrderTrackingCard(runningOrders),
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Each bill starts the moment an order is placed and covers exactly the '
                                    'next 48 hours. Any order placed inside that window joins the same bill. '
                                    'Once the window closes, the next order automatically starts a brand new bill — '
                                    'even if that is days or months later.',
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
                      if (orders.isEmpty)
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