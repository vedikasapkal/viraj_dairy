import 'package:flutter/material.dart';
import '../services/billing_service.dart';
import '../services/database_service.dart';
import '../services/bill_automation_service.dart';

class CustomerBillSection extends StatefulWidget {
  final Map<String, dynamic> customerProfile;
  final List<Map<String, dynamic>> customerOrders;

  const CustomerBillSection({
    super.key,
    required this.customerProfile,
    required this.customerOrders,
  });

  @override
  State<CustomerBillSection> createState() => _CustomerBillSectionState();
}

class _CustomerBillSectionState extends State<CustomerBillSection> {
  final DatabaseService _db = DatabaseService();
  bool _checking = true;
  Map<String, dynamic>? _dueCycle;
  Map<String, dynamic>? _dueBillDoc;
  List<Map<String, dynamic>> _pastBills = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _checking = true);

    final result = await BillAutomationService.checkAndPrepareCustomerBill(
      customerProfile: widget.customerProfile,
      customerOrders: widget.customerOrders,
    );

    final mobile = widget.customerProfile['mobile']?.toString() ?? '';
    final all = await _db.getAllGeneratedBills();
    final mine = all.where((b) => b['customerMobile']?.toString() == mobile).toList();

    if (!mounted) return;
    setState(() {
      _dueCycle = result?['cycle'];
      _dueBillDoc = result?['billDoc'];
      _pastBills = mine;
      _checking = false;
    });

    // Auto-prompt WhatsApp exactly once per cycle (whatsappSent guards repeats)
    if (_dueBillDoc != null && _dueBillDoc!['whatsappSent'] != true) {
      final sent = await BillAutomationService.openWhatsAppForBill(
        mobile: mobile,
        customerName: widget.customerProfile['name'] ?? 'Customer',
        amount: BillingService.parseAmount(_dueCycle?['totalAmount']),
        billNumber: _dueCycle?['billNumber'] ?? 1,
      );
      if (sent) await BillAutomationService.markWhatsappSent(_dueBillDoc!['id']);
    }
  }

  Future<void> _viewCyclePdf(Map<String, dynamic> cycle) =>
      BillingService.printBill(customer: widget.customerProfile, cycle: cycle);

  Future<void> _viewPastBill(Map<String, dynamic> b) {
    final cycle = {
      'orders': List<Map<String, dynamic>>.from(b['orders'] ?? []),
      'totalAmount': b['totalAmount'],
      'firstOrderTime': b['firstOrderTime'],
      'maturityTime': b['maturityTime'],
      'billNumber': b['billNumber'],
    };
    return BillingService.printBill(customer: widget.customerProfile, cycle: cycle);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_dueCycle != null)
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.green, size: 30),
              title: Text('Bill #${_dueCycle!['billNumber']} is ready'),
              subtitle: Text(
                '₹${BillingService.parseAmount(_dueCycle!['totalAmount']).toStringAsFixed(2)} • 2-day cycle completed',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                onPressed: () => _viewCyclePdf(_dueCycle!),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text('Bill History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (_pastBills.isEmpty)
          const Text('No bills generated yet.', style: TextStyle(color: Colors.grey)),
        ..._pastBills.map((b) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Bill #${b['billNumber']}'),
                subtitle: Text(
                  '₹${BillingService.parseAmount(b['totalAmount']).toStringAsFixed(2)} • ${b['paymentStatus'] ?? 'Pending'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      b['whatsappSent'] == true ? Icons.check_circle : Icons.schedule,
                      color: b['whatsappSent'] == true ? Colors.green : Colors.orange,
                      size: 18,
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      onPressed: () => _viewPastBill(b),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}