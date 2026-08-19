import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add intl package in pubspec.yaml if not already present

class DateWiseBillingWidget extends StatefulWidget {
  final String orderId;

  const DateWiseBillingWidget({Key? key, required this.orderId}) : super(key: key);

  @override
  _DateWiseBillingWidgetState createState() => _DateWiseBillingWidgetState();
}

class _DateWiseBillingWidgetState extends State<DateWiseBillingWidget> {
  bool _isLoading = true;
  DateTime? _orderDate;
  DateTime? _billingDueDate;
  bool _isBillingReady = false;

  @override
  void initState() {
    super.initState();
    _fetchOrInitializeDates();
  }

  Future<void> _fetchOrInitializeDates() async {
    try {
      DocumentReference orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
      DocumentSnapshot orderDoc = await orderRef.get();

      if (orderDoc.exists) {
        Map<String, dynamic> data = orderDoc.data() as Map<String, dynamic>;
        Timestamp? storedOrderDate = data['orderDate'];
        Timestamp? storedBillingDueDate = data['billingDueDate'];

        DateTime orderDt;
        DateTime billingDt;

        if (storedOrderDate != null && storedBillingDueDate != null) {
          orderDt = storedOrderDate.toDate();
          billingDt = storedBillingDueDate.toDate();
        } else {
          // If dates don't exist yet, initialize: Order date = Today, Billing due = 2 days later
          orderDt = DateTime.now();
          billingDt = orderDt.add(const Duration(days: 2));

          await orderRef.update({
            'orderDate': Timestamp.fromDate(orderDt),
            'billingDueDate': Timestamp.fromDate(billingDt),
            'isBillingGenerated': false,
          });
        }

        // Check if current date has reached or passed the billing due date
        bool isReady = DateTime.now().isAfter(billingDt) || 
                       DateTime.now().year == billingDt.year && 
                       DateTime.now().month == billingDt.month && 
                       DateTime.now().day == billingDt.day;

        setState(() {
          _orderDate = orderDt;
          _billingDueDate = billingDt;
          _isBillingReady = isReady;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching dates: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generatePdfBill() async {
    // Logic to generate PDF bill or trigger billing generation goes here
    try {
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).update({
        'isBillingGenerated': true,
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PDF Bill generated successfully for the 2-day period!")),
      );
    } catch (e) {
      print("Error updating bill generation status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    String formattedOrderDate = _orderDate != null ? DateFormat('dd MMM yyyy').format(_orderDate!) : 'N/A';
    String formattedDueDate = _billingDueDate != null ? DateFormat('dd MMM yyyy').format(_billingDueDate!) : 'N/A';

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Billing Period Details",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Order Date: $formattedOrderDate", style: const TextStyle(fontSize: 14)),
                Text("Billing Date: $formattedDueDate", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBillingReady ? Colors.green : Colors.grey,
                ),
                onPressed: _isBillingReady ? _generatePdfBill : null,
                child: Text(
                  _isBillingReady ? "Generate PDF Bill" : "Billing Available on $formattedDueDate",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ), 
      ),
    );
  }
}