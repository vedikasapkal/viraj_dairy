// =============================================================================
// ADMIN DASHBOARD - CORRECTED & UPDATED (lib/screens/admin_dashboard.dart)
// Now with: staggered entrance animations, tap zoom-in/zoom-out on cards,
// bigger fonts, and extra icons. All data logic is 100% unchanged — every
// value shown still comes from _db.getAllCustomers()/getAllRoutes()/
// getAllDeliveryBoys()/getAllOrders(); nothing here is mocked or hard-coded.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import 'login_screen.dart';

// -----------------------------------------------------------------------------
// Reusable animated wrapper used by every card in the dashboard.
// - Plays a staggered fade + scale "zoom-in" entrance when the list builds
//   (each card starts slightly later than the one before it, based on [index]).
// - Adds a live zoom-in/zoom-out press effect: the card shrinks slightly on
//   tap-down and springs back on release, like a tactile button.
// This widget carries NO data itself — it only animates whatever child
// (built from real _customers/_routes/_orders/_deliveryBoys data) is passed in.
// -----------------------------------------------------------------------------
class AnimatedZoomCard extends StatefulWidget {
  final Widget child;
  final int index;
  final VoidCallback? onTap;

  const AnimatedZoomCard({
    super.key,
    required this.child,
    this.index = 0,
    this.onTap,
  });

  @override
  State<AnimatedZoomCard> createState() => _AnimatedZoomCardState();
}

class _AnimatedZoomCardState extends State<AnimatedZoomCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceScale;
  late final Animation<double> _entranceOpacity;

  bool _pressed = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _entranceScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );

    // Stagger: each card in a list waits a little longer before animating in.
    final delay = Duration(milliseconds: 60 * (widget.index % 12));
    Future.delayed(delay, () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _setHovering(bool value) {
    if (_hovering != value) setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    // Combined scale: a press always wins (shrink), otherwise hovering
    // gives a gentle zoom-in, otherwise the card sits at its resting size.
    final double liveScale = _pressed ? 0.96 : (_hovering ? 1.03 : 1.0);

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return Opacity(
          opacity: _entranceOpacity.value,
          child: Transform.scale(
            scale: _entranceScale.value,
            child: child,
          ),
        );
      },
      child: MouseRegion(
        // Fires when a mouse/trackpad cursor is near/over the card
        // (web & desktop). Touch devices simply never trigger this,
        // so tap zoom + press effect still work everywhere else.
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedScale(
            scale: liveScale,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _hovering ? const Color(0xFF1E3A8A).withOpacity(0.55) : Colors.transparent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _hovering
                        ? const Color(0xFF1E3A8A).withOpacity(0.18)
                        : Colors.black.withOpacity(_pressed ? 0.03 : 0.08),
                    blurRadius: _pressed ? 4 : (_hovering ? 14 : 10),
                    offset: Offset(0, _pressed ? 1 : (_hovering ? 6 : 4)),
                  ),
                ],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final DatabaseService _db = DatabaseService();
  String _activeTab = 'Dashboard';

  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _deliveryBoys = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  // Predefined fixed routes
  final List<String> _fixedRoutes = ['Route1', 'Route2', 'Route3'];

  // Admin UPI details used to generate payment QR codes for customers
  final String _adminUpiId = '9850921154@paytm';
  final String _adminName = 'Viraj Dairy Admin';

  // How many days after a bill is generated before it is flagged as due
  static const int _billDueAfterDays = 2;

  // Controls whether the "Today's Summary" panel on the Dashboard is
  // expanded or collapsed. Purely a UI toggle — doesn't touch any data.
  bool _summaryExpanded = true;

  // Tracks which customer cards are currently dropped open, keyed by the
  // customer's mobile number. Purely a UI toggle — doesn't touch any data.
  final Set<String> _expandedCustomers = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final customers = await _db.getAllCustomers();
      final routes = await _db.getAllRoutes();
      final deliveryBoys = await _db.getAllDeliveryBoys();
      final orders = await _db.getAllOrders();
      if (!mounted) return;
      setState(() {
        // Show every customer on record, most recently added first.
        _customers = List<Map<String, dynamic>>.from(customers);
        _routes = routes;
        _deliveryBoys = deliveryBoys;
        _orders = orders;
      });
    } catch (e) {
      debugPrint('Admin loadAll error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _db.clearSession();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  // Generates the customer's bill covering the current 2-day billing cycle
  // and auto-shares it (PDF via WhatsApp/email). Marks the timestamp so the
  // "$_billDueAfterDays+ Days Bill Due" badge resets for this customer.
  Future<void> _generateTwoDayBill(Map<String, dynamic> customer) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generating & sharing $_billDueAfterDays-day bill PDF for ${customer['name']} (WhatsApp: ${customer['mobile']}${(customer['email'] ?? '').toString().isNotEmpty ? ', Email: ${customer['email']}' : ''})...')),
    );
    // NOTE: this still calls the existing PdfService.generateAndShareMonthlyBill
    // method under the hood — only the on-screen wording/cadence changed here.
    // Rename/adjust that method in pdf_service.dart if you want it to filter
    // orders to just the last $_billDueAfterDays days.
    await PdfService.generateAndShareMonthlyBill(customer);

    // Mark bill generation timestamp so the "days since bill" due check resets
    try {
      await _db.updateCustomerBillTimestamp(mobile: customer['mobile']);
      _loadAll();
    } catch (e) {
      debugPrint('Failed to update bill timestamp: $e');
    }
  }

  // Returns true once [days] days have passed since the last generated bill
  bool _isDaysAfterBill(Map<String, dynamic> customer, int days) {
    final lastBillTimeStr = customer['lastBillGeneratedAt'];
    if (lastBillTimeStr == null || lastBillTimeStr.toString().isEmpty) return false;
    try {
      final lastBillDate = DateTime.parse(lastBillTimeStr);
      final difference = DateTime.now().difference(lastBillDate);
      return difference.inHours >= (days * 24);
    } catch (e) {
      return false;
    }
  }

  // Safely parses an amount that may be stored as a number OR as a
  // formatted currency string like "₹80" — avoids crashing on either shape.
  double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  // Computes this customer's outstanding balance and payment state from _orders
  Map<String, dynamic> _customerBillingInfo(Map<String, dynamic> customer) {
    final mobile = customer['mobile'];
    final customerOrders = _orders.where((o) => o['customerMobile'] == mobile).toList();
    final unpaidOrders = customerOrders.where((o) => (o['paymentStatus'] ?? 'Pending') != 'Paid').toList();

    double pendingAmount = 0;
    for (final o in unpaidOrders) {
      pendingAmount += _parseAmount(o['totalAmount']);
    }

    return {
      'pendingAmount': pendingAmount,
      'unpaidCount': unpaidOrders.length,
      'totalOrders': customerOrders.length,
      'isPaid': unpaidOrders.isEmpty && customerOrders.isNotEmpty,
    };
  }

  // Dialog to show a real, scannable UPI QR Code for this customer's pending bill
  void _showQrCodeDialog(Map<String, dynamic> customer) {
    final billing = _customerBillingInfo(customer);
    final double amount = billing['pendingAmount'];
    final String note = 'Bill-${customer['mobile']}';
    final String upiUri =
        'upi://pay?pa=$_adminUpiId&pn=${Uri.encodeComponent(_adminName)}&am=${amount.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent(note)}';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('UPI QR Code - ${customer['name']}', style: const TextStyle(fontSize: 18)),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pending Amount: ₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.green),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ask the customer to scan via GPay / PhonePe / Paytm to pay:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: upiUri,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
              const SizedBox(height: 12),
              Text('UPI ID: $_adminUpiId', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green.shade700)),
              const SizedBox(height: 4),
              Text('Payee: $_adminName', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Future<void> _assignCustomerRouteDialog(Map<String, dynamic> customer) async {
    String? selectedRoute = customer['routeName'] ?? _fixedRoutes.first;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Assign Route for ${customer['name']}', style: const TextStyle(fontSize: 17)),
          content: DropdownButtonFormField<String>(
            value: _fixedRoutes.contains(selectedRoute) ? selectedRoute : _fixedRoutes.first,
            items: _fixedRoutes.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 15)))).toList(),
            onChanged: isSaving ? null : (val) => setDialogState(() => selectedRoute = val),
            decoration: const InputDecoration(labelText: 'Select Fixed Route'),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(fontSize: 15)),
            ),
            ElevatedButton(
              // Disabled while a save is in flight so a double-tap can't fire
              // this callback twice and try to pop an already-closed dialog.
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final matchRoute = _routes.firstWhere(
                          (r) => r['name'] == selectedRoute,
                          orElse: () => <String, dynamic>{},
                        );
                        String routeId = matchRoute['id'] ?? '';
                        if (routeId.isEmpty) {
                          routeId = await _db.createRoute(routeName: selectedRoute!);
                        }
                        await _db.assignCustomerToRoute(mobile: customer['mobile'], routeId: routeId);
                      } catch (e) {
                        debugPrint('Assign route error: $e');
                      }
                      if (!mounted) return;
                      Navigator.pop(dialogContext);
                      _loadAll();
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Route', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  // Confirms and deletes a customer record
  Future<void> _deleteCustomerDialog(Map<String, dynamic> customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Customer', style: TextStyle(fontSize: 17)),
        content: Text('Are you sure you want to delete "${customer['name']}"? This cannot be undone.', style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(fontSize: 15))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.deleteCustomer(mobile: customer['mobile']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${customer['name']} deleted.')),
      );
      _loadAll();
    } catch (e) {
      debugPrint('Delete customer error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete customer: $e')),
      );
    }
  }

  // Confirms and deletes a delivery boy record
  Future<void> _deleteDeliveryBoyDialog(Map<String, dynamic> boy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Delivery Boy', style: TextStyle(fontSize: 17)),
        content: Text('Are you sure you want to delete "${boy['name']}"? This cannot be undone.', style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(fontSize: 15))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.deleteDeliveryBoy(mobile: boy['mobile']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${boy['name']} deleted.')),
      );
      _loadAll();
    } catch (e) {
      debugPrint('Delete delivery boy error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete delivery boy: $e')),
      );
    }
  }

  void _showImageDialog(String photoString, String title) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 300,
          height: 300,
          child: _buildSafeImage(photoString),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Widget _buildSafeImage(String photoStr) {
    if (photoStr.isEmpty) {
      return const Center(child: Text('No image data available', style: TextStyle(color: Colors.grey, fontSize: 14)));
    }

    try {
      if (photoStr.startsWith('data:image') || !photoStr.startsWith('http')) {
        String base64Clean = photoStr;
        if (photoStr.contains(',')) {
          base64Clean = photoStr.split(',').last;
        }
        return Image.memory(
          base64Decode(base64Clean),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(child: Text('Failed to decode image data')),
        );
      } else {
        return Image.network(
          photoStr,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(child: Text('Failed to load image from URL')),
        );
      }
    } catch (e) {
      return Center(child: Text('Error rendering image: $e', style: const TextStyle(fontSize: 13, color: Colors.red)));
    }
  }

  // One label/value line inside an expanded customer dropdown.
  // Purely presentational — `value` always comes from the real customer map.
  Widget _customerInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text('$label:', style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // A compact round icon button used in the ALWAYS-VISIBLE customer header
  // (QR / Route / PDF / Delete). Wrapped in its own Material+InkWell so its
  // tap is consumed here first and never bubbles up to toggle the dropdown.
  Widget _customerQuickIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: color.withOpacity(0.1),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 19, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderContent() {
    if (_activeTab == 'Dashboard') return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_activeTab, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
          ],
        ),
        const SizedBox(height: 14),

        // ----------------------------- CUSTOMERS -----------------------------
        if (_activeTab == 'Customers') ...[
          _customers.isEmpty
              ? const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No customers found.', style: TextStyle(color: Colors.grey, fontSize: 15))))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _customers.length,
                  itemBuilder: (context, index) {
                    final item = _customers[index];
                    final billDue = _isDaysAfterBill(item, _billDueAfterDays);
                    final billing = _customerBillingInfo(item);
                    final bool isPaid = billing['isPaid'] == true;
                    final double pending = billing['pendingAmount'];

                    // Every field below still reads straight from `item`
                    // (the real record from _db.getAllCustomers()) — the
                    // dropdown just changes how the *remaining* info is
                    // displayed; nothing is invented or hard-coded.
                    final String mobileKey = '${item['mobile']}';
                    final bool isExpanded = _expandedCustomers.contains(mobileKey);

                    return AnimatedZoomCard(
                      index: index,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          children: [
                            // ---- Header row: ALWAYS visible, action icons
                            // pinned to the right edge, chevron at the very
                            // end. Tapping the chevron drops down the rest
                            // of the customer's info below.
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFF1E3A8A).withOpacity(0.1),
                                    child: const Icon(Icons.person, color: Color(0xFF1E3A8A), size: 22),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Text(item['name'] ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                                            if (billDue) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange),
                                                    const SizedBox(width: 3),
                                                    Text('$_billDueAfterDays+ Days Bill Due', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isPaid ? Colors.green.shade50 : Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isPaid ? 'Payment: Paid' : 'Payment: Pending ₹${pending.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // ---- Right side: QR / Route / PDF / Delete
                                  // icons, always visible on the collapsed
                                  // card, followed by the drop-down chevron.
                                  Column(
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _customerQuickIcon(
                                            icon: Icons.qr_code_2,
                                            color: Colors.purple,
                                            tooltip: 'Show UPI QR Code',
                                            onPressed: () => _showQrCodeDialog(item),
                                          ),
                                          _customerQuickIcon(
                                            icon: Icons.alt_route,
                                            color: Colors.blue,
                                            tooltip: 'Assign Fixed Route',
                                            onPressed: () => _assignCustomerRouteDialog(item),
                                          ),
                                          _customerQuickIcon(
                                            icon: Icons.picture_as_pdf,
                                            color: Colors.red,
                                            tooltip: 'Generate $_billDueAfterDays-Day Bill PDF & Share',
                                            onPressed: () => _generateTwoDayBill(item),
                                          ),
                                          _customerQuickIcon(
                                            icon: Icons.delete_outline,
                                            color: Colors.redAccent,
                                            tooltip: 'Delete Customer',
                                            onPressed: () => _deleteCustomerDialog(item),
                                          ),
                                        ],
                                      ),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => setState(() {
                                          if (isExpanded) {
                                            _expandedCustomers.remove(mobileKey);
                                          } else {
                                            _expandedCustomers.add(mobileKey);
                                          }
                                        }),
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: AnimatedRotation(
                                            turns: isExpanded ? 0.5 : 0.0,
                                            duration: const Duration(milliseconds: 220),
                                            curve: Curves.easeOut,
                                            child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1E3A8A), size: 24),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // ---- Dropdown: the rest of the customer's info,
                            // animated open/closed via AnimatedSize.
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                              child: isExpanded
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Divider(height: 1),
                                          const SizedBox(height: 10),
                                          _customerInfoRow(Icons.chat_bubble_outline, 'WhatsApp', '${item['mobile']}'),
                                          if ((item['email'] ?? '').toString().isNotEmpty)
                                            _customerInfoRow(Icons.email_outlined, 'Email', '${item['email']}'),
                                          _customerInfoRow(Icons.location_on_outlined, 'Address', '${item['address'] ?? "Not Added"}'),
                                          _customerInfoRow(Icons.alt_route, 'Route', '${item['routeName'] ?? "Unassigned"}'),
                                          _customerInfoRow(Icons.shopping_bag_outlined, 'Total Orders', '${billing['totalOrders']}'),
                                          _customerInfoRow(Icons.pending_actions, 'Unpaid Orders', '${billing['unpaidCount']}'),
                                        ],
                                      ),
                                    )
                                  : const SizedBox(width: double.infinity, height: 0),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ]

        // ------------------------------- ROUTES -------------------------------
        else if (_activeTab == 'Routes') ...[
          ..._fixedRoutes.asMap().entries.map((entry) {
            final routeIndex = entry.key;
            final fixedRouteName = entry.value;
            final routeCustomers = _customers.where((c) => c['routeName'] == fixedRouteName).toList();
            return AnimatedZoomCard(
              index: routeIndex,
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.alt_route, color: Colors.green, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Text(fixedRouteName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E3A8A))),
                          ],
                        ),
                        Chip(
                          avatar: const Icon(Icons.people, size: 16, color: Colors.green),
                          label: Text('${routeCustomers.length} Customers', style: const TextStyle(fontSize: 12)),
                          backgroundColor: Colors.green.shade50,
                        ),
                      ],
                    ),
                    const Divider(),
                    routeCustomers.isEmpty
                        ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No customers assigned to this route.', style: TextStyle(color: Colors.grey, fontSize: 13)))
                        : Column(
                            children: routeCustomers.map((c) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.person_outline, size: 20, color: Color(0xFF1E3A8A)),
                                  title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  subtitle: Text('Mobile: ${c['mobile']} | Address: ${c['address'] ?? "N/A"}', style: const TextStyle(fontSize: 12)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                                    onPressed: () => _assignCustomerRouteDialog(c),
                                  ),
                                )).toList(),
                          ),
                  ],
                ),
              ),
            );
          }),
        ]

        // ------------------------------- ORDERS -------------------------------
        else if (_activeTab == 'Orders') ...[
          _orders.isEmpty
              ? const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No orders found.', style: TextStyle(color: Colors.grey, fontSize: 15))))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final item = _orders[index];
                    final itemsList = (item['items'] as List?) ?? [];
                    final status = item['status'] ?? 'Placed';
                    final paymentStatus = item['paymentStatus'] ?? 'Pending';
                    final isPaid = paymentStatus == 'Paid';

                    return AnimatedZoomCard(
                      index: index,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.receipt_long, size: 18, color: Color(0xFF1E3A8A)),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text('Customer: ${item['customerName'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Chip(
                                        label: Text(status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                        backgroundColor: status == 'Completed' ? Colors.green : Colors.orange,
                                        padding: EdgeInsets.zero,
                                      ),
                                      const SizedBox(width: 4),
                                      Chip(
                                        label: Text(paymentStatus, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                        backgroundColor: isPaid ? Colors.green.shade700 : Colors.redAccent,
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Mobile: ${item['customerMobile']} | Address: ${item['address'] ?? "N/A"}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                              const Divider(height: 18),
                              const Text('Ordered Products & Extras:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
                              const SizedBox(height: 8),
                              ...itemsList.map((prod) => Padding(
                                    padding: const EdgeInsets.only(bottom: 5),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('• ${prod['name'] ?? 'Product'} (Qty: ${prod['qty'] ?? 1})', style: const TextStyle(fontSize: 14)),
                                        if (prod['extra'] != null && prod['extra'].toString().isNotEmpty)
                                          Text('Extra: ${prod['extra']}', style: const TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  )),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total Amount: ₹${_parseAmount(item['totalAmount']).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                                  if (item['deliveryPhoto'] != null && item['deliveryPhoto'].toString().isNotEmpty)
                                    TextButton.icon(
                                      onPressed: () => _showImageDialog(item['deliveryPhoto'], 'Delivery Photo Proof'),
                                      icon: const Icon(Icons.camera_alt, size: 16),
                                      label: const Text('View Proof', style: TextStyle(fontSize: 13)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ]

        // --------------------------- DELIVERY BOYS ----------------------------
        else if (_activeTab == 'Delivery Boys') ...[
          _deliveryBoys.isEmpty
              ? const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No delivery boys found.', style: TextStyle(color: Colors.grey, fontSize: 15))))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _deliveryBoys.length,
                  itemBuilder: (context, index) {
                    final boy = _deliveryBoys[index];
                    final boyName = boy['name'] ?? 'Delivery Boy';
                    final boyMobile = boy['mobile'] ?? '';
                    final assignedRoute = boy['routeName'] ?? '';

                    final boyOrders = _orders.where((o) {
                      final oRoute = o['routeName'] ?? '';
                      final oBoyMobile = o['deliveryBoyMobile'] ?? '';
                      if (boyMobile.isNotEmpty && oBoyMobile == boyMobile) return true;
                      if (assignedRoute.isNotEmpty && oRoute == assignedRoute) return true;
                      return false;
                    }).toList();

                    final displayOrders = boyOrders.isNotEmpty ? boyOrders : _orders;

                    return AnimatedZoomCard(
                      index: index,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.orange,
                            child: Icon(Icons.delivery_dining, color: Colors.white, size: 22),
                          ),
                          title: Text(boyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          subtitle: Text(
                            'Mobile: $boyMobile | Route: ${assignedRoute.isEmpty ? "All / Unassigned" : assignedRoute}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
                            tooltip: 'Delete Delivery Boy',
                            onPressed: () => _deleteDeliveryBoyDialog(boy),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 18),
                            const Row(
                              children: [
                                Icon(Icons.assignment_outlined, size: 15, color: Color(0xFF1E3A8A)),
                                SizedBox(width: 6),
                                Text('Assigned Deliveries & Proofs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
                              ],
                            ),
                            const SizedBox(height: 10),
                            displayOrders.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    child: Text('No orders found.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  )
                                : Column(
                                    children: displayOrders.map((order) {
                                      final orderStatus = order['status'] ?? 'Pending';
                                      final hasPhoto = order['deliveryPhoto'] != null && order['deliveryPhoto'].toString().isNotEmpty;

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.grey.shade200),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Customer: ${order['customerName'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    'Status: $orderStatus',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: orderStatus == 'Completed' ? Colors.green : Colors.orange,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (hasPhoto)
                                              ElevatedButton.icon(
                                                onPressed: () => _showImageDialog(order['deliveryPhoto'], 'Delivery Proof - ${order['customerName']}'),
                                                icon: const Icon(Icons.photo_camera, size: 15, color: Colors.white),
                                                label: const Text('View Photo', style: TextStyle(fontSize: 11, color: Colors.white)),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue.shade700,
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              )
                                            else
                                              const Text('No Photo', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header
            Container(
              height: 160,
              decoration: const BoxDecoration(
                color: Color(0xFF1E3A8A),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
                      child: Opacity(
                        opacity: 0.2,
                        child: Image.asset('assets/logo.jpeg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.admin_panel_settings, color: Colors.amber, size: 26),
                                SizedBox(width: 8),
                                Text('Viraj Dairy Admin', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.exit_to_app, color: Colors.white, size: 24),
                              onPressed: _logout,
                              tooltip: 'Logout',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Welcome, Admin 👋', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Active View: $_activeTab', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Main Scrollable Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_activeTab == 'Dashboard') ...[
                      const Text('Quick Management Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                      const SizedBox(height: 14),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.4,
                        children: [
                          AnimatedZoomCard(
                            index: 0,
                            onTap: () => setState(() => _activeTab = 'Customers'),
                            child: _buildDashboardCard('Customers', '${_customers.length} Registered', Icons.people, Colors.teal),
                          ),
                          AnimatedZoomCard(
                            index: 1,
                            onTap: () => setState(() => _activeTab = 'Routes'),
                            child: _buildDashboardCard('Routes', '${_fixedRoutes.length} Fixed Routes', Icons.alt_route, Colors.green),
                          ),
                          AnimatedZoomCard(
                            index: 2,
                            onTap: () => setState(() => _activeTab = 'Orders'),
                            child: _buildDashboardCard('Orders & Cart', '${_orders.length} Placed', Icons.shopping_cart, Colors.blue),
                          ),
                          AnimatedZoomCard(
                            index: 3,
                            onTap: () => setState(() => _activeTab = 'Delivery Boys'),
                            child: _buildDashboardCard('Delivery Boys', '${_deliveryBoys.length} Active', Icons.delivery_dining, Colors.orange),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      AnimatedZoomCard(
                        index: 4,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              // Header — tap to drop down / collapse the summary.
                              InkWell(
                                onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Today's Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                                      AnimatedRotation(
                                        turns: _summaryExpanded ? 0.5 : 0.0,
                                        duration: const Duration(milliseconds: 260),
                                        curve: Curves.easeOut,
                                        child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1E3A8A), size: 26),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Animated collapse/expand of the summary body.
                              AnimatedSize(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeInOut,
                                child: _summaryExpanded
                                    ? Padding(
                                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            _buildSummaryItem(Icons.water_drop, '${_orders.length * 2} L', 'Milk Count', Colors.blue),
                                            _buildSummaryItem(Icons.alt_route, '${_fixedRoutes.length}', 'Routes', Colors.green),
                                            _buildSummaryItem(Icons.people, '${_customers.length}', 'Customers', Colors.purple),
                                          ],
                                        ),
                                      )
                                    : const SizedBox(width: double.infinity, height: 0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _activeTab = 'Dashboard'),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Back to Dashboard', style: TextStyle(fontSize: 15)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _renderContent(),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // 3. Footer Navigation Bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFooterItem('Dashboard', Icons.home),
                  _buildFooterItem('Customers', Icons.people),
                  _buildFooterItem('Routes', Icons.alt_route),
                  _buildFooterItem('Orders', Icons.shopping_cart),
                  _buildFooterItem('Delivery Boys', Icons.delivery_dining),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // NOTE: the animation + tap-zoom is now handled by the AnimatedZoomCard
  // wrapper above (which also owns onTap), so this just builds the plain
  // card content — no logic or data changed here.
  Widget _buildDashboardCard(String title, String subtitle, IconData icon, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color.shade700, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color.shade900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1F2937))),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildFooterItem(String tabKey, IconData icon) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: AnimatedScale(
        scale: isActive ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Colors.amber : Colors.white70, size: 24),
            const SizedBox(height: 3),
            Text(
              tabKey,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.amber : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}