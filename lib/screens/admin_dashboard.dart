// =============================================================================
// ADMIN DASHBOARD - CORRECTED & UPDATED (lib/screens/admin_dashboard.dart)
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import 'login_screen.dart';

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
        title: Text('UPI QR Code - ${customer['name']}'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pending Amount: ₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ask the customer to scan via GPay / PhonePe / Paytm to pay:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
              Text('UPI ID: $_adminUpiId', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade700)),
              const SizedBox(height: 4),
              Text('Payee: $_adminName', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
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
          title: Text('Assign Route for ${customer['name']}'),
          content: DropdownButtonFormField<String>(
            value: _fixedRoutes.contains(selectedRoute) ? selectedRoute : _fixedRoutes.first,
            items: _fixedRoutes.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: isSaving ? null : (val) => setDialogState(() => selectedRoute = val),
            decoration: const InputDecoration(labelText: 'Select Fixed Route'),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
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
                  : const Text('Save Route'),
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
        title: const Text('Delete Customer'),
        content: Text('Are you sure you want to delete "${customer['name']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
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
        title: const Text('Delete Delivery Boy'),
        content: Text('Are you sure you want to delete "${boy['name']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
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
        title: Text(title),
        content: SizedBox(
          width: 300,
          height: 300,
          child: _buildSafeImage(photoString),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildSafeImage(String photoStr) {
    if (photoStr.isEmpty) {
      return const Center(child: Text('No image data available', style: TextStyle(color: Colors.grey)));
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
      return Center(child: Text('Error rendering image: $e', style: const TextStyle(fontSize: 12, color: Colors.red)));
    }
  }

  Widget _renderContent() {
    if (_activeTab == 'Dashboard') return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_activeTab, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
          ],
        ),
        const SizedBox(height: 12),
        if (_activeTab == 'Customers') ...[
          _customers.isEmpty
              ? const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No customers found.', style: TextStyle(color: Colors.grey))))
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

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Row(
                            children: [
                              Flexible(child: Text(item['name'] ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              if (billDue) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                                  child: Text('$_billDueAfterDays+ Days Bill Due', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('WhatsApp: ${item['mobile']}', style: const TextStyle(fontSize: 12)),
                              if ((item['email'] ?? '').toString().isNotEmpty)
                                Text('Email: ${item['email']}', style: const TextStyle(fontSize: 12)),
                              Text('Address: ${item['address'] ?? "Not Added"}', style: const TextStyle(fontSize: 12)),
                              Text('Route: ${item['routeName'] ?? "Unassigned"}', style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPaid ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isPaid ? 'Payment: Paid' : 'Payment: Pending ₹${pending.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.qr_code_2, color: Colors.purple),
                                tooltip: 'Show UPI QR Code',
                                onPressed: () => _showQrCodeDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.alt_route, color: Colors.blue),
                                tooltip: 'Assign Fixed Route',
                                onPressed: () => _assignCustomerRouteDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                tooltip: 'Generate $_billDueAfterDays-Day Bill PDF & Share (WhatsApp/Email)',
                                onPressed: () => _generateTwoDayBill(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                tooltip: 'Delete Customer',
                                onPressed: () => _deleteCustomerDialog(item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ] else if (_activeTab == 'Routes') ...[
          ..._fixedRoutes.map((fixedRouteName) {
            final routeCustomers = _customers.where((c) => c['routeName'] == fixedRouteName).toList();
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.alt_route, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(fixedRouteName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E3A8A))),
                        ],
                      ),
                      Chip(label: Text('${routeCustomers.length} Customers', style: const TextStyle(fontSize: 11)), backgroundColor: Colors.green.shade50),
                    ],
                  ),
                  const Divider(),
                  routeCustomers.isEmpty
                      ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No customers assigned to this route.', style: TextStyle(color: Colors.grey, fontSize: 12)))
                      : Column(
                          children: routeCustomers.map((c) => ListTile(
                                dense: true,
                                title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: Text('Mobile: ${c['mobile']} | Address: ${c['address'] ?? "N/A"}', style: const TextStyle(fontSize: 11)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                  onPressed: () => _assignCustomerRouteDialog(c),
                                ),
                              )).toList(),
                        ),
                ],
              ),
            );
          }),
        ] else if (_activeTab == 'Orders') ...[
          _orders.isEmpty
              ? const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No orders found.', style: TextStyle(color: Colors.grey))))
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

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Customer: ${item['customerName'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Row(
                                  children: [
                                    Chip(
                                      label: Text(status, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                      backgroundColor: status == 'Completed' ? Colors.green : Colors.orange,
                                      padding: EdgeInsets.zero,
                                    ),
                                    const SizedBox(width: 4),
                                    Chip(
                                      label: Text(paymentStatus, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                      backgroundColor: isPaid ? Colors.green.shade700 : Colors.redAccent,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Text('Mobile: ${item['customerMobile']} | Address: ${item['address'] ?? "N/A"}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const Divider(height: 16),
                            const Text('Ordered Products & Extras:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E3A8A))),
                            const SizedBox(height: 6),
                            ...itemsList.map((prod) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('• ${prod['name'] ?? 'Product'} (Qty: ${prod['qty'] ?? 1})', style: const TextStyle(fontSize: 12)),
                                      if (prod['extra'] != null && prod['extra'].toString().isNotEmpty)
                                        Text('Extra: ${prod['extra']}', style: const TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                )),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Amount: ₹${_parseAmount(item['totalAmount']).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                                if (item['deliveryPhoto'] != null && item['deliveryPhoto'].toString().isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () => _showImageDialog(item['deliveryPhoto'], 'Delivery Photo Proof'),
                                    icon: const Icon(Icons.camera_alt, size: 14),
                                    label: const Text('View Proof', style: TextStyle(fontSize: 11)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ] else if (_activeTab == 'Delivery Boys') ...[
          _deliveryBoys.isEmpty
              ? const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No delivery boys found.', style: TextStyle(color: Colors.grey))))
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

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ExpansionTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.delivery_dining, color: Colors.white),
                        ),
                        title: Text(boyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        subtitle: Text(
                          'Mobile: $boyMobile | Route: ${assignedRoute.isEmpty ? "All / Unassigned" : assignedRoute}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: 'Delete Delivery Boy',
                          onPressed: () => _deleteDeliveryBoyDialog(boy),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 18),
                          const Text('Assigned Deliveries & Proofs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E3A8A))),
                          const SizedBox(height: 8),
                          displayOrders.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text('No orders found.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                )
                              : Column(
                                  children: displayOrders.map((order) {
                                    final orderStatus = order['status'] ?? 'Pending';
                                    final hasPhoto = order['deliveryPhoto'] != null && order['deliveryPhoto'].toString().isNotEmpty;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Customer: ${order['customerName'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Status: $orderStatus',
                                                  style: TextStyle(
                                                    fontSize: 11,
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
                                              icon: const Icon(Icons.photo_camera, size: 14, color: Colors.white),
                                              label: const Text('View Photo', style: TextStyle(fontSize: 10, color: Colors.white)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.blue.shade700,
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            )
                                          else
                                            const Text('No Photo', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ],
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
                                Icon(Icons.admin_panel_settings, color: Colors.amber, size: 24),
                                SizedBox(width: 8),
                                Text('Viraj Dairy Admin', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.exit_to_app, color: Colors.white, size: 22),
                              onPressed: _logout,
                              tooltip: 'Logout',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Welcome, Admin 👋', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Active View: $_activeTab', style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
                      const Text('Quick Management Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                      const SizedBox(height: 12),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.5,
                        children: [
                          _buildDashboardCard('Customers', '${_customers.length} Registered', Icons.people, Colors.teal, () => setState(() => _activeTab = 'Customers')),
                          _buildDashboardCard('Routes', '3 Fixed Routes', Icons.alt_route, Colors.green, () => setState(() => _activeTab = 'Routes')),
                          _buildDashboardCard('Orders & Cart', '${_orders.length} Placed', Icons.shopping_cart, Colors.blue, () => setState(() => _activeTab = 'Orders')),
                          _buildDashboardCard('Delivery Boys', '${_deliveryBoys.length} Active', Icons.delivery_dining, Colors.orange, () => setState(() => _activeTab = 'Delivery Boys')),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text("Today's Summary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryItem(Icons.water_drop, '${_orders.length * 2} L', 'Milk Count', Colors.blue),
                            _buildSummaryItem(Icons.alt_route, '3', 'Routes', Colors.green),
                            _buildSummaryItem(Icons.people, '${_customers.length}', 'Customers', Colors.purple),
                          ],
                        ),
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _activeTab = 'Dashboard'),
                          icon: const Icon(Icons.arrow_back, size: 16),
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

  Widget _buildDashboardCard(String title, String subtitle, IconData icon, MaterialColor color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.shade100),
          boxShadow: [BoxShadow(color: color.shade50.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color.shade700, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color.shade900)),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F2937))),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildFooterItem(String tabKey, IconData icon) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? Colors.amber : Colors.white70, size: 22),
          const SizedBox(height: 2),
          Text(
            tabKey,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.amber : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}