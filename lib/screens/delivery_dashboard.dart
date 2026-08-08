// =============================================================================
// DELIVERY DASHBOARD (lib/screens/delivery_dashboard.dart)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';

class DeliveryApp extends StatelessWidget {
  const DeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delivery Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        useMaterial3: true,
      ),
      home: const DeliveryDashboard(
        deliveryPartnerName: 'Demo Delivery Partner',
        deliveryPartnerMobile: '1234567890',
      ),
    );
  }
}

class DeliveryDashboard extends StatefulWidget {
  final String? deliveryPartnerName;
  final String? deliveryPartnerMobile;

  const DeliveryDashboard({
    super.key,
    this.deliveryPartnerName,
    this.deliveryPartnerMobile,
  });

  @override
  State<DeliveryDashboard> createState() => _DeliveryDashboardState();
}

class _DeliveryDashboardState extends State<DeliveryDashboard> with WidgetsBindingObserver {
  final DatabaseService _db = DatabaseService();
  String _activeTab = 'Orders';

  // Dynamic routes list loaded from database/admin configuration
  List<Map<String, String>> _routesAssignment = [];
  String _selectedRoute = '';
  
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  Map<String, dynamic>? _targetOrderForProof;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDeliveryData();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initController(_selectedCameraIndex);
    }
  }

  Future<void> _disposeCamera() async {
    final cameraController = _cameraController;
    if (cameraController != null) {
      _cameraController = null;
      await cameraController.dispose();
    }
    if (mounted) {
      setState(() => _isCameraInitialized = false);
    }
  }

  Future<void> _loadDeliveryData() async {
    setState(() => _loading = true);
    try {
      final orders = await _db.getAllOrders();
      final customers = await _db.getAllCustomers();
      
      // Extract unique routes dynamically from all customers in the database, excluding 'chinchawad' (case-insensitive)
      Set<String> uniqueRoutes = {};
      for (var cust in customers) {
        final routeName = cust['routeName']?.toString();
        if (routeName != null && routeName.isNotEmpty) {
          if (routeName.toLowerCase() != 'chinchawad') {
            uniqueRoutes.add(routeName);
          }
        }
      }

      // Fallback if no routes found in customers
      if (uniqueRoutes.isEmpty) {
        uniqueRoutes = {'General Route'};
      }

      // Build dynamic route assignments list ensuring all routes are included
      List<Map<String, String>> dynamicRoutes = uniqueRoutes.map((route) {
        return {
          'route': route,
          'person': '${widget.deliveryPartnerName ?? "Partner"} ($route)',
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _allOrders = orders;
        _customers = customers;
        _routesAssignment = dynamicRoutes;
        
        // Ensure selected route defaults to the first available route if empty or invalid
        if (_routesAssignment.isNotEmpty && (_selectedRoute.isEmpty || !_routesAssignment.any((r) => r['route'] == _selectedRoute))) {
          _selectedRoute = _routesAssignment.first['route']!;
        }
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _selectedCameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
        await _initController(_selectedCameraIndex);
      }
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  Future<void> _initController(int cameraIndex) async {
    if (_cameras.isEmpty) return;
    
    await _disposeCamera();

    final controller = CameraController(
      _cameras[cameraIndex],
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Controller initialization error: $e');
      if (mounted) {
        setState(() => _isCameraInitialized = false);
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initController(_selectedCameraIndex);
  }

  Future<void> _captureAndSaveProof(Map<String, dynamic> order) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready. Switching to Camera tab...')),
      );
      setState(() {
        _activeTab = 'Camera';
        _targetOrderForProof = order;
      });
      return;
    }

    try {
      final XFile picture = await _cameraController!.takePicture();
      final Uint8List imageBytes = await picture.readAsBytes();

      final String proofUrl = await StorageService.uploadBytesDeliveryProof(
        orderId: order['id'] ?? order['orderId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        imageBytes: imageBytes,
      );

      final String targetOrderId = order['id']?.toString() ?? order['orderId']?.toString() ?? '';
      await _db.updateOrderStatus(
        orderId: targetOrderId,
        status: 'Completed',
        deliveryPhoto: proofUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery proof captured and saved successfully!')),
      );
      
      setState(() {
        _targetOrderForProof = null;
        _activeTab = 'Orders'; 
      });
      
      await _loadDeliveryData();
    } catch (e) {
      debugPrint('Capture proof error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture proof: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final routeOrders = _allOrders.where((o) {
      final cust = _customers.firstWhere(
        (c) => c['mobile'] == o['customerMobile'] || c['name'] == o['customerName'],
        orElse: () => {},
      );
      final assignedRoute = cust['routeName'] ?? (_routesAssignment.isNotEmpty ? _routesAssignment.first['route'] : '');
      return assignedRoute == _selectedRoute;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
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
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade900,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.local_shipping, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Viraj Dairy Delivery', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              Text(widget.deliveryPartnerName ?? 'Delivery Partner', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.exit_to_app, color: Colors.white, size: 22),
                        onPressed: () async {
                          await _db.clearSession();
                          if (!mounted) return;
                          
                          // Force navigation pop or fallback to snackbar if it's the root screen
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            // If it cannot pop, push a replacement or show confirmation dialog/snackbar
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Session cleared. Already at root screen.')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Select Assigned Delivery Route:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _routesAssignment.map((item) {
                        final routeName = item['route']!;
                        final isSelected = _selectedRoute == routeName;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('Route: $routeName'),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedRoute = routeName);
                            },
                            selectedColor: Colors.white,
                            backgroundColor: Colors.orange.shade900,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.orange.shade900 : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Builder(
                  builder: (context) {
                    if (_activeTab == 'Orders') {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Active Route: $_selectedRoute',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Chip(
                                label: Text('${routeOrders.length} Orders', style: const TextStyle(fontSize: 11)),
                                backgroundColor: Colors.orange.shade50,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          routeOrders.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 40),
                                  child: Center(child: Text('No orders assigned to this route.', style: TextStyle(color: Colors.grey))),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: routeOrders.length,
                                  itemBuilder: (context, index) {
                                    final order = routeOrders[index];
                                    final itemsList = (order['items'] as List?) ?? [];
                                    final status = order['status'] ?? 'Pending';
                                    final isCompleted = status == 'Completed' || status == 'Delivered';

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(order['customerName'] ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                                Chip(
                                                  label: Text(status, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                                  backgroundColor: isCompleted ? Colors.green : Colors.orange,
                                                ),
                                              ],
                                            ),
                                            Text('Mobile: ${order['customerMobile']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                            Text('Address: ${order['address'] ?? "N/A"}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                            const Divider(height: 16),
                                            ...itemsList.map((prod) => Text('• ${prod['name'] ?? 'Milk'} (Qty: ${prod['qty'] ?? prod['quantity'] ?? 1})', style: const TextStyle(fontSize: 12))),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: () {
                                                    setState(() {
                                                      _targetOrderForProof = order;
                                                      _activeTab = 'Camera';
                                                    });
                                                  },
                                                  icon: const Icon(Icons.camera_alt, size: 14),
                                                  label: Text(isCompleted ? 'Retake Proof' : 'Capture & Complete', style: const TextStyle(fontSize: 11)),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: isCompleted ? Colors.green : Colors.orange.shade800,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ],
                      );
                    } else if (_activeTab == 'Camera') {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _targetOrderForProof != null
                                    ? 'Proof for: ${_targetOrderForProof!['customerName']}'
                                    : 'Live Camera Proof',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                              ),
                              if (_cameras.length > 1)
                                IconButton(onPressed: _switchCamera, icon: const Icon(Icons.cameraswitch, color: Colors.orange)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 380,
                            width: double.infinity,
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                            child: _isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: CameraPreview(_cameraController!),
                                  )
                                : const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(color: Colors.orange),
                                        SizedBox(height: 10),
                                        Text('Initializing Camera...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (_targetOrderForProof != null) {
                                _captureAndSaveProof(_targetOrderForProof!);
                              } else if (routeOrders.isNotEmpty) {
                                _captureAndSaveProof(routeOrders.first);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('No active orders available to attach photo proof.')),
                                );
                              }
                            },
                            icon: const Icon(Icons.camera),
                            label: Text(_targetOrderForProof != null
                                ? 'Capture Proof for ${_targetOrderForProof!['customerName']}'
                                : 'Capture & Complete Order'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Delivery Partner Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              children: [
                                const CircleAvatar(radius: 35, backgroundColor: Colors.orange, child: Icon(Icons.person, size: 40, color: Colors.white)),
                                const SizedBox(height: 12),
                                Text(widget.deliveryPartnerName ?? 'Delivery Partner', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('Active Route: $_selectedRoute', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.orange.shade800,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFooterItem('Orders', Icons.list_alt),
                  _buildFooterItem('Camera', Icons.camera_alt),
                  _buildFooterItem('Profile', Icons.person),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterItem(String tabKey, IconData icon) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? Colors.white : Colors.white70, size: 22),
          Text(tabKey, style: TextStyle(fontSize: 10, color: isActive ? Colors.white : Colors.white70)),
        ],
      ),
    );
  }
}