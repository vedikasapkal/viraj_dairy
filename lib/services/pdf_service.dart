// =============================================================================
// PDF SERVICE (lib/services/pdf_service.dart)
// Extracted from AdminDashboard._downloadMonthlyBillPdf. In the original code
// this only simulated the action with a SnackBar — kept that exact behavior
// here so nothing breaks, with a clear spot to wire in a real PDF package
// (e.g. `pdf` + `printing`) and WhatsApp share intent later.
// =============================================================================

import 'package:flutter/foundation.dart';

class PdfService {
  /// Generates (or, for now, simulates generating) a monthly bill PDF for a
  /// customer and shares it via WhatsApp. Returns true on success so the
  /// calling screen can show its own SnackBar/UI feedback.
  static Future<bool> generateAndShareMonthlyBill(Map<String, dynamic> customer) async {
    // TODO: replace with real PDF generation (pdf package) + WhatsApp share
    // (e.g. via the `share_plus` or `whatsapp_share` package) once you're
    // ready — the customer map already has name/mobile/address/totalBill.
    debugPrint('Simulated: generating monthly bill PDF for ${customer['name']} (${customer['mobile']})');
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }
}
