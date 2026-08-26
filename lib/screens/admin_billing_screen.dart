// =============================================================================
// ADMIN BILLING SCREEN
// lib/screens/admin_billing_screen.dart
// =============================================================================

import 'package:flutter/material.dart';
import '../services/billing_service.dart';
import '../services/admin_billing_service.dart';

class AdminBillingScreen extends StatefulWidget {
  final List<Map<String, dynamic>> allOrders;
  final List<Map<String, dynamic>> customerProfiles;
  final Function(String cycleId, String newStatus)? onStatusChanged;

  const AdminBillingScreen({
    Key? key,
    required this.allOrders,
    required this.customerProfiles,
    this.onStatusChanged,
  }) : super(key: key);

  @override
  State<AdminBillingScreen> createState() => _AdminBillingScreenState();
}

class _AdminBillingScreenState extends State<AdminBillingScreen> {
  String _selectedFilter = 'All'; // 'All', 'Pending', 'Paid'
  String _searchQuery = '';
  bool _isGeneratingPdf = false;

  @override
  Widget build(BuildContext context) {
    // Process rolling billing cycles for all customers
    final cycles = BillingService.getAllCustomerCycles(widget.allOrders);

    // Create a fast lookup for customer profile metadata
    final Map<String, Map<String, dynamic>> customerMap = {
      for (var c in widget.customerProfiles) c['mobile']?.toString() ?? '': c
    };

    // Calculate aggregated financial metrics
    double totalRevenue = 0.0;
    double totalCollected = 0.0;
    double totalPending = 0.0;

    for (final cycle in cycles) {
      double amt = BillingService.parseAmount(cycle['totalAmount']);
      if (amt == 0) {
        final orders = (cycle['orders'] as List?) ?? [];
        for (final o in orders) {
          amt += BillingService.orderTotal(o as Map<String, dynamic>);
        }
        // Add delivery charges (5 per day * 2 days = 10)
        amt += 10.0;
      }

      totalRevenue += amt;
      if (cycle['paymentStatus'] == 'Paid') {
        totalCollected += amt;
      } else {
        totalPending += amt;
      }
    }

    // Filter list according to search and status selection
    final filteredCycles = cycles.where((cycle) {
      final mobile = cycle['customerMobile']?.toString() ?? '';
      final profile = customerMap[mobile];
      final name = profile?['name']?.toString() ?? 'Customer';
      final status = cycle['paymentStatus']?.toString() ?? 'Pending';

      final matchesSearch = name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          mobile.contains(_searchQuery);
      
      final matchesFilter = _selectedFilter == 'All' || status == _selectedFilter;

      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Billing Dashboard'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf),
            tooltip: 'Print Master Statement',
            onPressed: _isGeneratingPdf
                ? null
                : () async {
                    setState(() => _isGeneratingPdf = true);
                    try {
                      await AdminBillingService.printAdminMasterSummary(
                        allOrders: widget.allOrders,
                        customerProfiles: widget.customerProfiles,
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error printing summary: $e')),
                      );
                    } finally {
                      setState(() => _isGeneratingPdf = false);
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Metrics Cards Summary
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                _buildMetricCard(
                  'Total Value',
                  '₹${totalRevenue.toStringAsFixed(2)}',
                  Colors.blue.shade900,
                ),
                const SizedBox(width: 8),
                _buildMetricCard(
                  'Collected',
                  '₹${totalCollected.toStringAsFixed(2)}',
                  Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                _buildMetricCard(
                  'Pending',
                  '₹${totalPending.toStringAsFixed(2)}',
                  Colors.red.shade700,
                ),
              ],
            ),
          ),

          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search customer name or mobile...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedFilter,
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedFilter = val);
                  },
                ),
              ],
            ),
          ),

          // Customer Billing Cycle List
          Expanded(
            child: filteredCycles.isEmpty
                ? const Center(child: Text('No billing cycles found.'))
                : ListView.builder(
                    itemCount: filteredCycles.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, index) {
                      final cycle = filteredCycles[index];
                      final mobile = cycle['customerMobile']?.toString() ?? '';
                      final profile = customerMap[mobile] ?? {};
                      final name = profile['name']?.toString() ?? 'Unknown Customer';
                      final orders = (cycle['orders'] as List?) ?? [];
                      final status = cycle['paymentStatus']?.toString() ?? 'Pending';
                      final isUnlocked = cycle['isUnlocked'] == true;

                      double total = BillingService.parseAmount(cycle['totalAmount']);
                      if (total == 0) {
                        for (final o in orders) {
                          total += BillingService.orderTotal(o as Map<String, dynamic>);
                        }
                        total += 10.0; // Delivery charges (₹5 * 2 days)
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: isUnlocked
                                ? Colors.green.shade100
                                : Colors.amber.shade100,
                            child: Icon(
                              isUnlocked ? Icons.lock_open : Icons.hourglass_top,
                              color: isUnlocked
                                  ? Colors.green.shade800
                                  : Colors.amber.shade800,
                            ),
                          ),
                          title: Text(
                            '$name ($mobile)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Bill #${cycle['billNumber']} • ${orders.length} Orders • ₹${total.toStringAsFixed(2)}',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: status == 'Paid'
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: status == 'Paid'
                                    ? Colors.green.shade900
                                    : Colors.red.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cycle ID: ${cycle['cycleId']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    'Status: ${BillingService.getRemainingTimeForCycle(cycle)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const Divider(),
                                  const Text(
                                    'Included Orders & Charges:',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  ...orders.map((o) {
                                    final oMap = o as Map<String, dynamic>;
                                    final amt = BillingService.orderTotal(oMap);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Order #${oMap['id']}'),
                                          Text('₹${amt.toStringAsFixed(2)}'),
                                        ],
                                      ),
                                    );
                                  }),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Delivery Charges (2 Days @ ₹5/day)'),
                                        Text('₹10.00'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          BillingService.printBill(
                                            customer: {
                                              'name': name,
                                              'mobile': mobile,
                                            },
                                            cycle: cycle,
                                          );
                                        },
                                        icon: const Icon(Icons.print, size: 16),
                                        label: const Text('Print Bill'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue.shade900,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                      OutlinedButton(
                                        onPressed: () {
                                          final newStatus =
                                              status == 'Paid' ? 'Pending' : 'Paid';
                                          if (widget.onStatusChanged != null) {
                                            widget.onStatusChanged!(
                                              cycle['cycleId'],
                                              newStatus,
                                            );
                                          }
                                          setState(() {
                                            cycle['paymentStatus'] = newStatus;
                                          });
                                        },
                                        child: Text(
                                          status == 'Paid'
                                              ? 'Mark Pending'
                                              : 'Mark Paid',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}