// =============================================================================
// DELIVERY DASHBOARD - FULL UPDATED VERSION
// File: lib/screens/delivery_dashboard.dart
//
// UPDATED (this revision):
// - Per-product status is now a proper 3-way control: Pending / Completed /
//   Removed. Only ONE of the three can ever be active for a product at a
//   time (this fixes the earlier bug where tapping "Completed" left the
//   product still looking like it was in two states / "both remaining").
// - "Removed" replaces the old "Not Available" toggle — same effect
//   (excluded from BillingService.orderTotal()), clearer label.
// - The collapsed order header (the banner you see before expanding a
//   card) now shows live counts for all three states — done / pending /
//   removed — so a manual cancel/removal done by the delivery partner is
//   immediately visible from OUTSIDE the card, without needing to expand
//   it.
// - The photo-capture control is still exactly ONE icon per order (never
//   per product), unchanged from before. If every product in an order is
//   marked Removed, the capture button is replaced with a Cancel Order
//   button.
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:upgrader/upgrader.dart';

import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../services/billing_service.dart';

// IMPORTANT:
// Change this import if your LoginScreen file has another location/name.
import 'login_screen.dart';

// =============================================================================
// MAIN
// =============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeliveryApp());
}

// =============================================================================
// DELIVERY APP
// =============================================================================

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
      home: UpgradeAlert(
        upgrader: Upgrader(
          durationUntilAlertAgain: const Duration(days: 1),
        ),
        child: const DeliveryDashboard(
          deliveryPartnerName: 'Demo Delivery Partner',
          deliveryPartnerMobile: '1234567890',
          deliveryPartnerRoute: 'Route1',
        ),
      ),
    );
  }
}

// =============================================================================
// DELIVERY DASHBOARD
// =============================================================================

class DeliveryDashboard extends StatefulWidget {
  final String? deliveryPartnerName;
  final String? deliveryPartnerMobile;
  final String? deliveryPartnerRoute;

  const DeliveryDashboard({
    super.key,
    this.deliveryPartnerName,
    this.deliveryPartnerMobile,
    this.deliveryPartnerRoute,
  });

  @override
  State<DeliveryDashboard> createState() => _DeliveryDashboardState();
}

// =============================================================================
// ITEM STATUS HELPERS
//
// A single, canonical place that decides what counts as "delivered" /
// "cancelled" / "pending" for a product line-item, so the collapsed
// header, the expanded row, and the billing check can never disagree
// with each other (that mismatch was the root of the old bug).
// =============================================================================

class _ItemStatus {
  static const String pending = 'pending';
  static const String delivered = 'delivered';
  static const String cancelled = 'cancelled';

  static String normalize(Map<String, dynamic> item) {
    final raw = (item['itemStatus']?.toString() ?? '').toLowerCase().trim();
    if (raw == 'delivered' || raw == 'completed' || raw == 'complete') {
      return delivered;
    }
    if (raw == 'cancelled' ||
        raw == 'canceled' ||
        raw == 'not_available' ||
        raw == 'not available' ||
        raw == 'removed') {
      return cancelled;
    }
    return pending;
  }

  static bool isDelivered(Map<String, dynamic> item) => normalize(item) == delivered;
  static bool isCancelled(Map<String, dynamic> item) => normalize(item) == cancelled;
  static bool isPending(Map<String, dynamic> item) => normalize(item) == pending;
}

// =============================================================================
// STATE
// =============================================================================

class _DeliveryDashboardState extends State<DeliveryDashboard>
    with WidgetsBindingObserver {
  final DatabaseService _db = DatabaseService();

  String _activeTab = 'Orders';

  late final String _assignedRoute;

  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _customers = [];

  bool _loading = true;
  bool _isCapturing = false;
  bool _isGoingToLogin = false;

  // Tracks which order id / item index is currently being updated so we can
  // show a small inline spinner on just that row instead of blocking the
  // whole screen.
  String? _itemBusyOrderId;
  int? _itemBusyIndex;

  // Tracks which order ids are currently expanded (dropdown open). Orders
  // are collapsed by default — an id is added here only once the user taps
  // to open it.
  final Set<String> _expandedOrderIds = {};

  // Which status filter chip is active on the Orders tab: 'All', 'Pending',
  // 'Completed', or 'Removed'. Filters which customers/orders are shown.
  String _selectedStatusFilter = 'All';

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  String? _cameraError;
  Map<String, dynamic>? _targetOrderForProof;

  // =============================================================================
  // INIT
  // =============================================================================

  @override
  void initState() {
    super.initState();

    _assignedRoute = (widget.deliveryPartnerRoute ?? '').trim();

    WidgetsBinding.instance.addObserver(this);

    _loadDeliveryData();
    _initCamera();
  }

  // =============================================================================
  // DISPOSE
  // =============================================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  // =============================================================================
  // APP LIFECYCLE
  // =============================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _disposeCamera();
    }

    if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty) {
        _initController(_selectedCameraIndex);
      } else {
        _initCamera();
      }
    }
  }

  // =============================================================================
  // CAMERA DISPOSE
  // =============================================================================

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;

    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
    }

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('Camera dispose error: $e');
      }
    }
  }

  // =============================================================================
  // LOAD DELIVERY DATA
  // =============================================================================

  Future<void> _loadDeliveryData() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final orders = await _db.getAllOrders();
      final customers = await _db.getAllCustomers();

      if (!mounted) return;

      setState(() {
        _allOrders = orders;
        _customers = customers;
      });
    } catch (e) {
      debugPrint('Error loading delivery data: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load delivery data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // =============================================================================
  // INITIALIZE CAMERA
  // =============================================================================

  Future<void> _initCamera() async {
    try {
      if (mounted) {
        setState(() {
          _cameraError = null;
        });
      }

      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No camera found on this device.';
            _isCameraInitialized = false;
          });
        }
        return;
      }

      final backCameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );

      _selectedCameraIndex = backCameraIndex == -1 ? 0 : backCameraIndex;

      await _initController(_selectedCameraIndex);
    } catch (e) {
      debugPrint('Camera discovery error: $e');

      if (mounted) {
        setState(() {
          _cameraError = 'Failed to find cameras.\n$e';
          _isCameraInitialized = false;
        });
      }
    }
  }

  // =============================================================================
  // INITIALIZE CAMERA CONTROLLER
  // =============================================================================

  Future<void> _initController(int cameraIndex) async {
    if (_cameras.isEmpty) return;

    if (cameraIndex < 0 || cameraIndex >= _cameras.length) {
      cameraIndex = 0;
    }

    _selectedCameraIndex = cameraIndex;

    await _disposeCamera();

    final controller = CameraController(
      _cameras[_selectedCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController = controller;

    try {
      await controller.initialize();

      if (!mounted) return;

      if (_cameraController != controller) {
        await controller.dispose();
        return;
      }

      setState(() {
        _isCameraInitialized = true;
        _cameraError = null;
      });
    } catch (e) {
      debugPrint('Camera controller initialization error: $e');

      if (_cameraController == controller) {
        _cameraController = null;
      }

      try {
        await controller.dispose();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _cameraError = 'Camera initialization failed.\n$e';
        });
      }
    }
  }

  // =============================================================================
  // SWITCH CAMERA
  // =============================================================================

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initController(nextIndex);
  }

  // =============================================================================
  // RETRY CAMERA
  // =============================================================================

  Future<void> _retryCamera() async {
    if (!mounted) return;

    setState(() {
      _cameraError = null;
      _isCameraInitialized = false;
    });

    await _initCamera();
  }

  // =============================================================================
  // PER-PRODUCT STATUS (Pending / Completed / Removed)
  //
  // Tapping a status that is already active is a no-op — this is what
  // keeps the UI from ever looking like two states are true at once.
  // =============================================================================

  Future<void> _setItemStatus(
    Map<String, dynamic> order,
    int itemIndex,
    String status, // _ItemStatus.pending | .delivered | .cancelled
  ) async {
    final orderId = order['id']?.toString() ?? '';
    if (orderId.isEmpty) return;

    final itemsList = List<Map<String, dynamic>>.from(
      ((order['items'] as List?) ?? []).map(
        (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
      ),
    );
    if (itemIndex < 0 || itemIndex >= itemsList.length) return;

    // Already in that state — nothing to do.
    if (_ItemStatus.normalize(itemsList[itemIndex]) == status) return;

    setState(() {
      _itemBusyOrderId = orderId;
      _itemBusyIndex = itemIndex;
    });

    try {
      await _db.updateOrderItemStatus(
        orderId: orderId,
        itemIndex: itemIndex,
        status: status,
      );
      await _loadDeliveryData();
    } catch (e) {
      debugPrint('Item status update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update product: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _itemBusyOrderId = null;
          _itemBusyIndex = null;
        });
      }
    }
  }

  // =============================================================================
  // CANCEL AN ENTIRE ORDER
  // =============================================================================

  Future<void> _cancelWholeOrder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? '';
    if (orderId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'None of the products in this order are available. This order will '
          'be marked Cancelled and will NOT be added to the customer\'s bill.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Order', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.cancelEntireOrder(orderId: orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order cancelled — not added to billing.')),
      );
      await _loadDeliveryData();
    } catch (e) {
      debugPrint('Cancel order error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel order: $e')),
        );
      }
    }
  }

  // =============================================================================
  // CAPTURE AND SAVE DELIVERY PROOF
  // =============================================================================

  Future<void> _captureAndSaveProof(Map<String, dynamic> order) async {
    if (_isCapturing) return;

    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera is not ready. Please wait or retry the camera.'),
          ),
        );

        setState(() {
          _activeTab = 'Camera';
          _targetOrderForProof = order;
        });
      }
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile picture = await controller.takePicture();
      final Uint8List originalBytes = await picture.readAsBytes();

      Uint8List imageBytes = originalBytes;

      try {
        final compressed = await FlutterImageCompress.compressWithList(
          originalBytes,
          minWidth: 600,
          minHeight: 600,
          quality: 50,
        );

        if (compressed.isNotEmpty) {
          imageBytes = compressed;
        }
      } catch (compressError) {
        debugPrint('Image compression failed: $compressError');
      }

      final String targetOrderId = order['id']?.toString() ??
          order['orderId']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();

      final String proofUrl = await StorageService.uploadBytesDeliveryProof(
        orderId: targetOrderId,
        imageBytes: imageBytes,
      );

      await _db.updateOrderStatus(
        orderId: targetOrderId,
        status: 'Completed',
        deliveryPhoto: proofUrl,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery proof captured and saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _targetOrderForProof = null;
        _activeTab = 'Orders';
      });

      await _loadDeliveryData();
    } catch (e) {
      debugPrint('Capture delivery proof error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture proof: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  // =============================================================================
  // GO DIRECTLY TO LOGIN
  // =============================================================================

  Future<void> _goToLogin() async {
    if (_isGoingToLogin) return;

    _isGoingToLogin = true;

    debugPrint('Going directly to LoginScreen...');

    try {
      await _db.clearSession();
    } catch (e) {
      debugPrint('Clear session error: $e');
    }

    try {
      await _disposeCamera();
    } catch (e) {
      debugPrint('Camera stop error: $e');
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  // =============================================================================
  // GET ROUTE ORDERS
  // =============================================================================

  List<Map<String, dynamic>> _getRouteOrders() {
    final hasRoute = _assignedRoute.isNotEmpty;

    if (!hasRoute) return [];

    return _allOrders.where((order) {
      // Already-cancelled orders have nothing left to do here.
      if ((order['status']?.toString() ?? '') == 'Cancelled') return false;

      final customer = _customers.firstWhere(
        (customer) =>
            customer['mobile'] == order['customerMobile'] ||
            customer['name'] == order['customerName'],
        orElse: () => {},
      );

      final customerRoute = customer['routeName'];

      return customerRoute == _assignedRoute;
    }).toList();
  }

  // =============================================================================
  // GROUP ROUTE ORDERS BY CUSTOMER
  // =============================================================================

  Map<String, List<Map<String, dynamic>>> _groupByCustomer(
    List<Map<String, dynamic>> orders,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final order in orders) {
      final key = order['customerMobile']?.toString() ??
          order['customerName']?.toString() ??
          'unknown';
      grouped.putIfAbsent(key, () => []).add(order);
    }
    return grouped;
  }

  // =============================================================================
  // DERIVE AN ORDER'S OVERALL STATUS — used by the filter chips.
  // Prefers a backend status ('Completed'/'Cancelled') when present,
  // otherwise derives it from the products inside the order.
  // =============================================================================

  String _deriveOrderStatus(Map<String, dynamic> order) {
    final backendStatus = (order['status']?.toString() ?? '').trim();
    if (backendStatus == 'Completed' || backendStatus == 'Delivered') return 'Completed';
    if (backendStatus == 'Cancelled') return 'Removed';

    final itemsList = List<Map<String, dynamic>>.from(
      ((order['items'] as List?) ?? []).map(
        (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
      ),
    );
    if (itemsList.isEmpty) return 'Pending';

    if (itemsList.every(_ItemStatus.isCancelled)) return 'Removed';

    final allResolved = itemsList.every(
      (i) => _ItemStatus.isDelivered(i) || _ItemStatus.isCancelled(i),
    );
    if (allResolved && itemsList.any(_ItemStatus.isDelivered)) return 'Completed';

    return 'Pending';
  }

  // =============================================================================
  // TOGGLE ORDER DROPDOWN
  // =============================================================================

  void _toggleOrderExpanded(String orderId) {
    setState(() {
      if (_expandedOrderIds.contains(orderId)) {
        _expandedOrderIds.remove(orderId);
      } else {
        _expandedOrderIds.add(orderId);
      }
    });
  }

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.orange),
        ),
      );
    }

    final bool hasRoute = _assignedRoute.isNotEmpty;
    final routeOrders = _getRouteOrders();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goToLogin();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // =================================================================
              // HEADER
              // =================================================================
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
                      children: [
                        Expanded(
                          child: Row(
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
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Viraj Dairy Delivery',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      widget.deliveryPartnerName ?? 'Delivery Partner',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.shade800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            tooltip: 'Back to Login',
                            onPressed: _isGoingToLogin ? null : _goToLogin,
                            icon: _isGoingToLogin
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          hasRoute ? Icons.alt_route : Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade900,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              hasRoute
                                  ? 'Assigned Route: $_assignedRoute'
                                  : 'No route assigned — contact admin',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // =================================================================
              // CONTENT
              // =================================================================
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildActiveContent(hasRoute, routeOrders),
                ),
              ),

              // =================================================================
              // FOOTER
              // =================================================================
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
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
      ),
    );
  }

  // =============================================================================
  // ACTIVE CONTENT
  // =============================================================================

  Widget _buildActiveContent(bool hasRoute, List<Map<String, dynamic>> routeOrders) {
    if (_activeTab == 'Orders') {
      return _buildOrdersTab(hasRoute, routeOrders);
    }
    if (_activeTab == 'Camera') {
      return _buildCameraTab(routeOrders);
    }
    return _buildProfileTab(hasRoute);
  }

  // =============================================================================
  // ORDERS TAB — grouped: Route -> Customer -> Orders (dropdown) -> Products
  // =============================================================================

  Widget _buildOrdersTab(bool hasRoute, List<Map<String, dynamic>> routeOrders) {
    if (!hasRoute) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            'You have not been assigned a route yet.\n'
            'Ask your admin to assign one from the Admin Dashboard.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    if (routeOrders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
          child: Text('No orders assigned to this route.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    // ---- Apply the active status filter (All / Pending / Completed /
    // Removed) before grouping by customer, so filtered-out orders never
    // reach the customer cards. ----
    final filteredOrders = _selectedStatusFilter == 'All'
        ? routeOrders
        : routeOrders.where((o) => _deriveOrderStatus(o) == _selectedStatusFilter).toList();

    final grouped = _groupByCustomer(filteredOrders);
    final customerKeys = grouped.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Your Route: $_assignedRoute',
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
        _buildStatusFilterRow(),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.touch_app_rounded, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 5),
            Text(
              'Tap an order to expand it',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (customerKeys.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                _selectedStatusFilter == 'All'
                    ? 'No orders to show.'
                    : 'No $_selectedStatusFilter orders on this route.',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),
        for (final customerKey in customerKeys) ...[
          _buildCustomerGroupHeader(grouped[customerKey]!.first),
          const SizedBox(height: 8),
          // ---------------------------------------------------------------
          // Multiple orders for the same customer are numbered ("Order N
          // of M") and given extra spacing so they read as clearly
          // separate cards instead of blending together.
          // ---------------------------------------------------------------
          for (int i = 0; i < grouped[customerKey]!.length; i++) ...[
            _buildOrderCard(
              grouped[customerKey]![i],
              orderIndex: i + 1,
              orderCountForCustomer: grouped[customerKey]!.length,
            ),
            if (i < grouped[customerKey]!.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 22),
        ],
      ],
    );
  }

  // -----------------------------------------------------------------------
  // STATUS FILTER ROW — All / Pending / Completed / Removed. Filters which
  // customers and orders appear below, based on each order's overall
  // status (see _deriveOrderStatus).
  // -----------------------------------------------------------------------
  Widget _buildStatusFilterRow() {
    const filters = ['All', 'Pending', 'Completed', 'Removed'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in filters) ...[
            _buildFilterChip(f),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Color _colorForFilter(String label) {
    switch (label) {
      case 'Pending':
        return Colors.orange.shade700;
      case 'Completed':
        return Colors.green.shade700;
      case 'Removed':
        return Colors.red.shade700;
      default:
        return const Color(0xFF1E3A8A);
    }
  }

  Widget _buildFilterChip(String label) {
    final selected = _selectedStatusFilter == label;
    final color = _colorForFilter(label);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedStatusFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerGroupHeader(Map<String, dynamic> sampleOrder) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle, size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              sampleOrder['customerName'] ?? 'Customer',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF7C2D12)),
            ),
          ),
          Text(
            sampleOrder['customerMobile'] ?? '',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // ORDER CARD (DROPDOWN) — collapsed header with order #, status, item
  // count and address preview. Tapping expands to reveal the product list
  // (Pending / Completed / Removed buttons) and the capture/cancel action.
  //
  // The collapsed header now shows a done / pending / removed count so a
  // manual removal is visible immediately, without opening the card.
  //
  // orderIndex / orderCountForCustomer: when a customer has more than one
  // order on this route, an "Order N of M" label is shown at the top of
  // the card so the separate orders are unmistakable.
  // =============================================================================

  Widget _buildOrderCard(
    Map<String, dynamic> order, {
    int orderIndex = 1,
    int orderCountForCustomer = 1,
  }) {
    final orderId = order['id']?.toString() ?? '';

    final itemsList = List<Map<String, dynamic>>.from(
      ((order['items'] as List?) ?? []).map(
        (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
      ),
    );

    final status = order['status'] ?? 'Pending';
    final isCompleted = status == 'Completed' || status == 'Delivered';
    final canEditItems = !isCompleted;

    final allCancelled =
        itemsList.isNotEmpty && itemsList.every((i) => _ItemStatus.isCancelled(i));

    final bool showOrderCount = orderCountForCustomer > 1;
    final bool isExpanded = _expandedOrderIds.contains(orderId);

    // ---- Live per-order counts, always derived the same way as the rows
    // below so the banner and the expanded list can never disagree. ----
    final int deliveredCount = itemsList.where(_ItemStatus.isDelivered).length;
    final int cancelledCount = itemsList.where(_ItemStatus.isCancelled).length;
    final int pendingCount = itemsList.where(_ItemStatus.isPending).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: showOrderCount
            ? BorderSide(color: Colors.orange.shade100, width: 1)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -----------------------------------------------------------------
          // DROPDOWN HEADER — always visible, tap to expand/collapse.
          // -----------------------------------------------------------------
          InkWell(
            onTap: () => _toggleOrderExpanded(orderId),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showOrderCount) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Order $orderIndex of $orderCountForCustomer',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order #$orderId',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Chip(
                        label: Text(status, style: const TextStyle(fontSize: 10, color: Colors.white)),
                        backgroundColor: isCompleted ? Colors.green : Colors.orange,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey.shade600,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    order['address'] ?? "N/A",
                    maxLines: isExpanded ? null : 1,
                    overflow: isExpanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  // ---- Live status counts — this is the "outside the
                  // card" view. A manual Removed tap inside the card
                  // shows up here right away. ----
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _buildMiniStat(Icons.shopping_bag_outlined, '${itemsList.length} items', Colors.grey.shade700),
                      if (deliveredCount > 0)
                        _buildMiniStat(Icons.check_circle_outline, '$deliveredCount completed', Colors.green.shade700),
                      if (pendingCount > 0)
                        _buildMiniStat(Icons.schedule_outlined, '$pendingCount pending', Colors.orange.shade700),
                      if (cancelledCount > 0)
                        _buildMiniStat(Icons.remove_circle_outline, '$cancelledCount removed', Colors.red.shade700),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // -----------------------------------------------------------------
          // EXPANDABLE BODY — product list + bottom action.
          // -----------------------------------------------------------------
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 16),

                        // ---------------------------------------------------
                        // PRODUCT LIST
                        // A thin divider is drawn between each product row
                        // (not after the last one) so individual products
                        // are clearly separated from each other. Each row
                        // has its OWN Pending / Completed / Removed
                        // control — never a camera button.
                        // ---------------------------------------------------
                        ...List.generate(
                          itemsList.length * 2 - (itemsList.isEmpty ? 0 : 1),
                          (position) {
                            final isDividerSlot = position.isOdd;

                            if (isDividerSlot) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                              );
                            }

                            final index = position ~/ 2;
                            final item = itemsList[index];
                            final itemStatus = _ItemStatus.normalize(item);
                            final isCancelled = itemStatus == _ItemStatus.cancelled;
                            final isDelivered = itemStatus == _ItemStatus.delivered;
                            final isPending = itemStatus == _ItemStatus.pending;
                            final isBusyRow = _itemBusyOrderId == orderId && _itemBusyIndex == index;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isCancelled
                                    ? Colors.red.shade50
                                    : isDelivered
                                        ? Colors.green.shade50
                                        : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCancelled
                                      ? Colors.red.shade100
                                      : isDelivered
                                          ? Colors.green.shade100
                                          : Colors.grey.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${item['name'] ?? 'Product'} (Qty: ${item['qty'] ?? item['quantity'] ?? 1})',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            decoration: isCancelled ? TextDecoration.lineThrough : null,
                                            color: isCancelled ? Colors.red.shade700 : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      if (isBusyRow)
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      else if (!canEditItems)
                                        Text(
                                          isCancelled
                                              ? 'Removed'
                                              : (isDelivered ? 'Completed' : 'Pending'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isCancelled
                                                ? Colors.red
                                                : (isDelivered ? Colors.green : Colors.orange),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (canEditItems && !isBusyRow) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        // "Pending" only shows while the
                                        // product IS pending. Once it's
                                        // marked Completed or Removed, this
                                        // chip disappears — you can still
                                        // switch between Completed and
                                        // Removed, but not go back to
                                        // Pending.
                                        if (isPending) ...[
                                          Expanded(
                                            child: _buildStatusChip(
                                              label: 'Pending',
                                              icon: Icons.schedule_rounded,
                                              color: Colors.orange,
                                              selected: isPending,
                                              onTap: () =>
                                                  _setItemStatus(order, index, _ItemStatus.pending),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Expanded(
                                          child: _buildStatusChip(
                                            label: 'Completed',
                                            icon: Icons.check_circle_rounded,
                                            color: Colors.green,
                                            selected: isDelivered,
                                            onTap: () =>
                                                _setItemStatus(order, index, _ItemStatus.delivered),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: _buildStatusChip(
                                            label: 'Removed',
                                            icon: Icons.remove_circle_rounded,
                                            color: Colors.red,
                                            selected: isCancelled,
                                            onTap: () =>
                                                _setItemStatus(order, index, _ItemStatus.cancelled),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 12),

                        // ---------------------------------------------------
                        // BOTTOM ACTION: single photo capture icon per
                        // order (never per product), OR Cancel Order if
                        // every product is Removed.
                        // ---------------------------------------------------
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!isCompleted && allCancelled)
                              ElevatedButton.icon(
                                onPressed: () => _cancelWholeOrder(order),
                                icon: const Icon(Icons.cancel_outlined, size: 14),
                                label: const Text('Cancel Order', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: _isCapturing
                                    ? null
                                    : () {
                                        setState(() {
                                          _targetOrderForProof = order;
                                          _activeTab = 'Camera';
                                        });
                                      },
                                icon: const Icon(Icons.camera_alt, size: 14),
                                label: Text(
                                  isCompleted ? 'Retake Proof' : 'Capture & Complete',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isCompleted ? Colors.green : Colors.orange.shade800,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // A single Pending / Completed / Removed chip. `selected` is computed
  // from the SAME normalized status as everything else, so exactly one
  // chip in a row of three can ever be highlighted.
  // -----------------------------------------------------------------------
  Widget _buildStatusChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================================
  // CAMERA TAB
  // =============================================================================

  Widget _buildCameraTab(List<Map<String, dynamic>> routeOrders) {
    final controller = _cameraController;

    final cameraReady =
        _isCameraInitialized && controller != null && controller.value.isInitialized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _targetOrderForProof != null
                    ? 'Proof for: ${_targetOrderForProof!['customerName'] ?? 'Customer'}'
                    : 'Live Camera Proof',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
              ),
            ),
            if (_cameras.length > 1)
              IconButton(
                onPressed: _switchCamera,
                tooltip: 'Switch Camera',
                icon: const Icon(Icons.cameraswitch, color: Colors.orange),
              ),
          ],
        ),

        const SizedBox(height: 12),

        Container(
          height: 380,
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: cameraReady ? _buildCameraPreview(controller) : _buildCameraLoading(),
          ),
        ),

        const SizedBox(height: 16),

        ElevatedButton.icon(
          onPressed: _isCapturing
              ? null
              : () {
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
          icon: _isCapturing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.camera),
          label: Text(
            _isCapturing
                ? 'Processing Proof...'
                : _targetOrderForProof != null
                    ? 'Capture Proof for ${_targetOrderForProof!['customerName'] ?? 'Customer'}'
                    : 'Capture & Complete Order',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        const SizedBox(height: 10),

        if (!cameraReady && _cameraError != null)
          OutlinedButton.icon(
            onPressed: _retryCamera,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Camera'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
          ),
      ],
    );
  }

  // =============================================================================
  // CAMERA PREVIEW
  // =============================================================================

  Widget _buildCameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return CameraPreview(controller);
    }

    final aspectRatio = previewSize.width / previewSize.height;

    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }

  // =============================================================================
  // CAMERA LOADING
  // =============================================================================

  Widget _buildCameraLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_cameraError != null) ...[
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retryCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Camera'),
              ),
            ] else ...[
              const CircularProgressIndicator(color: Colors.orange),
              const SizedBox(height: 12),
              const Text('Initializing Camera...', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  // =============================================================================
  // PROFILE TAB — redesigned, more attractive, with an interactive hero
  // card that shifts toward the pointer/finger when it gets near.
  // =============================================================================

  Widget _buildProfileTab(bool hasRoute) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          _InteractiveProfileHeroCard(
            name: widget.deliveryPartnerName ?? 'Delivery Partner',
            mobile: widget.deliveryPartnerMobile,
            hasRoute: hasRoute,
            route: _assignedRoute,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildProfileStatCard(
                  icon: Icons.list_alt_rounded,
                  label: 'Orders on Route',
                  value: '${_getRouteOrders().length}',
                  color: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildProfileStatCard(
                  icon: Icons.alt_route_rounded,
                  label: 'Route',
                  value: hasRoute ? _assignedRoute : '—',
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.045), blurRadius: 12, offset: const Offset(0, 5)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.info_outline_rounded, color: Colors.orange.shade700, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delivery Partner Account',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Your profile is linked to your assigned route. Contact admin to change your route or details.',
                        style: TextStyle(fontSize: 11.5, height: 1.4, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildProfileStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // FOOTER
  // =============================================================================

  Widget _buildFooterItem(String tabKey, IconData icon) {
    final isActive = _activeTab == tabKey;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _activeTab = tabKey;
          });

          if (tabKey == 'Camera' && !_isCameraInitialized) {
            if (_cameras.isEmpty) {
              _initCamera();
            } else {
              _initController(_selectedCameraIndex);
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : Colors.white70,
                size: 22,
              ),
              const SizedBox(height: 3),
              Text(
                tabKey,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? Colors.white : Colors.white70,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE PROFILE HERO CARD
//
// A gradient hero card for the Profile tab that gently shifts and tilts
// toward the pointer as it gets near (desktop/web, via MouseRegion.onHover)
// and toward the touch point while dragging on it (mobile, via
// onPanUpdate). It eases back to center when the pointer leaves / the
// drag ends.
// =============================================================================

class _InteractiveProfileHeroCard extends StatefulWidget {
  final String name;
  final String? mobile;
  final bool hasRoute;
  final String route;

  const _InteractiveProfileHeroCard({
    required this.name,
    required this.mobile,
    required this.hasRoute,
    required this.route,
  });

  @override
  State<_InteractiveProfileHeroCard> createState() => _InteractiveProfileHeroCardState();
}

class _InteractiveProfileHeroCardState extends State<_InteractiveProfileHeroCard>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;

  static const double _maxShift = 10.0;

  void _updateFromLocalPosition(Offset localPosition, Size size) {
    final dx = (localPosition.dx / size.width - 0.5) * 2; // -1..1
    final dy = (localPosition.dy / size.height - 0.5) * 2; // -1..1

    setState(() {
      _dragOffset = Offset(
        dx.clamp(-1.0, 1.0) * _maxShift,
        dy.clamp(-1.0, 1.0) * _maxShift,
      );
    });
  }

  void _reset() {
    setState(() {
      _dragOffset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 190);

        return MouseRegion(
          onHover: (event) => _updateFromLocalPosition(event.localPosition, size),
          onExit: (_) => _reset(),
          child: GestureDetector(
            onPanUpdate: (details) => _updateFromLocalPosition(details.localPosition, size),
            onPanEnd: (_) => _reset(),
            onPanCancel: _reset,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.identity()
                ..translate(_dragOffset.dx, _dragOffset.dy)
                ..rotateZ(_dragOffset.dx / 600)
                ..rotateX(-_dragOffset.dy / 600),
              transformAlignment: Alignment.center,
              width: double.infinity,
              height: size.height,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFC2410C),
                    Color(0xFFEA580C),
                    Color(0xFFF97316),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEA580C).withOpacity(0.35),
                    blurRadius: 22 + _dragOffset.distance,
                    offset: Offset(_dragOffset.dx * 0.4, 12 + _dragOffset.dy * 0.4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -30,
                    top: -35,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                    ),
                  ),
                  Positioned(
                    left: -20,
                    bottom: -40,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), shape: BoxShape.circle),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
                            ),
                            child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 32),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Delivery Partner',
                                  style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (widget.mobile != null && widget.mobile!.isNotEmpty) ...[
                            Icon(Icons.phone_rounded, size: 13, color: Colors.white.withOpacity(0.85)),
                            const SizedBox(width: 5),
                            Text(
                              widget.mobile!,
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 14),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.hasRoute ? widget.route : 'No route',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}