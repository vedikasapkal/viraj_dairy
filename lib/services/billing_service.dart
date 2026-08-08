// =============================================================================
// BILLING SERVICE (lib/services/billing_service.dart)
// Pulls the pricing/total math out of CustomerDashboard so it's in one place
// and unit-testable. Behavior matches the original inline formula exactly:
// each cart line was billed at a flat ₹80 in the original checkout call.
// =============================================================================

import '../models/item_model.dart';

class BillingService {
  /// Matches the original `_handleCheckout` formula: '₹${_cart.length * 80}'.
  /// Kept as a flat per-item rate so behavior is unchanged; swap this out
  /// for real per-product pricing (parsed from CartItemModel.price) whenever
  /// you're ready — that's the one place to do it.
  static String calculateCartTotal(List<CartItemModel> cart) {
    return '₹${cart.length * 80}';
  }

  /// Parses a "₹123" style string into an int, defaulting to 0 on failure.
  /// Used by the admin dashboard when summing a customer's order history.
  static int parseAmount(String? amount) {
    if (amount == null) return 0;
    return int.tryParse(amount.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }
}
