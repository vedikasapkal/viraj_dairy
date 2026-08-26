import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'billing_service.dart';
import 'database_service.dart';

class BillAutomationService {
  static final DatabaseService _db = DatabaseService();

  /// Call on customer dashboard load AND on admin's PDF button.
  /// If the 48h cycle has matured, persists it ONE time (idempotent via cycleId)
  /// so both dashboards see the exact same bill.
  static Future<Map<String, dynamic>?> checkAndPrepareCustomerBill({
    required Map<String, dynamic> customerProfile,
    required List<Map<String, dynamic>> customerOrders,
  }) async {
    final cycle = BillingService.getCurrentCycle(customerOrders);
    if (cycle == null || cycle['isUnlocked'] != true) return null; // not due yet

    final cycleId = cycle['cycleId'] as String;
    final mobile = customerProfile['mobile']?.toString() ?? '';

    var billDoc = await _db.getGeneratedBillByCycleId(cycleId);

    if (billDoc == null) {
      final total = BillingService.parseAmount(cycle['totalAmount']);
      await _db.saveGeneratedBill({
        'id': cycleId,
        'cycleId': cycleId,
        'customerMobile': mobile,
        'customerName': customerProfile['name'] ?? '',
        'billNumber': cycle['billNumber'],
        'totalAmount': total,
        'paymentStatus': cycle['paymentStatus'],
        'firstOrderTime': (cycle['firstOrderTime'] as DateTime).toIso8601String(),
        'maturityTime': (cycle['maturityTime'] as DateTime).toIso8601String(),
        'orders': cycle['orders'],
        'whatsappSent': false,
      });
      billDoc = await _db.getGeneratedBillByCycleId(cycleId);
    }
    return {'cycle': cycle, 'billDoc': billDoc};
  }

  /// Opens WhatsApp with the message pre-filled.
  /// IMPORTANT: wa.me can only OPEN a chat with text already typed — it cannot
  /// silently send a message with zero user interaction. True unattended
  /// sending (e.g. while nobody has the app open) needs the WhatsApp Cloud
  /// API / Twilio running on a server, not client Flutter code. See note below.
  static Future<bool> openWhatsAppForBill({
    required String mobile,
    required String customerName,
    required double amount,
    required int billNumber,
  }) async {
    if (mobile.isEmpty) return false;
    final clean = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = clean.length > 10 ? clean : '91$clean';
    final msg = 'Hello $customerName,\n\n'
        'Your Viraj Dairy bill #$billNumber for the last 2-day cycle is ready.\n'
        'Amount Due: ₹${amount.toStringAsFixed(2)}\n\n'
        'Check your app dashboard for the full PDF and UPI payment.';
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    debugPrint('Could not launch WhatsApp for $mobile');
    return false;
  }

  static Future<void> markWhatsappSent(String billDocId) =>
      _db.markBillWhatsappSent(billDocId);
}