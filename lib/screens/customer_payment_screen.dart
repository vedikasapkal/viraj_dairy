// =============================================================================
// UPDATED CUSTOMER BILLING & PAYMENT SCREEN (lib/screens/customer_payment_screen.dart)
// Logic Update: 48-Hour Strict Window Restriction
// - A billing cycle (and its combined PDF / Total Amount / QR code) ONLY unlocks and 
//   becomes available to the customer AFTER 48 full hours have elapsed from the 
//   start (first order) of that billing cycle.
// - If the 48 hours have not yet passed, the screen explicitly displays a countdown 
//   and locks bill generation/payment until the precise maturity timestamp is reached.
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/database_service.dart';

class CustomerPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerPaymentScreen({super.key, required this.customer});

  @override
  State<CustomerPaymentScreen> createState() => _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends State<CustomerPaymentScreen> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _customerOrders = [];
  List<Map<String, dynamic>> _billingCycles = [];
  Map<String, dynamic>? _selectedCycle;
  bool _loading = true;
  Timer? _statusPollTimer;
  Timer? _countdownTimer;

  // Admin UPI Details
  final String _adminUpiId = '9850921154@paytm';
  final String _adminName = 'Viraj Dairy Admin';

  @override
  void initState() {
    super.initState();
    _loadOrdersAndGroupCycles();
    
    // Poll the database every 5 seconds to update orders & maturity statuses automatically
    _statusPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _silentRefreshOrders();
    });

    // Update UI every 1 second to refresh active countdown timers if a cycle is awaiting 48 hours
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrdersAndGroupCycles() async {
    setState(() => _loading = true);
    try {
      final allOrders = await _db.getAllOrders();
      final mobile = widget.customer['mobile'] ?? '';
      
      // Filter orders belonging strictly to this customer
      _customerOrders = allOrders.where((o) => o['customerMobile'] == mobile).toList();
      
      // Sort orders chronologically (oldest first)
      _customerOrders.sort((a, b) {
        final dateA = DateTime.tryParse(a['date'] ?? a['createdAt'] ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['date'] ?? b['createdAt'] ?? '') ?? DateTime(2000);
        if (dateA.compareTo(dateB) != 0) return dateA.compareTo(dateB);
        
        final idA = int.tryParse(a['id'].toString()) ?? 0;
        final idB = int.tryParse(b['id'].toString()) ?? 0;
        return idA.compareTo(idB);
      });

      // Group orders using the 48-Hour Strict Rule
      _billingCycles = _groupOrdersStrict48Hours(_customerOrders);

      if (_billingCycles.isNotEmpty) {
        if (_selectedCycle != null) {
          final matched = _billingCycles.firstWhere(
            (c) => c['cycleId'] == _selectedCycle!['cycleId'],
            orElse: () => _billingCycles.last,
          );
          _selectedCycle = matched;
        } else {
          _selectedCycle = _billingCycles.last;
        }
      } else {
        _selectedCycle = null;
      }
    } catch (e) {
      debugPrint('Error loading customer orders: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _silentRefreshOrders() async {
    try {
      final allOrders = await _db.getAllOrders();
      final mobile = widget.customer['mobile'] ?? '';
      final updatedOrders = allOrders.where((o) => o['customerMobile'] == mobile).toList();
      
      updatedOrders.sort((a, b) {
        final dateA = DateTime.tryParse(a['date'] ?? a['createdAt'] ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['date'] ?? b['createdAt'] ?? '') ?? DateTime(2000);
        if (dateA.compareTo(dateB) != 0) return dateA.compareTo(dateB);
        
        final idA = int.tryParse(a['id'].toString()) ?? 0;
        final idB = int.tryParse(b['id'].toString()) ?? 0;
        return idA.compareTo(idB);
      });

      final updatedCycles = _groupOrdersStrict48Hours(updatedOrders);
      
      if (mounted && updatedCycles.isNotEmpty) {
        setState(() {
          _customerOrders = updatedOrders;
          _billingCycles = updatedCycles;
          if (_selectedCycle != null) {
            _selectedCycle = _billingCycles.firstWhere(
              (c) => c['cycleId'] == _selectedCycle!['cycleId'],
              orElse: () => _billingCycles.last,
            );
          } else {
            _selectedCycle = _billingCycles.last;
          }
        });
      }
    } catch (e) {
      debugPrint('Silent refresh error: $e');
    }
  }

  /// Implements strict 48-hour cycle grouping:
  /// - A cycle starts with an initial order.
  /// - Subsequent orders placed within 48 hours from that first order are batched together.
  /// - Once 48 hours have elapsed from the start of the batch, the cycle closes and 
  ///   any further orders form the next cycle.
  List<Map<String, dynamic>> _groupOrdersStrict48Hours(List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) return [];

    List<Map<String, dynamic>> cycles = [];
    List<Map<String, dynamic>> currentChunk = [];
    DateTime? firstOrderTime;
    int cycleCounter = 1;

    for (int i = 0; i < orders.length; i++) {
      final order = orders[i];
      final orderDate = DateTime.tryParse(order['date'] ?? order['createdAt'] ?? '') ?? DateTime.now();

      if (currentChunk.isEmpty) {
        currentChunk.add(order);
        firstOrderTime = orderDate;
      } else {
        bool exceeded48Hours = false;
        if (firstOrderTime != null) {
          final difference = orderDate.difference(firstOrderTime);
          if (difference.inHours >= 48) {
            exceeded48Hours = true;
          }
        }

        if (exceeded48Hours) {
          cycles.add(_buildCycleMap(cycleCounter++, currentChunk, firstOrderTime!));
          currentChunk = [order];
          firstOrderTime = orderDate;
        } else {
          currentChunk.add(order);
        }
      }
    }

    if (currentChunk.isNotEmpty && firstOrderTime != null) {
      cycles.add(_buildCycleMap(cycleCounter++, currentChunk, firstOrderTime));
    }

    return cycles;
  }

  Map<String, dynamic> _buildCycleMap(int cycleNumber, List<Map<String, dynamic>> chunk, DateTime firstOrderTime) {
    double totalCycleAmount = 0.0;
    bool allPaid = true;
    List<String> orderIds = [];

    for (var o in chunk) {
      totalCycleAmount += _parseAmount(o['totalAmount']);
      if ((o['paymentStatus'] ?? 'Pending') != 'Paid') {
        allPaid = false;
      }
      orderIds.add(o['id'].toString());
    }

    // Maturity time is exactly 48 hours after the first order's timestamp
    final maturityTime = firstOrderTime.add(const Duration(hours: 48));
    final bool isMatured = DateTime.now().isAfter(maturityTime);

    final firstDateStr = chunk.first['date'] ?? chunk.first['createdAt'] ?? 'N/A';
    final lastDateStr = chunk.last['date'] ?? chunk.last['createdAt'] ?? firstDateStr;
    String label = 'Bill #$cycleNumber (${chunk.length} ${chunk.length == 1 ? 'Order' : 'Orders'})';

    return {
      'cycleId': 'batch_$cycleNumber',
      'label': label,
      'dateRange': 'Start: $firstDateStr',
      'orders': chunk,
      'orderIds': orderIds,
      'totalAmount': totalCycleAmount,
      'paymentStatus': allPaid ? 'Paid' : 'Pending',
      'firstOrderTime': firstOrderTime,
      'maturityTime': maturityTime,
      'isMatured': isMatured,
    };
  }

  double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  // Generate and Download PDF Bill (Only accessible if 48 hours have passed)
  Future<void> _generateAndDownloadPdf(Map<String, dynamic> cycle) async {
    final pdf = pw.Document();
    final orders = cycle['orders'] as List<Map<String, dynamic>>;
    final totalAmount = cycle['totalAmount'] as double;
    final paymentStatus = cycle['paymentStatus'] as String;
    final customerName = widget.customer['name'] ?? 'Valued Customer';
    final customerMobile = widget.customer['mobile'] ?? '';

    final Map<String, pw.ImageProvider?> loadedImages = {};
    for (var order in orders) {
      final photoUrl = order['deliveryPhotoUrl'] ?? order['imageUrl'] ?? order['photo'];
      if (photoUrl != null && photoUrl.toString().isNotEmpty) {
        try {
          final netImage = await networkImage(photoUrl.toString());
          loadedImages[order['id'].toString()] = netImage;
        } catch (_) {}
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('VIRAJ DAIRY', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text('Fresh & Pure Dairy Products', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('TAX INVOICE / BILL (48-Hr Verified)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${DateTime.now().toLocal().toString().split(' ')[0]}', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Divider(color: PdfColors.blue900, thickness: 1.5),
            pw.SizedBox(height: 10),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Customer Details:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text('Name: $customerName', style: pw.TextStyle(fontSize: 10)),
                    pw.Text('Mobile: $customerMobile', style: pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Billing Info:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text(cycle['label'], style: pw.TextStyle(fontSize: 10)),
                    pw.Text('Status: $paymentStatus', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: paymentStatus == 'Paid' ? PdfColors.green : PdfColors.orange)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Text('Included Orders Breakdown:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: <String>['Order ID', 'Date', 'Items Summary', 'Amount (₹)'],
              data: orders.map((order) {
                final items = (order['items'] as List?) ?? [];
                final itemsStr = items.map((i) => '${i['name']} (x${i['qty'] ?? 1})').join(', ');
                return [
                  '#${order['id']}',
                  order['date'] ?? order['createdAt'] ?? '',
                  itemsStr.isNotEmpty ? itemsStr : 'Dairy Items',
                  _parseAmount(order['totalAmount']).toStringAsFixed(2),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 15),

            pw.Text('Delivery Proof Photos:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: orders.map((order) {
                final orderId = order['id'].toString();
                final img = loadedImages[orderId];
                if (img != null) {
                  return pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                    child: pw.Column(
                      children: [
                        pw.Image(img, width: 80, height: 80, fit: pw.BoxFit.cover),
                        pw.SizedBox(height: 2),
                        pw.Text('Order #$orderId', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  );
                }
                return pw.Container();
              }).toList(),
            ),
            pw.SizedBox(height: 20),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Total Combined Bill:', style: pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 4),
                      pw.Text('₹${totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            pw.Divider(color: PdfColors.grey400),
            pw.Center(
              child: pw.Text('Thank you for choosing Viraj Dairy! Generated after 48-hour mandatory window.', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Viraj_Dairy_Bill_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final double cycleAmount = _selectedCycle != null ? _parseAmount(_selectedCycle!['totalAmount']) : 0.0;
    final String paymentStatus = _selectedCycle?['paymentStatus'] ?? 'Pending';
    final bool isPaid = paymentStatus == 'Paid';
    final bool isMatured = _selectedCycle?['isMatured'] ?? false;
    
    // Calculate remaining time for the 48-hr lock
    Duration remainingTime = Duration.zero;
    if (_selectedCycle != null && _selectedCycle!['maturityTime'] != null) {
      final maturity = _selectedCycle!['maturityTime'] as DateTime;
      final now = DateTime.now();
      if (maturity.isAfter(now)) {
        remainingTime = maturity.difference(now);
      }
    }

    final String cycleNote = _selectedCycle != null ? 'BatchBill#${(_selectedCycle!['orderIds'] as List).join("-")}' : 'DairyBill';
    final String upiUri = 'upi://pay?pa=$_adminUpiId&pn=${Uri.encodeComponent(_adminName)}&am=${cycleAmount.toStringAsFixed(2)}&cu=INR&tn=$cycleNote';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('My Bills & Online Payments (48-Hr Lock)', style: TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _customerOrders.isEmpty
              ? const Center(
                  child: Text('No active bills or orders found.', style: TextStyle(color: Colors.grey, fontSize: 14)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. BILLING BATCH DROPDOWN SELECTOR
                      const Text('Select Order Bill Batch (Strict 48-Hour Lock Rule):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedCycle?['cycleId'],
                            items: _billingCycles.map((cycle) {
                              final bool matured = cycle['isMatured'] ?? false;
                              return DropdownMenuItem<String>(
                                value: cycle['cycleId'],
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(cycle['label'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text(matured ? 'Status: Unlocked (48h Passed)' : 'Status: Locked (< 48h)', style: TextStyle(fontSize: 10, color: matured ? Colors.green : Colors.orange)),
                                      ],
                                    ),
                                    Text('₹${_parseAmount(cycle['totalAmount']).toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (String? cycleId) {
                              if (cycleId != null) {
                                setState(() {
                                  _selectedCycle = _billingCycles.firstWhere((c) => c['cycleId'] == cycleId);
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. SELECTED BATCH DETAILS
                      if (_selectedCycle != null) ...[
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_selectedCycle!['label'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A))),
                                        const SizedBox(height: 2),
                                        Text(_selectedCycle!['dateRange'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                    Chip(
                                      label: Text(paymentStatus, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                      backgroundColor: isPaid ? Colors.green : Colors.orange,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                
                                const Text('Included Orders & Delivery Proofs:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 8),
                                ...((_selectedCycle!['orders'] as List).map((order) {
                                  final items = (order['items'] as List?) ?? [];
                                  final photoUrl = order['deliveryPhotoUrl'] ?? order['imageUrl'] ?? order['photo'];

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Order #${order['id']} (${order['date'] ?? order['createdAt'] ?? ''})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                            Text('₹${_parseAmount(order['totalAmount']).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        ...items.map((prod) => Padding(
                                              padding: const EdgeInsets.only(left: 8, top: 2),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('• ${prod['name'] ?? 'Item'} (Qty: ${prod['qty'] ?? 1})', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                  Text('₹${prod['price'] ?? 0}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                ],
                                              ),
                                            )),
                                        
                                        if (photoUrl != null && photoUrl.toString().isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          const Row(
                                            children: [
                                              Icon(Icons.image, size: 14, color: Colors.blue),
                                              SizedBox(width: 4),
                                              Text('Delivery Photo:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              photoUrl.toString(),
                                              height: 70,
                                              width: 70,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => const Text('Could not load photo', style: TextStyle(fontSize: 9, color: Colors.red)),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                })),

                                const Divider(height: 20),

                                // 3. CONDITIONAL RENDER: IF 48 HOURS PASSED -> SHOW PDF & TOTAL; ELSE SHOW COUNTDOWN LOCK
                                if (isMatured) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Total Combined Bill:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                          Text('₹${cycleAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A))),
                                        ],
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1E3A8A),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        icon: const Icon(Icons.picture_as_pdf, size: 16),
                                        label: const Text('Download PDF', style: TextStyle(fontSize: 12)),
                                        onPressed: () => _generateAndDownloadPdf(_selectedCycle!),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.amber.shade300),
                                    ),
                                    child: Column(
                                      children: [
                                        const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.lock_clock, color: Colors.orange, size: 20),
                                            SizedBox(width: 6),
                                            Text('Bill Generation Locked (< 48 Hours)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Time remaining until bill unlocks: ${remainingTime.inHours}h ${remainingTime.inMinutes.remainder(60)}m ${remainingTime.inSeconds.remainder(60)}s',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Bills, combined totals, and QR codes become available strictly 48 hours after the start of this cycle.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 4. QR CODE SECTION (Only displayed if 48 hours have passed and unpaid)
                        if (isMatured && !isPaid) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              children: [
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.qr_code_2, size: 24, color: Color(0xFF1E3A8A)),
                                    SizedBox(width: 8),
                                    Text('Scan & Pay Total Bill Online', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Pay to Admin Mobile: 9850921154', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: QrImageView(
                                    data: upiUri,
                                    version: QrVersions.auto,
                                    size: 200.0,
                                    embeddedImage: const AssetImage('assets/logo.jpeg'),
                                    embeddedImageStyle: const QrEmbeddedImageStyle(
                                      size: Size(40, 40),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Scan this QR using Google Pay, PhonePe, Paytm, or any UPI app. Once your payment is completed successfully, the status will update automatically.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isMatured && isPaid) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'This order batch bill is fully Paid!',
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}