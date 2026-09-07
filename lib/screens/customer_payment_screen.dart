// =============================================================================
// CUSTOMER PAYMENT SCREEN
// lib/screens/customer_payment_screen.dart
//
// PAYMENT RULES
// 1. Only delivered orders are billed.
// 2. A bill is payable only after its 48-hour window is unlocked.
// 3. NEVER mark a bill Paid for SUBMITTED, FAILURE, CANCELLED or UNKNOWN.
// 4. A bill is marked Paid only after the UPI app returns SUCCESS.
// 5. The same transaction cannot be submitted twice while it is in progress.
// 6. After SUCCESS, both the cycle orders and generated bill are updated.
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
  State<CustomerPaymentScreen> createState() =>
      _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends State<CustomerPaymentScreen> {
  final DatabaseService _db = DatabaseService();
  final UpiIndia _upiIndia = UpiIndia();

  Timer? _refreshTimer;

  // IMPORTANT:
  // This must be the REAL receiving UPI ID belonging to the dairy.
  // Do not use a personal/request-money UPI ID for production payments.
  static const String adminUpiId = '9850921154@paytm';

  // Keep this name identical to the verified name shown by the receiving
  // UPI account/merchant profile.
  static const String adminName = 'Viraj Dudh Dairy';

  static const Set<String> _deliveredStatuses = <String>{
    'Completed',
    'Delivered',
  };

  String? _busyCycleId;

  bool get _androidUpiFlowSupported => !kIsWeb && Platform.isAndroid;

  // ---------------------------------------------------------------------------
  // ORDER HELPERS
  // ---------------------------------------------------------------------------

  bool _isOrderDelivered(Map<String, dynamic> order) {
    final status = order['status']?.toString().trim() ?? '';
    return _deliveredStatuses.contains(status);
  }

  bool _isOrderCancelled(Map<String, dynamic> order) {
    final status = order['status']?.toString().trim() ?? '';
    return status.toLowerCase() == 'cancelled';
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Only forces BillCard to rebuild its unlock/countdown state.
    // It does NOT modify a billing cycle.
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UPI
  // ---------------------------------------------------------------------------

  String _transactionRefId(Map<String, dynamic> cycle) {
    final cycleId = cycle['cycleId']?.toString().trim() ?? '';
    final billNumber = cycle['billNumber']?.toString().trim() ?? '1';

    // cycleId is deterministic for the bill, so retrying the same bill keeps
    // the same application reference instead of generating a new random ref.
    final safeCycleId =
        cycleId.isEmpty ? 'C${DateTime.now().millisecondsSinceEpoch}' : cycleId;

    return 'VDBILL$billNumber-$safeCycleId';
  }

  String _getUpiUri(Map<String, dynamic> cycle) {
    final amount = BillingService.parseAmount(cycle['totalAmount']);
    final billNumber = cycle['billNumber']?.toString() ?? '1';

    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: <String, String>{
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

  Future<void> _payUsingUpi(Map<String, dynamic> cycle) async {
    final isUnlocked = cycle['isUnlocked'] == true;
    final paymentStatus =
        cycle['paymentStatus']?.toString().trim().toLowerCase() ?? 'pending';

    if (!isUnlocked) {
      _showMessage(
        'Payment is locked until the 48-hour billing window is complete.',
        error: true,
      );
      return;
    }

    if (paymentStatus == 'paid') {
      _showMessage('This bill is already paid.');
      return;
    }

    final cycleId = cycle['cycleId']?.toString() ?? '';

    if (cycleId.isEmpty) {
      _showMessage(
        'Unable to start payment because this bill has no cycle ID.',
        error: true,
      );
      return;
    }

    if (_busyCycleId != null) {
      _showMessage('Another payment is already in progress.');
      return;
    }

    if (_androidUpiFlowSupported) {
      await _payWithAndroidUpi(cycle);
    } else {
      await _payWithExternalUpi(cycle);
    }
  }

  Future<void> _payWithAndroidUpi(Map<String, dynamic> cycle) async {
    final cycleId = cycle['cycleId']?.toString() ?? '';

    if (!mounted) return;
    setState(() => _busyCycleId = cycleId);

    try {
      final apps = await _upiIndia.getAllUpiApps(
        mandatoryTransactionId: false,
      );

      if (apps.isEmpty) {
        _showMessage(
          'No UPI app was found. Install Google Pay, PhonePe or Paytm.',
          error: true,
        );
        return;
      }

      UpiApp? selectedApp;

      if (apps.length == 1) {
        selectedApp = apps.first;
      } else if (mounted) {
        selectedApp = await _showUpiAppPicker(apps);
      }

      if (selectedApp == null) {
        return;
      }

      final amount = BillingService.parseAmount(cycle['totalAmount']);

      if (amount <= 0) {
        _showMessage(
          'Invalid bill amount. Payment cannot be started.',
          error: true,
        );
        return;
      }

      final billNumber = cycle['billNumber']?.toString() ?? '1';
      final reference = _transactionRefId(cycle);

      _showMessage('Opening ${selectedApp.name}...');

      final UpiResponse response = await _upiIndia.startTransaction(
        app: selectedApp,
        receiverUpiId: adminUpiId,
        receiverName: adminName,
        transactionRefId: reference,
        transactionNote: 'Viraj Dairy Bill #$billNumber',
        amount: amount,
      );

      await _handleUpiResponse(
        response: response,
        cycle: cycle,
        appName: selectedApp.name,
      );
    } on UpiIndiaUserCancelledException {
      _showMessage('Payment cancelled. The bill is still Pending.');
    } on UpiIndiaNullResponseException {
      _showMessage(
        'The UPI app did not return a payment result. The bill is still Pending.',
        error: true,
      );
    } on UpiIndiaAppNotInstalledException {
      _showMessage(
        'The selected UPI app is not installed.',
        error: true,
      );
    } on UpiIndiaInvalidParametersException {
      _showMessage(
        'The UPI app rejected the payment request. '
        'Please verify the dairy UPI ID and try again.',
        error: true,
      );
    } on UpiIndiaActivityMissingException {
      _showMessage(
        'Unable to open the selected UPI app.',
        error: true,
      );
    } catch (e, stackTrace) {
      debugPrint('UPI payment exception: $e');
      debugPrintStack(stackTrace: stackTrace);

      _showMessage(
        'Payment was not completed. The bill remains Pending.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyCycleId = null);
      }
    }
  }

  Future<UpiApp?> _showUpiAppPicker(List<UpiApp> apps) {
    return showModalBottomSheet<UpiApp>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose a UPI app',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Divider(height: 1),
                ...apps.map(
                  (app) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                    ),
                    leading: app.icon.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              app.icon,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const CircleAvatar(
                            child: Icon(Icons.account_balance_wallet),
                          ),
                    title: Text(
                      app.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop(app);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _payWithExternalUpi(Map<String, dynamic> cycle) async {
    final uri = Uri.parse(_getUpiUri(cycle));

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _showMessage(
          'No UPI payment application could be opened.',
          error: true,
        );
        return;
      }

      // IMPORTANT:
      // We do NOT mark the bill paid here because url_launcher does not give
      // us a trustworthy payment result.
      _showExternalPaymentInstructions(cycle);
    } catch (e, stackTrace) {
      debugPrint('External UPI error: $e');
      debugPrintStack(stackTrace: stackTrace);

      _showMessage(
        'Unable to open the UPI payment application.',
        error: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PAYMENT RESULT
  // ---------------------------------------------------------------------------

  Future<void> _handleUpiResponse({
    required UpiResponse response,
    required Map<String, dynamic> cycle,
    required String appName,
  }) async {
    final status = (response.status ?? '').toUpperCase().trim();

    final transactionId = response.transactionId?.trim().isNotEmpty == true
        ? response.transactionId!.trim()
        : _transactionRefId(cycle);

    debugPrint(
      'UPI result: app=$appName status=$status transactionId=$transactionId',
    );

    switch (status) {
      case 'SUCCESS':
        await _completeSuccessfulPayment(
          cycle: cycle,
          transactionId: transactionId,
          appName: appName,
        );
        break;

      case 'SUBMITTED':
        // NEVER call markCycleOrdersPaid() here.
        // SUBMITTED is not the same as SUCCESS.
        _showPendingPaymentDialog(
          cycle: cycle,
          transactionId: transactionId,
        );
        break;

      case 'FAILURE':
        _showMessage(
          'Payment failed or was cancelled in $appName. '
          'Bill #${cycle['billNumber']} is still Pending.',
          error: true,
        );
        break;

      default:
        // Unknown/empty response must remain unpaid.
        _showMessage(
          'UPI returned an unknown payment status. '
          'Bill #${cycle['billNumber']} is still Pending.',
          error: true,
        );
        break;
    }
  }

  Future<void> _completeSuccessfulPayment({
    required Map<String, dynamic> cycle,
    required String transactionId,
    required String appName,
  }) async {
    final cycleId = cycle['cycleId']?.toString() ?? '';
    final mobile = widget.customer['mobile']?.toString() ?? '';
    final customerName = widget.customer['name']?.toString();

    if (cycleId.isEmpty || mobile.isEmpty) {
      _showMessage(
        'Payment returned SUCCESS, but bill information is incomplete. '
        'Please contact the administrator with transaction ID $transactionId.',
        error: true,
      );
      return;
    }

    final billNumber = cycle['billNumber'] is int
        ? cycle['billNumber'] as int
        : int.tryParse(cycle['billNumber']?.toString() ?? '');

    final totalAmount = BillingService.parseAmount(
      cycle['totalAmount'],
    );

    try {
      // These two writes are the ONLY place where this screen marks the
      // payment as completed.
      //
      // Existing DatabaseService methods are reused so the admin dashboard
      // and customer screen receive the same Firestore payment state.
      await _db.markCycleOrdersPaid(
        cycleOrders: List<Map<String, dynamic>>.from(
          cycle['orders'] ?? const [],
        ),
        paymentId: transactionId,
      );

      await _db.markGeneratedBillPaid(
        cycleId: cycleId,
        customerMobile: mobile,
        paymentId: transactionId,
        customerName: customerName,
        billNumber: billNumber,
        totalAmount: totalAmount,
      );

      if (!mounted) return;

      setState(() {});

      await _showPaymentCompletedDialog(
        billNumber: cycle['billNumber']?.toString() ?? '',
        amount: totalAmount,
        transactionId: transactionId,
        appName: appName,
      );
    } catch (e, stackTrace) {
      debugPrint('Payment Firestore update error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      // Do not show a false "completed" UI when Firestore could not save it.
      _showMessage(
        'UPI reported SUCCESS, but the bill could not be updated. '
        'Transaction ID: $transactionId',
        error: true,
        duration: const Duration(seconds: 7),
      );
    }
  }

  Future<void> _showPaymentCompletedDialog({
    required String billNumber,
    required double amount,
    required String transactionId,
    required String appName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          contentPadding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 48,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Payment Completed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF166534),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bill #$billNumber has been marked as Paid.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 18),
              _successRow('Amount', '₹${amount.toStringAsFixed(2)}'),
              _successRow('App', appName),
              _successRow('Transaction ID', transactionId),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('DONE'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _successRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPendingPaymentDialog({
    required Map<String, dynamic> cycle,
    required String transactionId,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Payment Pending'),
          content: Text(
            'The UPI app submitted the transaction, but it did not return '
            'SUCCESS.\n\n'
            'Bill #${cycle['billNumber']} will remain Pending until the '
            'payment is actually confirmed.\n\n'
            'Transaction ID:\n$transactionId',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showExternalPaymentInstructions(
    Map<String, dynamic> cycle,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('UPI App Opened'),
          content: Text(
            'Complete the payment in your UPI app.\n\n'
            'Bill #${cycle['billNumber']} is NOT marked Paid automatically '
            'from this link because the app cannot safely read the final '
            'bank result.\n\n'
            'If your app reports a failed/risk-policy payment, the bill '
            'will remain Pending.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MESSAGES
  // ---------------------------------------------------------------------------

  void _showMessage(
    String message, {
    bool error = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              error ? const Color(0xFFB91C1C) : const Color(0xFF166534),
          content: Text(message),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // CUSTOMER CARD
  // ---------------------------------------------------------------------------

  Widget _buildCustomerCard() {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFFE0E7FF),
              child: Icon(
                Icons.person,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer['name']?.toString() ?? 'Customer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mobile: ${widget.customer['mobile'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AWAITING DELIVERY
  // ---------------------------------------------------------------------------

  Widget _buildAwaitingDeliveryCard(
    List<Map<String, dynamic>> pendingOrders,
  ) {
    if (pendingOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFFDE68A),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: Color(0xFF92400E),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Awaiting Delivery',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
                Text(
                  '${pendingOrders.length} order'
                  '${pendingOrders.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF92400E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            const Text(
              'These orders are not included in billing until delivery is '
              'completed.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: Color(0xFF92400E),
              ),
            ),
            const SizedBox(height: 10),
            ...pendingOrders.map((order) {
              final orderId = order['id']?.toString() ?? '';
              final placedAt =
                  BillingService.getOrderCreatedAt(order);
              final amount = BillingService.orderTotal(order);
              final status =
                  order['status']?.toString() ?? 'Pending';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pending_actions,
                      size: 16,
                      color: Color(0xFF92400E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #$orderId',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Placed: '
                            '${BillingService.formatCalendarShort(placedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          status,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF92400E),
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

  // ---------------------------------------------------------------------------
  // BILL + PAYMENT
  // ---------------------------------------------------------------------------

  Widget _buildBillBlock(
    Map<String, dynamic> cycle,
    Map<String, Map<String, dynamic>> billDocsByCycleId,
  ) {
    final cycleId = cycle['cycleId']?.toString() ?? '';
    final billDoc = billDocsByCycleId[cycleId];

    final isUnlocked = cycle['isUnlocked'] == true;
    final isPaid =
        cycle['paymentStatus']?.toString().trim().toLowerCase() == 'paid';
    final isBusy = _busyCycleId == cycleId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
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

          // ---------------------------------------------------------------
          // UNPAID + UNLOCKED
          // ---------------------------------------------------------------
          if (isUnlocked && !isPaid)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 16,
                top: 4,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFDE68A),
                        ),
                      ),
                      child: const Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Color(0xFF92400E),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pay only after the bill is unlocked. '
                              'The bill becomes Paid only after the UPI '
                              'transaction returns SUCCESS.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isBusy
                            ? null
                            : () => _payUsingUpi(cycle),
                        icon: isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.account_balance_wallet_rounded,
                              ),
                        label: Text(
                          isBusy
                              ? 'Waiting for UPI app...'
                              : 'Pay Bill #${cycle['billNumber']} via UPI',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 13,
                            horizontal: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Scan QR to Pay',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade200,
                        ),
                      ),
                      child: QrImageView(
                        data: _getUpiUri(cycle),
                        version: QrVersions.auto,
                        size: 180,
                        gapless: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      adminUpiId,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Viraj Dudh Dairy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ---------------------------------------------------------------
          // PAID
          // ---------------------------------------------------------------
          if (isPaid)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 16,
                top: 4,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFBBF7D0),
                  ),
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Completed',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Bill #${cycle['billNumber']} is Paid and closed.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

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
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 9,
                    color: Colors.greenAccent,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.streamOrdersForCustomer(mobile),
        builder: (context, orderSnap) {
          if (orderSnap.connectionState ==
                  ConnectionState.waiting &&
              !orderSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final allOrders = orderSnap.data ?? <Map<String, dynamic>>[];

          final billableOrders =
              allOrders.where(_isOrderDelivered).toList();

          final pendingOrders = allOrders
              .where(
                (order) =>
                    !_isOrderDelivered(order) &&
                    !_isOrderCancelled(order),
              )
              .toList();

          final cycles = BillingService
              .buildCustomerCycles(billableOrders)
              .reversed
              .toList();

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _db.streamGeneratedBillsForCustomer(mobile),
            builder: (context, billSnap) {
              final bills =
                  billSnap.data ?? <Map<String, dynamic>>[];

              final billDocsByCycleId =
                  <String, Map<String, dynamic>>{
                for (final bill in bills)
                  if (bill['cycleId'] != null)
                    bill['cycleId'].toString(): bill,
              };

              return RefreshIndicator(
                onRefresh: () async {
                  if (mounted) {
                    setState(() {});
                  }
                },
                child: SingleChildScrollView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _buildCustomerCard(),
                      const SizedBox(height: 18),

                      _buildAwaitingDeliveryCard(
                        pendingOrders,
                      ),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius:
                              BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFBFDBFE),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Color(0xFF1D4ED8),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '48-Hour Billing Rule',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight:
                                          FontWeight.bold,
                                      color:
                                          Color(0xFF1E3A8A),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Each bill starts from the first delivered '
                                    'order and covers exactly 48 hours. Orders '
                                    'delivered inside that window join the same '
                                    'bill. Orders delivered after the window '
                                    'start a new bill. Undelivered and cancelled '
                                    'orders do not affect billing.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                      color:
                                          Color(0xFF1E3A8A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Billing History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            '${cycles.length} Bill'
                            '${cycles.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
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
                                  Icon(
                                    Icons.receipt_long,
                                    size: 50,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'No orders found.',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color:
                                          Color(0xFF64748B),
                                    ),
                                  ),
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
                                  Icon(
                                    Icons
                                        .local_shipping_outlined,
                                    size: 50,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'No bills yet — your orders '
                                    'will appear here once delivered.',
                                    textAlign:
                                        TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ...cycles.map(
                          (cycle) => _buildBillBlock(
                            cycle,
                            billDocsByCycleId,
                          ),
                        ),

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
