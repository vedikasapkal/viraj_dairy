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
//
// NEW IN THIS VERSION — AUTOMATIC PAYMENT CONFIRMATION
// -----------------------------------------------------------------------------
// - "Pay via UPI" now launches the chosen UPI app using upi_india's
//   startActivityForResult-based transaction, NOT a bare url_launcher deep
//   link. That is the only way an app gets a real response (SUCCESS /
//   SUBMITTED / FAILURE + transaction id) back from GPay/PhonePe/Paytm once
//   the user returns to this screen — a plain `upi://pay` link launched via
//   url_launcher hands off control with no way back, which is why the old
//   code needed an admin to manually confirm every payment.
// - On a genuine SUCCESS response, the app immediately calls
//   DatabaseService.markCycleOrdersPaid() + markGeneratedBillPaid(). Both
//   this screen (via its Firestore streams) and the admin dashboard (via its
//   12s silent refresh) pick up the change on their own — no extra wiring
//   needed, nothing "shows Payment Completed" only on one side.
// - The QR code below the button is rendered once from a plain string via
//   QrImageView and is never hidden, regenerated, or put behind a timer —
//   there was nothing in the original code causing it to expire, and this
//   version does not add one. If a UPI app itself shows a "payment may
//   fail" banner, that message is coming from that UPI app's own risk
//   checks (e.g. Paytm's), not from anything in this screen.
// - On iOS, upi_india's app-list + transaction-result flow is not
//   available (iOS has no equivalent intent-result API), so the button
//   opens the UPI link the same way as before and the payment still needs
//   an admin's manual "Mark Paid" (see admin_dashboard.dart) to close out.
// =============================================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:upi_india/upi_india.dart';
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
  final UpiIndia _upiIndia = UpiIndia();

  Timer? _timer;

  static const String adminUpiId = '9850921154@paytm';
  static const String adminName = 'Viraj Dairy Admin';

  static const Set<String> _deliveredStatuses = {'Completed', 'Delivered'};

  // Tracks which cycleId currently has a payment in flight so only that
  // bill's button shows a spinner (and gets disabled) while a UPI app is
  // being talked to.
  String? _busyCycleId;

  bool get _upiAppFlowSupported => !kIsWeb && Platform.isAndroid;

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

  String _transactionRefId(Map<String, dynamic> cycle) {
    final cycleId = cycle['cycleId']?.toString() ?? '';
    final billNumber = cycle['billNumber']?.toString() ?? '1';
    return 'BILL$billNumber-${cycleId.isNotEmpty ? cycleId : DateTime.now().millisecondsSinceEpoch}';
  }

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
        'tr': _transactionRefId(cycle),
      },
    );

    return uri.toString();
  }

  // ---------------------------------------------------------------------------
  // MAIN ENTRY POINT: "Pay Bill via UPI" button
  // ---------------------------------------------------------------------------

  Future<void> _payUsingUpiApp(Map<String, dynamic> cycle) async {
    if (cycle['isUnlocked'] != true) {
      _showMessage('Payment is locked until the 48-hour bill window is complete.');
      return;
    }

    if (cycle['paymentStatus'] == 'Paid') {
      _showMessage('This bill is already paid.');
      return;
    }

    if (_upiAppFlowSupported) {
      await _payWithResultConfirmation(cycle);
    } else {
      // iOS / web fallback: no app-result API available, so this can only
      // open the link and still needs an admin to confirm afterwards.
      await _payWithLinkOnly(cycle);
    }
  }

  /// Android path: launches a chosen UPI app for a real, awaited result and
  /// auto-confirms the bill the moment that app reports SUCCESS.
  Future<void> _payWithResultConfirmation(Map<String, dynamic> cycle) async {
    final cycleId = cycle['cycleId']?.toString() ?? '';

    setState(() => _busyCycleId = cycleId);

    try {
      final List<UpiApp> apps = await _upiIndia.getAllUpiApps(mandatoryTransactionId: false);

      if (apps.isEmpty) {
        _showMessage('No UPI apps found on this device. Install GPay, PhonePe, or Paytm to pay.');
        return;
      }

      UpiApp? chosenApp = apps.first;

      if (apps.length > 1 && mounted) {
        chosenApp = await showModalBottomSheet<UpiApp>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (sheetContext) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 16, 18, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose a UPI app',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ...apps.map((app) {
                    return ListTile(
                      leading: Image.memory(app.icon, width: 32, height: 32),
                      title: Text(app.name),
                      onTap: () => Navigator.pop(sheetContext, app),
                    );
                  }),
                  const SizedBox(height: 6),
                ],
              ),
            );
          },
        );
      }

      if (chosenApp == null) return; // user dismissed the picker

      final double amount = BillingService.parseAmount(cycle['totalAmount']);
      final String billNumber = cycle['billNumber']?.toString() ?? '1';

      final UpiResponse response = await _upiIndia.startTransaction(
        app: chosenApp,
        receiverUpiId: adminUpiId,
        receiverName: adminName,
        transactionRefId: _transactionRefId(cycle),
        transactionNote: 'Viraj Dairy Bill #$billNumber',
        amount: amount,
      );

      await _handleUpiResponse(response, cycle);
    } catch (e) {
      // upi_india throws rather than returning a failure UpiResponse, so
      // landing here usually means the payment was cancelled/failed inside
      // the UPI app, not that it failed to launch.
      debugPrint('UPI transaction error/cancelled: $e');
      _showMessage(
        'Payment was not completed (cancelled or failed in the UPI app). '
        'If money was deducted, please contact the admin.',
      );
    } finally {
      if (mounted) setState(() => _busyCycleId = null);
    }
  }

  /// iOS / web fallback: same as the previous behavior — opens the UPI
  /// link externally with no way to read a result back, so the bill still
  /// needs an admin's manual confirmation.
  Future<void> _payWithLinkOnly(Map<String, dynamic> cycle) async {
    final uri = Uri.parse(_getUpiUri(cycle));

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched) {
        _showMessage('No UPI payment application found on this device.');
        return;
      }

      _showMessage(
        'UPI app opened. After completing payment, an admin will confirm it here — '
        'automatic confirmation on this device is only available on Android.',
      );
    } catch (e) {
      debugPrint('UPI link error: $e');
      _showMessage('Unable to open UPI payment app.');
    }
  }

  Future<void> _handleUpiResponse(UpiResponse response, Map<String, dynamic> cycle) async {
    final String status = (response.status ?? '').toUpperCase().trim();
    final String txnId = (response.transactionId?.isNotEmpty == true)
        ? response.transactionId!
        : _transactionRefId(cycle);

    if (status == 'SUCCESS') {
      final cycleOrders = List<Map<String, dynamic>>.from(cycle['orders'] ?? []);
      final cycleId = cycle['cycleId']?.toString() ?? '';
      final mobile = widget.customer['mobile']?.toString() ?? '';
      final billNumber = cycle['billNumber'] is int
          ? cycle['billNumber'] as int
          : int.tryParse(cycle['billNumber']?.toString() ?? '');
      final totalAmount = BillingService.parseAmount(cycle['totalAmount']);

      await _db.markCycleOrdersPaid(cycleOrders: cycleOrders, paymentId: txnId);
      await _db.markGeneratedBillPaid(
        cycleId: cycleId,
        customerMobile: mobile,
        paymentId: txnId,
        customerName: widget.customer['name']?.toString(),
        billNumber: billNumber,
        totalAmount: totalAmount,
      );

      if (!mounted) return;
      setState(() {}); // the Firestore streams will also push this shortly
      _showMessage('Payment successful — Bill #${cycle['billNumber']} marked as Paid.');
    } else if (status == 'SUBMITTED') {
      _showMessage(
        'Payment submitted and awaiting confirmation from your bank/UPI app. '
        'If it succeeds, this bill will update automatically within a minute — '
        'otherwise please try again.',
      );
    } else if (status == 'FAILURE') {
      _showMessage('Payment failed or was cancelled. Please try again.');
    } else {
      _showMessage('Payment status unclear (received: "${status.isEmpty ? 'no response' : status}"). '
          'If money was deducted, please contact the admin with your UPI transaction id.');
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
  //
  // The QR block below is rendered unconditionally whenever the bill is
  // unlocked and unpaid — there is no timer, countdown, or hidden state
  // attached to it, so it never shows an "expired" state on its own.
  // ===========================================================================

  Widget _buildBillBlock(
    Map<String, dynamic> cycle,
    Map<String, Map<String, dynamic>> billDocsByCycleId,
  ) {
    final cycleId = cycle['cycleId']?.toString() ?? '';
    final billDoc = billDocsByCycleId[cycleId];

    final isUnlocked = cycle['isUnlocked'] == true;
    final isPaid = cycle['paymentStatus']?.toString() == 'Paid';
    final isBusy = _busyCycleId == cycleId;

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
                      onPressed: isBusy ? null : () => _payUsingUpiApp(cycle),
                      icon: isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.payment_rounded),
                      label: Text(
                        isBusy
                            ? 'Waiting for UPI app...'
                            : 'Pay Bill #${cycle['billNumber']} via UPI',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (!_upiAppFlowSupported) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Automatic confirmation is available on Android. On this device, '
                      'an admin will confirm your payment after you pay.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Scan QR to Pay Bill #${cycle['billNumber']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                  const SizedBox(height: 10),
                  // Static QR — generated once from the UPI string, never
                  // hidden/regenerated/timed out.
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