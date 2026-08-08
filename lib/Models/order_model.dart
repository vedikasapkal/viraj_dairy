// =============================================================================
// ORDER MODEL (lib/models/order_model.dart)
// DatabaseService still returns/accepts List<Map<String,dynamic>> exactly as
// before (that's the real "dataflow" your screens rely on) — this class is a
// thin, optional typed view over the same map so screens that want type safety
// can use OrderModel.fromMap(...) without anything else having to change.
// =============================================================================

class OrderModel {
  final String id;
  final String customerMobile;
  final String customerName;
  final String address;
  final List<Map<String, dynamic>> items;
  final String totalAmount;
  final String status;
  final String? deliveryPhoto;

  OrderModel({
    required this.id,
    required this.customerMobile,
    required this.customerName,
    required this.address,
    required this.items,
    required this.totalAmount,
    required this.status,
    this.deliveryPhoto,
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
    };
  }

  bool get isCompleted => status == 'Completed' || status == 'Delivered';
}
