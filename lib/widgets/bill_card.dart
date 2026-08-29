// =============================================================================
// BILL CARD WIDGET
// lib/widgets/bill_card.dart
//
// UPDATED:
// - The remaining-time / unlock countdown now ticks on its own (1-second
//   internal Timer) instead of relying on whatever screen embeds this
//   widget to rebuild it. This fixes bills showing a stale/identical
//   "remaining" value.
// - Cancelled items (marked unavailable by delivery) are flagged per-order
//   and are already excluded from the total by BillingService.orderTotal().
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/billing_service.dart';
import '../services/database_service.dart';
import '../services/bill_automation_service.dart';

class BillCard extends StatefulWidget {
  final Map<String, dynamic> customer;
  final Map<String, dynamic> cycle;
  final Map<String, dynamic>? billDoc;
  final VoidCallback? onChanged;
  final bool allowDeleteBill;
  final bool allowDeleteOrders;

  const BillCard({
    super.key,
    required this.customer,
    required this.cycle,
    this.billDoc,
    this.onChanged,
    this.allowDeleteBill = true,
    this.allowDeleteOrders = true,
  });

  @override
  State<BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<BillCard> {
  final DatabaseService _db = DatabaseService();
  bool _busy = false;

  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();

    // ---------------------------------------------------------------------
    // Only bother ticking while this specific cycle is still locked — once
    // unlocked there's nothing left to count down, so we don't waste
    // rebuilds.
    // ---------------------------------------------------------------------
    if (widget.cycle['isUnlocked'] != true) {
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (BillingService.getRemainingTimeForCycle(widget.cycle) == 'Unlocked') {
          _tickTimer?.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 34),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteOrder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? '';
    if (orderId.isEmpty) return;

    final ok = await _confirmDelete(
      title: 'Delete this order?',
      message: 'This will permanently delete Order #$orderId '
          '(₹${BillingService.orderTotal(order).toStringAsFixed(2)}) '
          'from this bill. This action CANNOT be undone.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await _db.deleteOrder(orderId: orderId);
      _showSnack('Order #$orderId deleted.');
      widget.onChanged?.call();
    } catch (e) {
      _showSnack('Failed to delete order: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteBill() async {
    final orders = List<Map<String, dynamic>>.from(widget.cycle['orders'] ?? []);
    final billNumber = widget.cycle['billNumber'];

    final ok = await _confirmDelete(
      title: 'Delete Bill #$billNumber?',
      message: 'This will permanently delete all ${orders.length} order(s) in '
          'Bill #$billNumber for ${widget.customer['name'] ?? 'this customer'}, '
          'and its generated PDF record. This action CANNOT be undone.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final ids = orders
          .map((o) => o['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      await _db.deleteOrders(orderIds: ids);

      final billDocId = widget.billDoc?['id']?.toString();
      if (billDocId != null && billDocId.isNotEmpty) {
        await _db.deleteGeneratedBill(billDocId);
      }

      _showSnack('Bill #$billNumber deleted.');
      widget.onChanged?.call();
    } catch (e) {
      _showSnack('Failed to delete bill: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    final mobile = widget.customer['mobile']?.toString() ?? '';
    if (mobile.isEmpty) {
      _showSnack('No mobile number on file for this customer.');
      return;
    }

    setState(() => _busy = true);
    try {
      final sent = await BillAutomationService.openWhatsAppForBill(
        mobile: mobile,
        customerName: widget.customer['name']?.toString() ?? 'Customer',
        amount: BillingService.parseAmount(widget.cycle['totalAmount']),
        billNumber: widget.cycle['billNumber'] ?? 1,
      );

      if (sent) {
        final billDocId = widget.billDoc?['id']?.toString();
        if (billDocId != null && billDocId.isNotEmpty) {
          await _db.markBillWhatsappSent(billDocId);
        }
        widget.onChanged?.call();
      } else {
        _showSnack('Could not open WhatsApp on this device.');
      }
    } catch (e) {
      _showSnack('WhatsApp error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewPdf() async {
    await BillingService.printBill(
      customer: {
        'name': widget.customer['name'] ?? 'Customer',
        'mobile': widget.customer['mobile'],
      },
      cycle: widget.cycle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cycle = widget.cycle;

    final orders = List<Map<String, dynamic>>.from(cycle['orders'] ?? []);
    final isUnlocked = cycle['isUnlocked'] == true;
    final isPaid = cycle['paymentStatus']?.toString() == 'Paid';

    // Total automatically excludes any item marked cancelled (delivery
    // "Not Available") — see BillingService.orderTotal().
    final double total = orders.fold(
      0.0,
      (sum, order) => sum + BillingService.orderTotal(order),
    );

    final billNumber = cycle['billNumber'];
    final whatsappSent = widget.billDoc?['whatsappSent'] == true;

    final String startLong = cycle['startCalendarLong'] as String? ??
        BillingService.formatCalendarLong(cycle['firstOrderTime'] as DateTime);
    final String endLong = cycle['endCalendarLong'] as String? ??
        BillingService.formatCalendarLong(cycle['maturityTime'] as DateTime);

    // Recomputed every second while _tickTimer is running, so this is
    // always accurate — no more stuck/identical remaining values.
    final String liveRemaining = BillingService.getRemainingTimeForCycle(cycle);

    late final String statusLabel;
    late final Color statusColor;
    late final IconData statusIcon;

    if (!isUnlocked) {
      statusLabel = 'Running';
      statusColor = Colors.blue;
      statusIcon = Icons.hourglass_top;
    } else if (isPaid) {
      statusLabel = 'Completed';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else {
      statusLabel = 'Payment Pending';
      statusColor = Colors.orange;
      statusIcon = Icons.error_outline;
    }

    return Opacity(
      opacity: _busy ? 0.6 : 1.0,
      child: IgnorePointer(
        ignoring: _busy,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isUnlocked && isPaid ? Colors.green.shade200 : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER: bill number + status chip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Bill #$billNumber',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 13, color: statusColor),
                        const SizedBox(width: 4),
                        Text(statusLabel,
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // CALENDAR-WISE DATES
              _calendarRow(Icons.play_circle_outline, 'Started', startLong),
              const SizedBox(height: 3),
              _calendarRow(
                Icons.lock_clock,
                isUnlocked ? 'Unlocked' : 'Unlocks',
                isUnlocked ? endLong : '$endLong  ($liveRemaining)',
              ),

              // ORDERS IN THIS BILL
              if (orders.isNotEmpty) ...[
                const Divider(height: 18),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: orders.map((order) {
                      final orderId = order['id']?.toString() ?? '';
                      final amt = BillingService.orderTotal(order);
                      final orderDate = BillingService.getOrderCreatedAt(order);
                      final items = (order['items'] as List?) ?? [];
                      final hasCancelled = items.any((raw) {
                        final item = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
                        return BillingService.isItemCancelled(item);
                      });

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Order #$orderId',
                                          style: const TextStyle(
                                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(
                                        BillingService.formatCalendarShort(orderDate),
                                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                Text('₹${amt.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                                if (widget.allowDeleteOrders) ...[
                                  const SizedBox(width: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () => _deleteOrder(order),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (hasCancelled)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Some products in this order were unavailable and are not billed.',
                                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // TOTAL
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bill Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('₹${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ACTIONS: PDF / WhatsApp / Delete Bill
              Row(
                children: [
                  if (isUnlocked)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _viewPdf,
                        icon: const Icon(Icons.picture_as_pdf, size: 17, color: Colors.red),
                        label: const Text('PDF', style: TextStyle(fontSize: 12.5)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                    ),
                  if (isUnlocked) const SizedBox(width: 8),

                  if (isUnlocked)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sendWhatsApp,
                        icon: Icon(
                          Icons.chat,
                          size: 17,
                          color: whatsappSent ? Colors.green : const Color(0xFF25D366),
                        ),
                        label: Text(
                          whatsappSent ? 'Resend' : 'WhatsApp',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                    ),

                  if (widget.allowDeleteBill) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: _deleteBill,
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),

              if (isUnlocked && whatsappSent) ...[
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.check_circle, size: 12, color: Colors.green),
                    SizedBox(width: 4),
                    Text('WhatsApp opened for this bill already',
                        style: TextStyle(fontSize: 10.5, color: Colors.green)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendarRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF1E3A8A)),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}