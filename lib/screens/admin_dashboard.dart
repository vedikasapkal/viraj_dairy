// =============================================================================
// ADMIN DASHBOARD
// lib/screens/admin_dashboard.dart
//
// UPDATED IN THIS VERSION
// -----------------------------------------------------------------------------
// Customers tab -> each customer's Bill History card now has:
//   1. A DELETE icon (trash) on every generated bill, guarded by an
//      AlertDialog warning popup — nothing is deleted without the admin
//      confirming. Deleting a bill removes all its orders AND its
//      generated_bills record.
//   2. A WHATSAPP icon on every generated (unlocked) bill — tapping it opens
//      WhatsApp with that specific bill's message pre-filled, ready to send.
//      This works the same way for every bill in history, not just the
//      current/latest one.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/database_service.dart';
import '../services/billing_service.dart';
import '../services/bill_automation_service.dart';
import 'login_screen.dart';

// =============================================================================
// ANIMATED ZOOM CARD
// =============================================================================

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
    final double liveScale = _pressed ? 0.96 : (_hovering ? 1.02 : 1.0);

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return Opacity(
          opacity: _entranceOpacity.value,
          child: Transform.scale(scale: _entranceScale.value, child: child),
        );
      },
      child: MouseRegion(
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
                  color: _hovering
                      ? const Color(0xFF1E3A8A).withOpacity(0.55)
                      : Colors.transparent,
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

// =============================================================================
// ADMIN DASHBOARD
// =============================================================================

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

  String? _generatingBillForMobile;

  // Tracks cycleIds currently being deleted / whatsapp-sent so we can show a
  // spinner on just that one bill card and disable its buttons meanwhile.
  final Set<String> _busyBillIds = {};

  final List<String> _fixedRoutes = ['Route1', 'Route2', 'Route3'];

  final String _adminUpiId = '9850921154@paytm';
  final String _adminName = 'Viraj Dairy Admin';

  static const int _billDueAfterDays = 2;

  bool _summaryExpanded = true;

  final Set<String> _expandedCustomers = {};
  final Set<String> _expandedBillHistory = {};

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ===========================================================================
  // LOAD DATA
  // ===========================================================================

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);

    try {
      final customers = await _db.getAllCustomers();
      final routes = await _db.getAllRoutes();
      final deliveryBoys = await _db.getAllDeliveryBoys();
      final orders = await _db.getAllOrders();

      if (!mounted) return;

      setState(() {
        _customers = List<Map<String, dynamic>>.from(customers);
        _routes = List<Map<String, dynamic>>.from(routes);
        _deliveryBoys = List<Map<String, dynamic>>.from(deliveryBoys);
        _orders = List<Map<String, dynamic>>.from(orders);
      });
    } catch (e) {
      debugPrint('Admin loadAll error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  Future<void> _logout() async {
    try {
      await _db.clearSession();
    } catch (e) {
      debugPrint('Logout error: $e');
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ===========================================================================
  // AMOUNT PARSER
  // ===========================================================================

  double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  // ===========================================================================
  // CUSTOMER BILLING INFORMATION
  // ===========================================================================

  Map<String, dynamic> _customerBillingInfo(Map<String, dynamic> customer) {
    final mobile = customer['mobile']?.toString() ?? '';

    final customerOrders = _orders
        .where((order) => order['customerMobile']?.toString() == mobile)
        .toList();

    final unpaidOrders = customerOrders
        .where((order) => (order['paymentStatus'] ?? 'Pending') != 'Paid')
        .toList();

    double pendingAmount = 0;
    for (final order in unpaidOrders) {
      pendingAmount += _parseAmount(order['totalAmount']);
    }

    return {
      'pendingAmount': pendingAmount,
      'unpaidCount': unpaidOrders.length,
      'totalOrders': customerOrders.length,
      'isPaid': unpaidOrders.isEmpty && customerOrders.isNotEmpty,
    };
  }

  // ===========================================================================
  // BILL DUE CHECK
  // ===========================================================================

  bool _isDaysAfterBill(Map<String, dynamic> customer, int days) {
    final value = customer['lastBillGeneratedAt'];
    if (value == null || value.toString().isEmpty) return false;

    try {
      final lastBillDate = DateTime.parse(value.toString());
      final difference = DateTime.now().difference(lastBillDate);
      return difference.inHours >= days * 24;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // GENERATE BILL
  // ===========================================================================

  Future<void> _generateTwoDayBill(Map<String, dynamic> customer) async {
    final mobile = customer['mobile']?.toString() ?? '';
    if (mobile.isEmpty) return;

    setState(() => _generatingBillForMobile = mobile);

    try {
      final customerOrders = _orders
          .where((order) => order['customerMobile']?.toString() == mobile)
          .toList();

      final result = await BillAutomationService.checkAndPrepareCustomerBill(
        customerProfile: customer,
        customerOrders: customerOrders,
      );

      if (result == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${customer['name'] ?? 'Customer'} has no bill due yet. '
              'The $_billDueAfterDays-day cycle has not completed.',
            ),
          ),
        );
        return;
      }

      final cycle = result['cycle'] as Map<String, dynamic>;
      final billDoc = result['billDoc'] as Map<String, dynamic>;

      if (!mounted) return;

      final amount = BillingService.parseAmount(cycle['totalAmount']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bill #${cycle['billNumber']} ready for '
            '${customer['name']} (₹${amount.toStringAsFixed(2)}).',
          ),
        ),
      );

      await BillingService.printBill(customer: customer, cycle: cycle);

      final sent = await BillAutomationService.openWhatsAppForBill(
        mobile: mobile,
        customerName: customer['name'] ?? 'Customer',
        amount: amount,
        billNumber: cycle['billNumber'] ?? 1,
      );

      if (sent) {
        await BillAutomationService.markWhatsappSent(billDoc['id']);
      }

      await _db.updateCustomerBillTimestamp(mobile: mobile);

      await _loadAll();
    } catch (e) {
      debugPrint('Generate two-day bill error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate bill: $e')),
      );
    } finally {
      if (mounted) setState(() => _generatingBillForMobile = null);
    }
  }

  // ===========================================================================
  // QR CODE
  // ===========================================================================

  void _showQrCodeDialog(Map<String, dynamic> customer) {
    final billing = _customerBillingInfo(customer);
    final double amount = billing['pendingAmount'] as double;
    final String note = 'Bill-${customer['mobile']}';

    final String upiUri = 'upi://pay'
        '?pa=$_adminUpiId'
        '&pn=${Uri.encodeComponent(_adminName)}'
        '&am=${amount.toStringAsFixed(2)}'
        '&cu=INR'
        '&tn=${Uri.encodeComponent(note)}';

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('UPI QR Code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(customer['name'] ?? 'Customer',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  'Pending Amount: ₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17, color: Colors.green),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ask the customer to scan this QR using GPay / PhonePe / Paytm.',
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
                  child: QrImageView(data: upiUri, version: QrVersions.auto, size: 200),
                ),
                const SizedBox(height: 12),
                Text('UPI ID: $_adminUpiId',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                const SizedBox(height: 4),
                Text('Payee: $_adminName',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // ROUTE ASSIGNMENT
  // ===========================================================================

  Future<void> _assignCustomerRouteDialog(Map<String, dynamic> customer) async {
    String? selectedRoute = customer['routeName']?.toString();
    if (!_fixedRoutes.contains(selectedRoute)) {
      selectedRoute = _fixedRoutes.first;
    }

    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Assign Route for ${customer['name'] ?? 'Customer'}'),
              content: DropdownButtonFormField<String>(
                value: selectedRoute,
                items: _fixedRoutes
                    .map((route) => DropdownMenuItem(value: route, child: Text(route)))
                    .toList(),
                onChanged: isSaving
                    ? null
                    : (value) => setDialogState(() => selectedRoute = value),
                decoration: const InputDecoration(labelText: 'Select Route'),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            final matchRoute = _routes.firstWhere(
                              (route) => route['name'] == selectedRoute,
                              orElse: () => <String, dynamic>{},
                            );

                            String routeId = matchRoute['id']?.toString() ?? '';

                            if (routeId.isEmpty) {
                              routeId = await _db.createRoute(routeName: selectedRoute!);
                            }

                            await _db.assignCustomerToRoute(
                              mobile: customer['mobile'],
                              routeId: routeId,
                            );

                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            await _loadAll();
                          } catch (e) {
                            debugPrint('Assign route error: $e');
                            setDialogState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Route'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // DELETE CUSTOMER
  // ===========================================================================

  Future<void> _deleteCustomerDialog(Map<String, dynamic> customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete Customer'),
          content: Text('Are you sure you want to delete "${customer['name']}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _db.deleteCustomer(mobile: customer['mobile']);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${customer['name']} deleted.')));
      await _loadAll();
    } catch (e) {
      debugPrint('Delete customer error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete customer: $e')));
    }
  }

  // ===========================================================================
  // DELETE DELIVERY BOY
  // ===========================================================================

  Future<void> _deleteDeliveryBoyDialog(Map<String, dynamic> boy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete Delivery Boy'),
          content: Text('Are you sure you want to delete "${boy['name']}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _db.deleteDeliveryBoy(mobile: boy['mobile']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${boy['name']} deleted.')));
      await _loadAll();
    } catch (e) {
      debugPrint('Delete delivery boy error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete delivery boy: $e')));
    }
  }

  // ===========================================================================
  // ADD DELIVERY BOY
  // ===========================================================================

  Future<void> _addDeliveryBoyDialog() async {
    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final passwordController = TextEditingController();

    String? selectedRoute = _fixedRoutes.first;
    bool obscurePassword = true;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Add Delivery Boy'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      enabled: !isSaving,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobileController,
                      enabled: !isSaving,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Mobile Number'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      enabled: !isSaving,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Login Password',
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () =>
                              setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedRoute,
                      items: _fixedRoutes
                          .map((route) => DropdownMenuItem(value: route, child: Text(route)))
                          .toList(),
                      onChanged: isSaving
                          ? null
                          : (value) => setDialogState(() => selectedRoute = value),
                      decoration: const InputDecoration(labelText: 'Assign Route'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final mobile = mobileController.text.trim();
                          final password = passwordController.text.trim();

                          if (name.isEmpty || mobile.isEmpty || password.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please fill all fields')),
                            );
                            return;
                          }

                          if (_deliveryBoys.any((boy) => '${boy['mobile']}' == mobile)) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Delivery boy already exists')),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          try {
                            final created = await _db.createDeliveryBoyAccount(
                              name: name,
                              mobile: mobile,
                              password: password,
                              routeName: selectedRoute,
                            );

                            if (!created) {
                              throw Exception('Delivery boy already exists');
                            }

                            if (!mounted) return;
                            Navigator.pop(dialogContext);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Delivery boy "$name" added successfully.')),
                            );

                            await _loadAll();
                          } catch (e) {
                            debugPrint('Add delivery boy error: $e');
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(dialogContext)
                                .showSnackBar(SnackBar(content: Text('Failed: $e')));
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create Account'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // IMAGE DIALOG
  // ===========================================================================

  void _showImageDialog(String photoString, String title) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(width: 300, height: 300, child: _buildSafeImage(photoString)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Widget _buildSafeImage(String photoStr) {
    if (photoStr.isEmpty) {
      return const Center(child: Text('No image data available'));
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
          errorBuilder: (_, __, ___) => const Center(child: Text('Failed to decode image')),
        );
      }

      return Image.network(
        photoStr,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(child: Text('Failed to load image')),
      );
    } catch (e) {
      return Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red)));
    }
  }

  // ===========================================================================
  // CUSTOMER INFO ROW
  // ===========================================================================

  Widget _customerInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 105,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not Added' : value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // QUICK ICON
  // ===========================================================================

  Widget _customerQuickIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: color.withOpacity(0.10),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: loading ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: loading
                  ? SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    )
                  : Icon(icon, size: 19, color: color),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BILL HISTORY
  // ===========================================================================

  Widget _buildCustomerBillingHistory(Map<String, dynamic> customer) {
    final mobile = customer['mobile']?.toString() ?? '';

    final customerOrders =
        _orders.where((order) => order['customerMobile']?.toString() == mobile).toList();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadCustomerBillCards(customer, customerOrders),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        final cards = snapshot.data ?? [];

        if (cards.isEmpty) {
          return const Text('No billing cycles yet.', style: TextStyle(fontSize: 12, color: Colors.grey));
        }

        final currentCards = cards.where((card) {
          final cycle = card['cycle'] as Map<String, dynamic>;
          return cycle['isUnlocked'] != true;
        }).toList();

        final historyCards = cards.where((card) {
          final cycle = card['cycle'] as Map<String, dynamic>;
          return cycle['isUnlocked'] == true;
        }).toList();

        final completedCount = historyCards.where((card) {
          final cycle = card['cycle'] as Map<String, dynamic>;
          return cycle['paymentStatus']?.toString() == 'Paid';
        }).length;

        final showAll = _expandedBillHistory.contains(mobile);
        final displayedHistory = showAll ? historyCards : historyCards.take(1).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentCards.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.hourglass_top, size: 15, color: Color(0xFF1E3A8A)),
                  SizedBox(width: 6),
                  Text(
                    'Current Bill (Running)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...currentCards.map((card) => _billHistoryCard(customer: customer, card: card)),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Bill History ($completedCount/${historyCards.length} Completed)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                  ),
                ),
                if (historyCards.length > 1)
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (showAll) {
                          _expandedBillHistory.remove(mobile);
                        } else {
                          _expandedBillHistory.add(mobile);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            showAll ? 'Show Less' : 'View All (${historyCards.length})',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A)),
                          ),
                          AnimatedRotation(
                            turns: showAll ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF1E3A8A)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (historyCards.isEmpty)
              const Text('No completed bills yet.', style: TextStyle(fontSize: 12, color: Colors.grey))
            else
              ...displayedHistory.map((card) => _billHistoryCard(customer: customer, card: card)),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // LOAD BILL CARDS  (READ-ONLY — does not create or advance any bill)
  // ===========================================================================

  Future<List<Map<String, dynamic>>> _loadCustomerBillCards(
    Map<String, dynamic> customer,
    List<Map<String, dynamic>> customerOrders,
  ) async {
    // NOTE: cycles are computed purely from the customer's real orders —
    // nothing is written to the DB just because the admin opened this card.
    final allCycles = BillingService.buildCustomerCycles(customerOrders);

    if (allCycles.isEmpty) return [];

    final mobile = customer['mobile']?.toString() ?? '';

    final allGeneratedBills = await _db.getAllGeneratedBills();

    final Map<String, Map<String, dynamic>> billDocsByCycleId = {};

    for (final bill in allGeneratedBills) {
      if (bill['customerMobile']?.toString() == mobile && bill['cycleId'] != null) {
        billDocsByCycleId[bill['cycleId'].toString()] = bill;
      }
    }

    final ordered = allCycles.reversed.toList();

    return ordered.map((cycle) {
      final cycleId = cycle['cycleId']?.toString() ?? '';
      return {
        'cycle': cycle,
        'billDoc': billDocsByCycleId[cycleId],
      };
    }).toList();
  }

  // ===========================================================================
  // WARNING CONFIRMATION POPUP (shared by every bill-delete action here)
  // ===========================================================================

  Future<bool> _confirmDeleteBill({required String title, required String message}) async {
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

  // ===========================================================================
  // DELETE A GENERATED BILL (all its orders + its generated_bills record)
  //
  // Guarded by the warning popup above. Called from the trash icon on every
  // bill card in "Customers -> (expand a customer) -> Bill History".
  // ===========================================================================

  Future<void> _deleteBillCycle({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> cycle,
    required Map<String, dynamic>? billDoc,
  }) async {
    final orders = List<Map<String, dynamic>>.from(cycle['orders'] ?? []);
    final billNumber = cycle['billNumber'];
    final cycleId = cycle['cycleId']?.toString() ?? '';

    final confirmed = await _confirmDeleteBill(
      title: 'Delete Bill #$billNumber?',
      message: 'This will permanently delete all ${orders.length} order(s) in '
          'Bill #$billNumber for ${customer['name'] ?? 'this customer'}, '
          'along with its generated PDF record. This action CANNOT be undone.',
    );
    if (!confirmed) return;

    setState(() => _busyBillIds.add(cycleId));

    try {
      final orderIds =
          orders.map((o) => o['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();

      await _db.deleteOrders(orderIds: orderIds);

      final billDocId = billDoc?['id']?.toString();
      if (billDocId != null && billDocId.isNotEmpty) {
        await _db.deleteGeneratedBill(billDocId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bill #$billNumber deleted.')),
      );

      await _loadAll();
    } catch (e) {
      debugPrint('Delete bill error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete bill: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyBillIds.remove(cycleId));
    }
  }

  // ===========================================================================
  // SEND WHATSAPP FOR ONE SPECIFIC GENERATED BILL
  //
  // Opens WhatsApp with that bill's message pre-filled — works for EVERY
  // bill shown in history, not just the latest one. WhatsApp itself only
  // lets us open the chat with the text ready to go (see note in
  // bill_card.dart) — the admin still taps Send inside WhatsApp.
  // ===========================================================================

  Future<void> _sendWhatsAppForBill({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> cycle,
    required Map<String, dynamic>? billDoc,
  }) async {
    final mobile = customer['mobile']?.toString() ?? '';
    final cycleId = cycle['cycleId']?.toString() ?? '';

    if (mobile.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No mobile number on file for this customer.')));
      return;
    }

    setState(() => _busyBillIds.add(cycleId));

    try {
      final amount = BillingService.parseAmount(cycle['totalAmount']);

      final sent = await BillAutomationService.openWhatsAppForBill(
        mobile: mobile,
        customerName: customer['name']?.toString() ?? 'Customer',
        amount: amount,
        billNumber: cycle['billNumber'] ?? 1,
      );

      if (sent) {
        String? billDocId = billDoc?['id']?.toString();

        // If this bill doesn't have a generated_bills record yet, create one
        // so "WhatsApp Sent" can be tracked and shown next time this card
        // is opened.
        if (billDocId == null || billDocId.isEmpty) {
          final newId =
              cycleId.isNotEmpty ? cycleId : 'bill_${DateTime.now().millisecondsSinceEpoch}';

          await _db.saveGeneratedBill({
            'id': newId,
            'cycleId': cycleId,
            'customerMobile': mobile,
            'customerName': customer['name'] ?? 'Customer',
            'billNumber': cycle['billNumber'],
            'totalAmount': amount,
          });

          billDocId = newId;
        }

        await _db.markBillWhatsappSent(billDocId);

        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('WhatsApp opened for this bill.')));

        await _loadAll();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open WhatsApp on this device.')));
      }
    } catch (e) {
      debugPrint('Send WhatsApp error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('WhatsApp error: $e')));
    } finally {
      if (mounted) setState(() => _busyBillIds.remove(cycleId));
    }
  }

  // ===========================================================================
  // SINGLE BILL CARD
  //
  // Now includes: View PDF, WhatsApp (send/resend), and Delete (with the
  // warning popup) for EVERY generated bill, current or historical.
  // ===========================================================================

  Widget _billHistoryCard({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> card,
  }) {
    final cycle = card['cycle'] as Map<String, dynamic>;
    final billDoc = card['billDoc'] as Map<String, dynamic>?;

    final isUnlocked = cycle['isUnlocked'] == true;
    final total = BillingService.parseAmount(cycle['totalAmount']);
    final isPaid = cycle['paymentStatus']?.toString() == 'Paid';
    final cycleId = cycle['cycleId']?.toString() ?? '';
    final isBusy = _busyBillIds.contains(cycleId);

    final billNumber = cycle['billNumber'] is int
        ? cycle['billNumber'] as int
        : int.tryParse(cycle['billNumber']?.toString() ?? '') ?? 1;

    final startDate = cycle['firstOrderTime'] is DateTime ? cycle['firstOrderTime'] as DateTime : null;
    final endDate = cycle['maturityTime'] is DateTime ? cycle['maturityTime'] as DateTime : null;

    final whatsappSent = billDoc?['whatsappSent'] == true;

    String statusLabel;
    Color statusBg;
    Color statusFg;
    IconData statusIcon;

    if (!isUnlocked) {
      statusLabel = 'Running';
      statusBg = Colors.blue.shade100;
      statusFg = Colors.blue.shade800;
      statusIcon = Icons.hourglass_top;
    } else if (isPaid) {
      statusLabel = 'Completed';
      statusBg = Colors.green.shade100;
      statusFg = Colors.green.shade800;
      statusIcon = Icons.check_circle;
    } else {
      statusLabel = 'Payment Pending';
      statusBg = Colors.orange.shade100;
      statusFg = Colors.orange.shade800;
      statusIcon = Icons.error_outline;
    }

    String formatDate(DateTime? date) {
      if (date == null) return '-';
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }

    return Opacity(
      opacity: isBusy ? 0.6 : 1.0,
      child: IgnorePointer(
        ignoring: isBusy,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isUnlocked && isPaid ? Colors.green.shade200 : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------------------------------------------------------
              // HEADER: bill number + status chip + busy spinner
              // ---------------------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Bill #$billNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Row(
                    children: [
                      if (isBusy) ...[
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 12, color: statusFg),
                            const SizedBox(width: 4),
                            Text(statusLabel,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusFg)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 5),

              Text('Started: ${formatDate(startDate)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),

              Text(
                isUnlocked
                    ? 'Unlocked: ${formatDate(endDate)}'
                    : BillingService.getRemainingTimeForCycle(cycle),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),

              const SizedBox(height: 8),

              Text(
                '₹${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E3A8A)),
              ),

              const SizedBox(height: 8),

              // ---------------------------------------------------------------
              // ACTIONS: View PDF / WhatsApp / Delete — shown on every
              // GENERATED (unlocked) bill.
              // ---------------------------------------------------------------
              if (isUnlocked)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => BillingService.printBill(
                          customer: {
                            'name': customer['name'] ?? 'Customer',
                            'mobile': customer['mobile'],
                          },
                          cycle: cycle,
                        ),
                        icon: const Icon(Icons.picture_as_pdf, size: 15, color: Colors.red),
                        label: const Text('PDF', style: TextStyle(fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _sendWhatsAppForBill(
                          customer: customer,
                          cycle: cycle,
                          billDoc: billDoc,
                        ),
                        icon: Icon(
                          Icons.chat,
                          size: 15,
                          color: whatsappSent ? Colors.green : const Color(0xFF25D366),
                        ),
                        label: Text(
                          whatsappSent ? 'Resend' : 'WhatsApp',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _deleteBillCycle(
                        customer: customer,
                        cycle: cycle,
                        billDoc: billDoc,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                      ),
                    ),
                  ],
                ),

              if (isUnlocked) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      whatsappSent ? Icons.check_circle : Icons.schedule,
                      size: 13,
                      color: whatsappSent ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      whatsappSent ? 'WhatsApp Sent' : 'WhatsApp Pending',
                      style: TextStyle(
                        fontSize: 11,
                        color: whatsappSent ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CUSTOMER CARD
  // ===========================================================================

  Widget _buildCustomerCard(Map<String, dynamic> customer, int index) {
    final mobile = customer['mobile']?.toString() ?? '';
    final name = customer['name']?.toString() ?? 'Customer';
    final email = customer['email']?.toString() ?? '';
    final address = customer['address']?.toString() ?? '';
    final route = customer['routeName']?.toString() ?? '';

    final billing = _customerBillingInfo(customer);
    final bool isPaid = billing['isPaid'] == true;
    final double pending = billing['pendingAmount'] as double;

    final bool billDue = _isDaysAfterBill(customer, _billDueAfterDays);
    final bool isExpanded = _expandedCustomers.contains(mobile);
    final bool generating = _generatingBillForMobile == mobile;

    return AnimatedZoomCard(
      index: index,
      child: Card(
        margin: const EdgeInsets.only(bottom: 14),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            // ---------------------------------------------------------------
            // FRONT / COLLAPSED CUSTOMER CARD
            // ---------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFF1E3A8A).withOpacity(0.10),
                    child: const Icon(Icons.person, color: Color(0xFF1E3A8A), size: 26),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                            ),
                            if (billDue)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                              ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_outlined, size: 16, color: Colors.red.shade400),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                address.isEmpty ? 'Address not added' : address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPaid ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isPaid ? 'Payment: Paid' : 'Payment Pending: ₹${pending.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _customerQuickIcon(
                            icon: Icons.qr_code_2,
                            color: Colors.purple,
                            tooltip: 'Show UPI QR',
                            onPressed: () => _showQrCodeDialog(customer),
                          ),
                          _customerQuickIcon(
                            icon: Icons.alt_route,
                            color: Colors.blue,
                            tooltip: 'Assign Route',
                            onPressed: () => _assignCustomerRouteDialog(customer),
                          ),
                          _customerQuickIcon(
                            icon: Icons.picture_as_pdf,
                            color: Colors.red,
                            tooltip: 'Generate Bill',
                            loading: generating,
                            onPressed: () => _generateTwoDayBill(customer),
                          ),
                          _customerQuickIcon(
                            icon: Icons.delete_outline,
                            color: Colors.redAccent,
                            tooltip: 'Delete Customer',
                            onPressed: () => _deleteCustomerDialog(customer),
                          ),
                        ],
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedCustomers.remove(mobile);
                              } else {
                                _expandedCustomers.add(mobile);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 220),
                              child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1E3A8A), size: 25),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------------
            // DROPDOWN INFORMATION
            // ---------------------------------------------------------------
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(15, 0, 15, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E3A8A).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(Icons.person_outline, size: 19, color: Color(0xFF1E3A8A)),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Complete Customer Information',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _customerInfoRow(Icons.person_outline, 'Name', name),
                          _customerInfoRow(Icons.phone_outlined, 'Mobile', mobile),
                          if (email.isNotEmpty) _customerInfoRow(Icons.email_outlined, 'Email', email),
                          _customerInfoRow(Icons.location_on_outlined, 'Address', address.isEmpty ? 'Not Added' : address),
                          _customerInfoRow(Icons.alt_route, 'Route', route.isEmpty ? 'Unassigned' : route),
                          _customerInfoRow(Icons.shopping_bag_outlined, 'Total Orders', '${billing['totalOrders']}'),
                          _customerInfoRow(Icons.pending_actions, 'Unpaid Orders', '${billing['unpaidCount']}'),
                          _customerInfoRow(Icons.account_balance_wallet_outlined, 'Pending Amount', '₹${pending.toStringAsFixed(2)}'),
                          const SizedBox(height: 5),
                          const Divider(),
                          const SizedBox(height: 10),
                          _buildCustomerBillingHistory(customer),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DASHBOARD CARD
  // ===========================================================================

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
                child: Text(title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color.shade900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUMMARY ITEM
  // ===========================================================================

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

  // ===========================================================================
  // FOOTER
  // ===========================================================================

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

  // ===========================================================================
  // RENDER CONTENT
  // ===========================================================================

  Widget _renderContent() {
    // ==========================================================================
    // CUSTOMERS
    // ==========================================================================
    if (_activeTab == 'Customers') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Customers',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
              Text('${_customers.length} Customers', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 14),
          if (_customers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No customers found.', style: TextStyle(color: Colors.grey, fontSize: 15))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _customers.length,
              itemBuilder: (context, index) => _buildCustomerCard(_customers[index], index),
            ),
        ],
      );
    }

    // ==========================================================================
    // ROUTES
    // ==========================================================================
    if (_activeTab == 'Routes') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Routes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
          const SizedBox(height: 14),
          ..._fixedRoutes.asMap().entries.map((entry) {
            final routeIndex = entry.key;
            final routeName = entry.value;

            final routeCustomers = _customers.where((customer) => customer['routeName'] == routeName).toList();

            return AnimatedZoomCard(
              index: routeIndex,
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                ),
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
                              child: const Icon(Icons.alt_route, color: Colors.green),
                            ),
                            const SizedBox(width: 10),
                            Text(routeName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E3A8A))),
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
                    if (routeCustomers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No customers assigned to this route.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      )
                    else
                      Column(
                        children: routeCustomers.map((customer) {
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline, color: Color(0xFF1E3A8A)),
                            title: Text(customer['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Mobile: ${customer['mobile']} | Address: ${customer['address'] ?? "N/A"}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _assignCustomerRouteDialog(customer),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      );
    }

    // ==========================================================================
    // ORDERS
    // ==========================================================================
    if (_activeTab == 'Orders') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
          const SizedBox(height: 14),
          if (_orders.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text('No orders found.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final order = _orders[index];
                final items = (order['items'] as List?) ?? [];
                final status = order['status'] ?? 'Placed';
                final paymentStatus = order['paymentStatus'] ?? 'Pending';
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
                                child: Text(
                                  'Customer: ${order['customerName'] ?? 'Unknown'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              Row(
                                children: [
                                  Chip(
                                    label: Text(status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                    backgroundColor: status == 'Completed' ? Colors.green : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Chip(
                                    label: Text(paymentStatus, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                    backgroundColor: isPaid ? Colors.green.shade700 : Colors.redAccent,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Text('Mobile: ${order['customerMobile']}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          Text('Address: ${order['address'] ?? "N/A"}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          const Divider(),
                          const Text('Ordered Products:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                          const SizedBox(height: 8),
                          ...items.map((product) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text('• ${product['name'] ?? 'Product'} (Qty: ${product['qty'] ?? 1})')),
                                  if (product['extra'] != null && product['extra'].toString().isNotEmpty)
                                    Text('Extra: ${product['extra']}',
                                        style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total: ₹${_parseAmount(order['totalAmount']).toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              if (order['deliveryPhoto'] != null && order['deliveryPhoto'].toString().isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => _showImageDialog(order['deliveryPhoto'], 'Delivery Photo Proof'),
                                  icon: const Icon(Icons.camera_alt, size: 16),
                                  label: const Text('View Proof'),
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
        ],
      );
    }

    // ==========================================================================
    // DELIVERY BOYS
    // ==========================================================================
    if (_activeTab == 'Delivery Boys') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Delivery Boys',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
              ElevatedButton.icon(
                onPressed: _addDeliveryBoyDialog,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add Delivery Boy'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_deliveryBoys.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text('No delivery boys yet.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _deliveryBoys.length,
              itemBuilder: (context, index) {
                final boy = _deliveryBoys[index];
                final boyMobile = boy['mobile']?.toString() ?? '';
                final route = boy['routeName']?.toString() ?? '';

                final boyOrders = _orders.where((order) {
                  final orderRoute = order['routeName']?.toString() ?? '';
                  final orderBoy = order['deliveryBoyMobile']?.toString() ?? '';
                  return orderBoy == boyMobile || (route.isNotEmpty && orderRoute == route);
                }).toList();

                return AnimatedZoomCard(
                  index: index,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: ExpansionTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Icon(Icons.delivery_dining, color: Colors.white),
                      ),
                      title: Text(boy['name'] ?? 'Delivery Boy', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Mobile: $boyMobile | Route: ${route.isEmpty ? "Unassigned" : route}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _deleteDeliveryBoyDialog(boy),
                      ),
                      children: [
                        const Divider(),
                        ...boyOrders.map((order) {
                          return ListTile(
                            title: Text('Customer: ${order['customerName'] ?? 'Unknown'}'),
                            subtitle: Text('Status: ${order['status'] ?? 'Pending'}'),
                            trailing: order['deliveryPhoto'] != null && order['deliveryPhoto'].toString().isNotEmpty
                                ? TextButton(
                                    onPressed: () => _showImageDialog(order['deliveryPhoto'], 'Delivery Proof'),
                                    child: const Text('View Photo'),
                                  )
                                : const Text('No Photo'),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  // ===========================================================================
  // MAIN BUILD
  // ===========================================================================

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
            // ------------------------------------------------------------
            // HEADER
            // ------------------------------------------------------------
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            IconButton(onPressed: _logout, icon: const Icon(Icons.exit_to_app, color: Colors.white)),
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

            // ------------------------------------------------------------
            // MAIN CONTENT
            // ------------------------------------------------------------
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_activeTab == 'Dashboard') ...[
                      const Text('Quick Management Actions',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
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
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Today's Summary",
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                                      AnimatedRotation(
                                        turns: _summaryExpanded ? 0.5 : 0,
                                        duration: const Duration(milliseconds: 260),
                                        child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1E3A8A)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 260),
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
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back to Dashboard'),
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

            // ------------------------------------------------------------
            // FOOTER
            // ------------------------------------------------------------
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
}
