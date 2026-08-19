import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BillingCountdownWidget extends StatefulWidget {
  final String orderId;

  const BillingCountdownWidget({Key? key, required this.orderId}) : super(key: key);

  @override
  _BillingCountdownWidgetState createState() => _BillingCountdownWidgetState();
}

class _BillingCountdownWidgetState extends State<BillingCountdownWidget> {
  Timer? _timer;
  int _timeLeftSeconds = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchOrInitializeExpiryTime();
  }

  Future<void> _fetchOrInitializeExpiryTime() async {
    try {
      DocumentReference orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
      DocumentSnapshot orderDoc = await orderRef.get();

      if (orderDoc.exists) {
        Map<String, dynamic> data = orderDoc.data() as Map<String, dynamic>;
        Timestamp? expiryTimestamp = data['billingExpiryTime'];

        DateTime expiryTime;
        if (expiryTimestamp != null) {
          expiryTime = expiryTimestamp.toDate();
        } else {
          // If order doesn't have an expiry time yet, set it to 2 days from now and save to Firebase
          expiryTime = DateTime.now().add(const Duration(days: 2));
          await orderRef.update({
            'billingExpiryTime': Timestamp.fromDate(expiryTime),
            'isBillingGenerated': false,
          });
        }

        _calculateTimeLeft(expiryTime);
      }
    } catch (e) {
      print("Error fetching timer: $e");
      setState(() => _isLoading = false);
    }
  }

  void _calculateTimeLeft(DateTime expiryTime) {
    DateTime now = DateTime.now();
    int difference = expiryTime.difference(now).inSeconds;

    setState(() {
      _timeLeftSeconds = difference > 0 ? difference : 0;
      _isLoading = false;
    });

    _startCountdown(expiryTime);
  }

  void _startCountdown(DateTime expiryTime) {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      DateTime now = DateTime.now();
      int difference = expiryTime.difference(now).inSeconds;

      if (difference > 0) {
        setState(() {
          _timeLeftSeconds = difference;
        });
      } else {
        setState(() {
          _timeLeftSeconds = 0;
        });
        timer.cancel();
        _markBillingGenerated();
      }
    });
  }

  Future<void> _markBillingGenerated() async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).update({
        'isBillingGenerated': true,
      });
    } catch (e) {
      print("Error updating billing status: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    int days = _timeLeftSeconds ~/ (3600 * 24);
    int hours = (_timeLeftSeconds % (3600 * 24)) ~/ 3600;
    int minutes = (_timeLeftSeconds % 3600) ~/ 60;
    int seconds = _timeLeftSeconds % 60;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Billing Cycle Timer (2 Days)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "${days}d ${hours}h ${minutes}m ${seconds}s",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueAccent),
            ),
            const SizedBox(height: 4),
            const Text(
              "Time reduces continuously in Firebase. Safe across logouts and page refreshes.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}