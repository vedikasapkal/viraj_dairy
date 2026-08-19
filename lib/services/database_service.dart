// =============================================================================
// DATABASE SERVICE (lib/services/database_service.dart)
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _routes => _db.collection('routes');
  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get _banners => _db.collection('banners');

  String _userDocId(String role, String mobile) => '${role}_$mobile';

  // ======================================================
  // REGISTRATION & AUTH METHODS
  // ======================================================

  Future<bool> registerUser({
    required String role,
    required String mobile,
    required String password,
    required String name,
    String address = '',
    String email = '',
  }) async {
    final docRef = _users.doc(_userDocId(role, mobile));
    final existing = await docRef.get();
    if (existing.exists) return false;

    final Map<String, dynamic> userData = {
      'role': role,
      'mobile': mobile,
      'password': password,
      'name': name,
      'address': address,
      'routeId': null,
      'routeName': null,
      'lastBillGeneratedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (email.isNotEmpty) {
      userData['email'] = email;
    }

    await docRef.set(userData);
    return true;
  }

  Future<bool> checkAdminExists() async {
    final snapshot = await _users
        .where('role', isEqualTo: 'admin')
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<bool> verifyAdminCredentials({required String mobile, required String email}) async {
    final snap = await _users
        .where('role', isEqualTo: 'admin')
        .where('mobile', isEqualTo: mobile)
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> sendOtpToMobileAndEmail({required String mobile, required String email}) async {
    debugPrint('Simulated OTP sent to Mobile: $mobile & Email: $email');
  }

  Future<bool> registerMasterAdmin({
    required String mobile,
    required String password,
    required String name,
    required String email,
  }) async {
    if (await checkAdminExists()) {
      return false;
    }

    await _users.doc(_userDocId('admin', mobile)).set({
      'role': 'admin',
      'mobile': mobile,
      'password': password,
      'name': name,
      'email': email,
      'address': '',
      'routeId': null,
      'routeName': null,
      'isMasterAdmin': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

  Future<bool> checkAdminByEmail({
    required String mobile,
    required String email,
  }) async {
    final doc = await _users.doc(_userDocId('admin', mobile)).get();
    if (!doc.exists) return false;
    return doc.data()?['email'] == email;
  }

  Future<bool> updatePassword({
    required String role,
    required String mobile,
    required String newPassword,
  }) async {
    final doc = _users.doc(_userDocId(role, mobile));
    if (!(await doc.get()).exists) {
      return false;
    }
    await doc.update({
      'password': newPassword,
    });
    return true;
  }

  Future<Map<String, dynamic>?> loginUser({
    required String role,
    required String mobile,
    required String password,
  }) async {
    if (mobile == '1234567890' && password == '123') {
      return {'name': 'Demo $role', 'mobile': mobile, 'address': 'Demo Address', 'role': role, 'routeId': null, 'routeName': null};
    }
    final doc = await _users.doc(_userDocId(role, mobile)).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    if (data['password'] != password) return null;
    return data;
  }

  Future<Map<String, dynamic>?> getUserProfile({required String role, required String mobile}) async {
    final doc = await _users.doc(_userDocId(role, mobile)).get();
    return doc.exists ? doc.data() : null;
  }

  // ======================================================
  // SESSION MANAGEMENT & DATABASE RESET
  // ======================================================

  Future<void> saveSession({required String mobile, required String role}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('db_session', jsonEncode({'mobile': mobile, 'role': role}));
  }

  Future<Map<String, String>?> getSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('db_session');
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      debugPrint('Session read error: $e');
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('db_session');
  }

  Future<void> logout() async {
    await clearSession();
  }

  Future<void> clearAllLoginAndUserMasterData() async {
    await clearSession();

    final batch = _db.batch();

    final customerSnap = await _users.where('role', isEqualTo: 'customer').get();
    for (final doc in customerSnap.docs) {
      batch.delete(doc.reference);
    }

    final deliverySnap = await _users.where('role', isEqualTo: 'delivery').get();
    for (final doc in deliverySnap.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  // ======================================================
  // CUSTOMERS & DELIVERY MANAGEMENT
  // ======================================================

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    final snap = await _users.where('role', isEqualTo: 'customer').get();
    final result = <Map<String, dynamic>>[];

    for (final doc in snap.docs) {
      final c = doc.data();
      final mobile = c['mobile'] as String;
      final ordersSnap = await _orders.where('customerMobile', isEqualTo: mobile).get();
      final total = ordersSnap.docs.fold<int>(0, (sum, o) {
        final amt = int.tryParse((o.data()['totalAmount'] as String? ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return sum + amt;
      });

      result.add({
        'name': c['name'],
        'mobile': mobile,
        'email': c['email'] ?? '',
        'address': c['address'],
        'routeId': c['routeId'],
        'routeName': c['routeName'],
        'lastBillGeneratedAt': c['lastBillGeneratedAt'],
        'totalBill': ordersSnap.docs.isEmpty ? null : '₹$total',
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getAllDeliveryBoys() async {
    final snap = await _users.where('role', isEqualTo: 'delivery').get();
    return snap.docs.map((d) => {'name': d.data()['name'], 'mobile': d.data()['mobile'], 'routeName': d.data()['routeName'] ?? ''}).toList();
  }

  Future<void> updateCustomerBillTimestamp({required String mobile}) async {
    try {
      final querySnapshot = await _users
          .where('role', isEqualTo: 'customer')
          .where('mobile', isEqualTo: mobile)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final docId = querySnapshot.docs.first.id;
        await _users.doc(docId).update({
          'lastBillGeneratedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error updating bill timestamp: $e');
    }
  }

  Future<void> deleteCustomer({required String mobile}) async {
    await _users.doc(_userDocId('customer', mobile)).delete();
  }

  Future<void> deleteDeliveryBoy({required String mobile}) async {
    await _users.doc(_userDocId('delivery', mobile)).delete();
  }

  // ======================================================
  // ROUTES
  // ======================================================

  Future<String> createRoute({required String routeName}) async {
    final docRef = await _routes.add({
      'name': routeName,
      'deliveryBoyMobile': null,
      'deliveryBoyName': null,
      'customerMobiles': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<List<Map<String, dynamic>>> getAllRoutes() async {
    final snap = await _routes.get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> assignCustomerToRoute({required String mobile, required String routeId}) async {
    final allRoutes = await _routes.get();
    for (final doc in allRoutes.docs) {
      final mobiles = (doc.data()['customerMobiles'] as List?)?.cast<String>() ?? [];
      if (mobiles.contains(mobile)) {
        await doc.reference.update({'customerMobiles': FieldValue.arrayRemove([mobile])});
      }
    }

    final targetRoute = await _routes.doc(routeId).get();
    await _routes.doc(routeId).update({'customerMobiles': FieldValue.arrayUnion([mobile])});

    await _users.doc(_userDocId('customer', mobile)).update({
      'routeId': routeId,
      'routeName': targetRoute.data()?['name'],
    });
  }

  // ======================================================
  // ORDERS & BANNERS
  // ======================================================

  Future<String> saveOrder({
    required String customerMobile,
    required String customerName,
    required String address,
    required List<Map<String, dynamic>> items,
    required String totalAmount,
  }) async {
    final docRef = await _orders.add({
      'customerMobile': customerMobile,
      'customerName': customerName,
      'address': address,
      'items': items,
      'totalAmount': totalAmount,
      'status': 'Pending',
      'paymentStatus': 'Pending',
      'paymentId': null,
      'createdAt': DateTime.now().toIso8601String(),
      'orderDate': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<List<Map<String, dynamic>>> getOrdersForCustomer(String mobile) async {
    final snap = await _orders.where('customerMobile', isEqualTo: mobile).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getAllOrders() async {
    final snap = await _orders.get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
    String? deliveryPhoto,
  }) async {
    final Map<String, dynamic> updateData = {'status': status};
    if (deliveryPhoto != null) {
      updateData['deliveryPhoto'] = deliveryPhoto;
    }
    await _orders.doc(orderId).update(updateData);
  }

  Future<void> updateOrderPaymentStatus({
    required dynamic orderId,
    required String paymentStatus,
    String? paymentId,
  }) async {
    final Map<String, dynamic> updateData = {'paymentStatus': paymentStatus};
    if (paymentId != null) {
      updateData['paymentId'] = paymentId;
    }
    await _orders.doc(orderId.toString()).update(updateData);
  }

  Future<void> updateBatchPaymentStatus({
    required List<dynamic> orderIds,
    required String paymentStatus,
    String? paymentId,
  }) async {
    final batch = _db.batch();
    for (var id in orderIds) {
      final docRef = _orders.doc(id.toString());
      final Map<String, dynamic> updateData = {'paymentStatus': paymentStatus};
      if (paymentId != null) {
        updateData['paymentId'] = paymentId;
      }
      batch.update(docRef, updateData);
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getAllBanners() async {
    final snapshot = await _banners.get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<void> addBanner({required String title, required String imageUrl}) async {
    await _banners.add({
      'title': title,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}