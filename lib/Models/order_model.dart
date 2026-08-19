import 'package:cloud_firestore/cloud_firestore.dart';

class OrderModel {
  final String id;
  final String customerMobile;
  final String customerName;
  final String address;
  final List<Map<String, dynamic>> items;
  final String totalAmount;
  final String status;
  final String? deliveryPhoto;
  final Timestamp? orderDate;          // Date when order was placed
  final Timestamp? billingDueDate;     // Date when billing generates (e.g., +2 days)
  final bool isBillingGenerated;

  OrderModel({
    required this.id,
    required this.customerMobile,
    required this.customerName,
    required this.address,
    required this.items,
    required this.totalAmount,
    required this.status,
    this.deliveryPhoto,
    this.orderDate,
    this.billingDueDate,
    this.isBillingGenerated = false,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'] ?? '',
      customerMobile: map['customerMobile'] ?? '',
      customerName: map['customerName'] ?? 'Unknown',
      address: map['address'] ?? 'N/A',
      items: (map['items'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      totalAmount: map['totalAmount'] ?? '₹0',
      status: map['status'] ?? 'Pending',
      deliveryPhoto: map['deliveryPhoto'],
      orderDate: map['orderDate'],
      billingDueDate: map['billingDueDate'],
      isBillingGenerated: map['isBillingGenerated'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerMobile': customerMobile,
      'customerName': customerName,
      'address': address,
      'items': items,
      'totalAmount': totalAmount,
      'status': status,
      'deliveryPhoto': deliveryPhoto,
      'orderDate': orderDate,
      'billingDueDate': billingDueDate,
      'isBillingGenerated': isBillingGenerated,
    };
  }

  bool get isCompleted => status == 'Completed' || status == 'Delivered';
}
