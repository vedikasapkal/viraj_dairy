// =============================================================================
// DELIVERY DASHBOARD - FULL UPDATED VERSION
// File: lib/screens/delivery_dashboard.dart
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:upgrader/upgrader.dart';

import '../services/database_service.dart';
import '../services/storage_service.dart';

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

      // -----------------------------------------------------------------------
      // NO /login ROUTE IS REQUIRED NOW.
      //
      // We navigate directly using MaterialPageRoute to LoginScreen.
      // -----------------------------------------------------------------------

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
  State<DeliveryDashboard> createState() =>
      _DeliveryDashboardState();
}

// =============================================================================
// STATE
// =============================================================================

class _DeliveryDashboardState extends State<DeliveryDashboard>
    with WidgetsBindingObserver {
  final DatabaseService _db = DatabaseService();

  // ---------------------------------------------------------------------------
  // ACTIVE TAB
  // ---------------------------------------------------------------------------

  String _activeTab = 'Orders';

  // ---------------------------------------------------------------------------
  // ROUTE
  // ---------------------------------------------------------------------------

  late final String _assignedRoute;

  // ---------------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _customers = [];

  bool _loading = true;
  bool _isCapturing = false;

  // This prevents multiple navigation calls.
  bool _isGoingToLogin = false;

  // ---------------------------------------------------------------------------
  // CAMERA
  // ---------------------------------------------------------------------------

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

    _assignedRoute =
        (widget.deliveryPartnerRoute ?? '').trim();

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
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    final controller = _cameraController;

    if (controller == null) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
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
        debugPrint(
          'Camera dispose error: $e',
        );
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
      final orders =
          await _db.getAllOrders();

      final customers =
          await _db.getAllCustomers();

      if (!mounted) {
        return;
      }

      setState(() {
        _allOrders = orders;
        _customers = customers;
      });
    } catch (e) {
      debugPrint(
        'Error loading delivery data: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load delivery data: $e',
            ),
          ),
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

      _cameras =
          await availableCameras();

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError =
                'No camera found on this device.';
            _isCameraInitialized = false;
          });
        }

        return;
      }

      final backCameraIndex =
          _cameras.indexWhere(
        (camera) =>
            camera.lensDirection ==
            CameraLensDirection.back,
      );

      _selectedCameraIndex =
          backCameraIndex == -1
              ? 0
              : backCameraIndex;

      await _initController(
        _selectedCameraIndex,
      );
    } catch (e) {
      debugPrint(
        'Camera discovery error: $e',
      );

      if (mounted) {
        setState(() {
          _cameraError =
              'Failed to find cameras.\n$e';

          _isCameraInitialized = false;
        });
      }
    }
  }

  // =============================================================================
  // INITIALIZE CAMERA CONTROLLER
  // =============================================================================

  Future<void> _initController(
    int cameraIndex,
  ) async {
    if (_cameras.isEmpty) {
      return;
    }

    if (cameraIndex < 0 ||
        cameraIndex >= _cameras.length) {
      cameraIndex = 0;
    }

    _selectedCameraIndex =
        cameraIndex;

    await _disposeCamera();

    final controller =
        CameraController(
      _cameras[_selectedCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          ImageFormatGroup.jpeg,
    );

    _cameraController =
        controller;

    try {
      await controller.initialize();

      if (!mounted) {
        return;
      }

      if (_cameraController !=
          controller) {
        await controller.dispose();
        return;
      }

      setState(() {
        _isCameraInitialized = true;
        _cameraError = null;
      });
    } catch (e) {
      debugPrint(
        'Camera controller initialization error: $e',
      );

      if (_cameraController ==
          controller) {
        _cameraController = null;
      }

      try {
        await controller.dispose();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _cameraError =
              'Camera initialization failed.\n$e';
        });
      }
    }
  }

  // =============================================================================
  // SWITCH CAMERA
  // =============================================================================

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) {
      return;
    }

    final nextIndex =
        (_selectedCameraIndex + 1) %
            _cameras.length;

    await _initController(
      nextIndex,
    );
  }

  // =============================================================================
  // RETRY CAMERA
  // =============================================================================

  Future<void> _retryCamera() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _cameraError = null;
      _isCameraInitialized = false;
    });

    await _initCamera();
  }

  // =============================================================================
  // CAPTURE AND SAVE DELIVERY PROOF
  // =============================================================================

  Future<void> _captureAndSaveProof(
    Map<String, dynamic> order,
  ) async {
    if (_isCapturing) {
      return;
    }

    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera is not ready. Please wait or retry the camera.',
            ),
          ),
        );

        setState(() {
          _activeTab = 'Camera';
          _targetOrderForProof =
              order;
        });
      }

      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      // -----------------------------------------------------------------------
      // TAKE PHOTO
      // -----------------------------------------------------------------------

      final XFile picture =
          await controller.takePicture();

      final Uint8List originalBytes =
          await picture.readAsBytes();

      // -----------------------------------------------------------------------
      // COMPRESS PHOTO
      // -----------------------------------------------------------------------

      Uint8List imageBytes =
          originalBytes;

      try {
        final compressed =
            await FlutterImageCompress
                .compressWithList(
          originalBytes,
          minWidth: 600,
          minHeight: 600,
          quality: 50,
        );

        if (compressed.isNotEmpty) {
          imageBytes = compressed;
        }
      } catch (compressError) {
        debugPrint(
          'Image compression failed: $compressError',
        );
      }

      // -----------------------------------------------------------------------
      // ORDER ID
      // -----------------------------------------------------------------------

      final String targetOrderId =
          order['id']?.toString() ??
              order['orderId']?.toString() ??
              DateTime.now()
                  .millisecondsSinceEpoch
                  .toString();

      // -----------------------------------------------------------------------
      // UPLOAD DELIVERY PROOF
      // -----------------------------------------------------------------------

      final String proofUrl =
          await StorageService
              .uploadBytesDeliveryProof(
        orderId: targetOrderId,
        imageBytes: imageBytes,
      );

      // -----------------------------------------------------------------------
      // UPDATE ORDER
      // -----------------------------------------------------------------------

      await _db.updateOrderStatus(
        orderId: targetOrderId,
        status: 'Completed',
        deliveryPhoto: proofUrl,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Delivery proof captured and saved successfully!',
          ),
          backgroundColor:
              Colors.green,
        ),
      );

      setState(() {
        _targetOrderForProof = null;
        _activeTab = 'Orders';
      });

      await _loadDeliveryData();
    } catch (e) {
      debugPrint(
        'Capture delivery proof error: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to capture proof: $e',
            ),
            backgroundColor:
                Colors.red,
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
  //
  // THIS IS THE IMPORTANT FIX.
  // =============================================================================

  Future<void> _goToLogin() async {
    if (_isGoingToLogin) {
      return;
    }

    _isGoingToLogin = true;

    debugPrint(
      'Going directly to LoginScreen...',
    );

    // ---------------------------------------------------------------------------
    // CLEAR LOGIN SESSION
    // ---------------------------------------------------------------------------

    try {
      await _db.clearSession();
    } catch (e) {
      debugPrint(
        'Clear session error: $e',
      );
    }

    // ---------------------------------------------------------------------------
    // STOP CAMERA
    // ---------------------------------------------------------------------------

    try {
      await _disposeCamera();
    } catch (e) {
      debugPrint(
        'Camera stop error: $e',
      );
    }

    if (!mounted) {
      return;
    }

    // ---------------------------------------------------------------------------
    // REMOVE DASHBOARD COMPLETELY
    // AND OPEN LOGIN SCREEN
    // ---------------------------------------------------------------------------

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) =>
            const LoginScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  // =============================================================================
  // GET ROUTE ORDERS
  // =============================================================================

  List<Map<String, dynamic>>
      _getRouteOrders() {
    final hasRoute =
        _assignedRoute.isNotEmpty;

    if (!hasRoute) {
      return [];
    }

    return _allOrders.where(
      (order) {
        final customer =
            _customers.firstWhere(
          (customer) =>
              customer['mobile'] ==
                  order[
                      'customerMobile'] ||
              customer['name'] ==
                  order[
                      'customerName'],
          orElse: () => {},
        );

        final customerRoute =
            customer['routeName'];

        return customerRoute ==
            _assignedRoute;
      },
    ).toList();
  }

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(
            color: Colors.orange,
          ),
        ),
      );
    }

    final bool hasRoute =
        _assignedRoute.isNotEmpty;

    final routeOrders =
        _getRouteOrders();

    return PopScope(
      // -------------------------------------------------------------------------
      // IMPORTANT:
      //
      // FALSE means:
      // DO NOT POP DASHBOARD.
      //
      // Instead on Android/browser back call _goToLogin().
      // -------------------------------------------------------------------------

      canPop: false,

      onPopInvokedWithResult:
          (didPop, result) {
        if (didPop) {
          return;
        }

        _goToLogin();
      },

      child: Scaffold(
        backgroundColor:
            const Color(0xFFF8FAFC),

        body: SafeArea(
          child: Column(
            children: [
              // =================================================================
              // HEADER
              // =================================================================

              Container(
                padding:
                    const EdgeInsets.all(20),

                decoration:
                    BoxDecoration(
                  color:
                      Colors.orange.shade700,

                  borderRadius:
                      const BorderRadius.only(
                    bottomLeft:
                        Radius.circular(32),
                    bottomRight:
                        Radius.circular(32),
                  ),
                ),

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,

                  children: [
                    // -----------------------------------------------------------
                    // HEADER ROW
                    // -----------------------------------------------------------

                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,

                                decoration:
                                    BoxDecoration(
                                  color: Colors
                                      .orange
                                      .shade900,
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    12,
                                  ),
                                ),

                                child:
                                    const Icon(
                                  Icons
                                      .local_shipping,
                                  color:
                                      Colors.white,
                                  size: 20,
                                ),
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              Expanded(
                                child:
                                    Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    const Text(
                                      'Viraj Dairy Delivery',
                                      overflow:
                                          TextOverflow
                                              .ellipsis,
                                      style:
                                          TextStyle(
                                        color:
                                            Colors
                                                .white,
                                        fontSize:
                                            16,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),

                                    Text(
                                      widget.deliveryPartnerName ??
                                          'Delivery Partner',
                                      overflow:
                                          TextOverflow
                                              .ellipsis,
                                      style:
                                          const TextStyle(
                                        color:
                                            Colors
                                                .white70,
                                        fontSize:
                                            11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // -------------------------------------------------------
                        // BACK TO LOGIN BUTTON
                        // -------------------------------------------------------

                        Container(
                          decoration:
                              BoxDecoration(
                            color: Colors
                                .orange
                                .shade800,
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                          ),

                          child:
                              IconButton(
                            tooltip:
                                'Back to Login',

                            onPressed:
                                _isGoingToLogin
                                    ? null
                                    : _goToLogin,

                            icon:
                                _isGoingToLogin
                                    ? const SizedBox(
                                        width:
                                            20,
                                        height:
                                            20,
                                        child:
                                            CircularProgressIndicator(
                                          color:
                                              Colors
                                                  .white,
                                          strokeWidth:
                                              2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons
                                            .arrow_back,
                                        color:
                                            Colors
                                                .white,
                                        size: 24,
                                      ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    // -----------------------------------------------------------
                    // ROUTE
                    // -----------------------------------------------------------

                    Row(
                      children: [
                        Icon(
                          hasRoute
                              ? Icons.alt_route
                              : Icons
                                  .warning_amber_rounded,
                          color:
                              Colors.white,
                          size: 16,
                        ),

                        const SizedBox(
                          width: 6,
                        ),

                        Expanded(
                          child:
                              Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),

                            decoration:
                                BoxDecoration(
                              color: Colors
                                  .orange
                                  .shade900,
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                10,
                              ),
                            ),

                            child: Text(
                              hasRoute
                                  ? 'Assigned Route: $_assignedRoute'
                                  : 'No route assigned — contact admin',
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                                fontWeight:
                                    FontWeight
                                        .bold,
                                fontSize:
                                    13,
                              ),
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
                child:
                    SingleChildScrollView(
                  padding:
                      const EdgeInsets
                          .all(16),

                  child:
                      _buildActiveContent(
                    hasRoute,
                    routeOrders,
                  ),
                ),
              ),

              // =================================================================
              // FOOTER
              // =================================================================

              Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),

                decoration:
                    BoxDecoration(
                  color: Colors
                      .orange
                      .shade800,

                  borderRadius:
                      const BorderRadius
                          .only(
                    topLeft:
                        Radius.circular(
                            24),
                    topRight:
                        Radius.circular(
                            24),
                  ),
                ),

                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceAround,

                  children: [
                    _buildFooterItem(
                      'Orders',
                      Icons.list_alt,
                    ),

                    _buildFooterItem(
                      'Camera',
                      Icons.camera_alt,
                    ),

                    _buildFooterItem(
                      'Profile',
                      Icons.person,
                    ),
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

  Widget _buildActiveContent(
    bool hasRoute,
    List<Map<String, dynamic>>
        routeOrders,
  ) {
    if (_activeTab == 'Orders') {
      return _buildOrdersTab(
        hasRoute,
        routeOrders,
      );
    }

    if (_activeTab == 'Camera') {
      return _buildCameraTab(
        routeOrders,
      );
    }

    return _buildProfileTab(
      hasRoute,
    );
  }

  // =============================================================================
  // ORDERS TAB
  // =============================================================================

  Widget _buildOrdersTab(
    bool hasRoute,
    List<Map<String, dynamic>>
        routeOrders,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
          children: [
            Expanded(
              child: Text(
                hasRoute
                    ? 'Your Route: $_assignedRoute'
                    : 'No Route Assigned',
                style:
                    const TextStyle(
                  fontSize: 14,
                  fontWeight:
                      FontWeight.bold,
                  color:
                      Color(0xFF1E3A8A),
                ),
                overflow:
                    TextOverflow.ellipsis,
              ),
            ),
            Chip(
              label: Text(
                '${routeOrders.length} Orders',
                style:
                    const TextStyle(
                  fontSize: 11,
                ),
              ),
              backgroundColor:
                  Colors.orange.shade50,
            ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        if (!hasRoute)
          const Padding(
            padding:
                EdgeInsets.only(
              top: 40,
            ),
            child: Center(
              child: Text(
                'You have not been assigned a route yet.\n'
                'Ask your admin to assign one from the Admin Dashboard.',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Colors.grey,
                ),
              ),
            ),
          )
        else if (routeOrders.isEmpty)
          const Padding(
            padding:
                EdgeInsets.only(
              top: 40,
            ),
            child: Center(
              child: Text(
                'No orders assigned to this route.',
                style:
                    TextStyle(
                  color:
                      Colors.grey,
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics:
                const NeverScrollableScrollPhysics(),
            itemCount:
                routeOrders.length,
            itemBuilder:
                (context, index) {
              return _buildOrderCard(
                routeOrders[index],
              );
            },
          ),
      ],
    );
  }

  // =============================================================================
  // ORDER CARD
  // =============================================================================

  Widget _buildOrderCard(
    Map<String, dynamic> order,
  ) {
    final itemsList =
        (order['items'] as List?) ??
            [];

    final status =
        order['status'] ??
            'Pending';

    final isCompleted =
        status == 'Completed' ||
            status == 'Delivered';

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          16,
        ),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    order[
                            'customerName'] ??
                        'Customer',
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight
                              .bold,
                      fontSize: 14,
                    ),
                  ),
                ),

                Chip(
                  label: Text(
                    status,
                    style:
                        const TextStyle(
                      fontSize: 10,
                      color:
                          Colors.white,
                    ),
                  ),
                  backgroundColor:
                      isCompleted
                          ? Colors.green
                          : Colors.orange,
                ),
              ],
            ),

            Text(
              'Mobile: ${order['customerMobile'] ?? 'N/A'}',
              style:
                  TextStyle(
                fontSize: 12,
                color:
                    Colors.grey.shade600,
              ),
            ),

            Text(
              'Address: ${order['address'] ?? "N/A"}',
              style:
                  TextStyle(
                fontSize: 12,
                color:
                    Colors.grey.shade700,
              ),
            ),

            const Divider(
              height: 16,
            ),

            ...itemsList.map(
              (prod) {
                final product =
                    Map<String,
                        dynamic>.from(
                  prod as Map,
                );

                return Padding(
                  padding:
                      const EdgeInsets
                          .only(
                    bottom: 3,
                  ),
                  child: Text(
                    '• ${product['name'] ?? 'Milk'} '
                    '(Qty: ${product['qty'] ?? product['quantity'] ?? 1})',
                    style:
                        const TextStyle(
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(
              height: 12,
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .end,
              children: [
                ElevatedButton.icon(
                  onPressed:
                      _isCapturing
                          ? null
                          : () {
                              setState(() {
                                _targetOrderForProof =
                                    order;
                                _activeTab =
                                    'Camera';
                              });
                            },
                  icon:
                      const Icon(
                    Icons.camera_alt,
                    size: 14,
                  ),
                  label: Text(
                    isCompleted
                        ? 'Retake Proof'
                        : 'Capture & Complete',
                    style:
                        const TextStyle(
                      fontSize: 11,
                    ),
                  ),
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        isCompleted
                            ? Colors.green
                            : Colors.orange
                                .shade800,
                    foregroundColor:
                        Colors.white,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================================
  // CAMERA TAB
  // =============================================================================

  Widget _buildCameraTab(
    List<Map<String, dynamic>>
        routeOrders,
  ) {
    final controller =
        _cameraController;

    final cameraReady =
        _isCameraInitialized &&
            controller != null &&
            controller.value
                .isInitialized;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
          children: [
            Expanded(
              child: Text(
                _targetOrderForProof != null
                    ? 'Proof for: ${_targetOrderForProof!['customerName'] ?? 'Customer'}'
                    : 'Live Camera Proof',
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.bold,
                  color:
                      Color(0xFF1E3A8A),
                ),
              ),
            ),

            if (_cameras.length >
                1)
              IconButton(
                onPressed:
                    _switchCamera,
                tooltip:
                    'Switch Camera',
                icon:
                    const Icon(
                  Icons.cameraswitch,
                  color:
                      Colors.orange,
                ),
              ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        Container(
          height: 380,
          width: double.infinity,
          decoration:
              BoxDecoration(
            color: Colors.black,
            borderRadius:
                BorderRadius.circular(
              20,
            ),
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(
              20,
            ),
            child: cameraReady
                ? _buildCameraPreview(
                    controller,
                  )
                : _buildCameraLoading(),
          ),
        ),

        const SizedBox(
          height: 16,
        ),

        ElevatedButton.icon(
          onPressed:
              _isCapturing
                  ? null
                  : () {
                      if (_targetOrderForProof !=
                          null) {
                        _captureAndSaveProof(
                          _targetOrderForProof!,
                        );
                      } else if (routeOrders
                          .isNotEmpty) {
                        _captureAndSaveProof(
                          routeOrders.first,
                        );
                      } else {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          const SnackBar(
                            content:
                                Text(
                              'No active orders available to attach photo proof.',
                            ),
                          ),
                        );
                      }
                    },
          icon: _isCapturing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(
                    color:
                        Colors.white,
                    strokeWidth:
                        2,
                  ),
                )
              : const Icon(
                  Icons.camera,
                ),
          label: Text(
            _isCapturing
                ? 'Processing Proof...'
                : _targetOrderForProof !=
                        null
                    ? 'Capture Proof for ${_targetOrderForProof!['customerName'] ?? 'Customer'}'
                    : 'Capture & Complete Order',
          ),
          style:
              ElevatedButton.styleFrom(
            backgroundColor:
                Colors.orange.shade800,
            foregroundColor:
                Colors.white,
            minimumSize:
                const Size(
              double.infinity,
              48,
            ),
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
          ),
        ),

        const SizedBox(
          height: 10,
        ),

        if (!cameraReady &&
            _cameraError != null)
          OutlinedButton.icon(
            onPressed:
                _retryCamera,
            icon:
                const Icon(
              Icons.refresh,
            ),
            label:
                const Text(
              'Retry Camera',
            ),
            style:
                OutlinedButton.styleFrom(
              minimumSize:
                  const Size(
                double.infinity,
                46,
              ),
            ),
          ),
      ],
    );
  }

  // =============================================================================
  // CAMERA PREVIEW
  // =============================================================================

  Widget _buildCameraPreview(
    CameraController controller,
  ) {
    final previewSize =
        controller.value.previewSize;

    if (previewSize == null) {
      return CameraPreview(
        controller,
      );
    }

    final aspectRatio =
        previewSize.width /
            previewSize.height;

    return Center(
      child: AspectRatio(
        aspectRatio:
            aspectRatio,
        child:
            CameraPreview(
          controller,
        ),
      ),
    );
  }

  // =============================================================================
  // CAMERA LOADING
  // =============================================================================

  Widget _buildCameraLoading() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            if (_cameraError !=
                null) ...[
              const Icon(
                Icons.error_outline,
                color:
                    Colors.redAccent,
                size: 40,
              ),

              const SizedBox(
                height: 12,
              ),

              Text(
                _cameraError!,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color:
                      Colors.white70,
                  fontSize: 12,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              ElevatedButton.icon(
                onPressed:
                    _retryCamera,
                icon:
                    const Icon(
                  Icons.refresh,
                ),
                label:
                    const Text(
                  'Retry Camera',
                ),
              ),
            ] else ...[
              const CircularProgressIndicator(
                color:
                    Colors.orange,
              ),

              const SizedBox(
                height: 12,
              ),

              const Text(
                'Initializing Camera...',
                style:
                    TextStyle(
                  color:
                      Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =============================================================================
  // PROFILE TAB
  // =============================================================================

  Widget _buildProfileTab(
    bool hasRoute,
  ) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [
          const SizedBox(
            height: 8,
          ),

          const Text(
            'Delivery Partner Profile',
            style:
                TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
              color:
                  Color(0xFF1E3A8A),
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          Container(
            width: double.infinity,
            constraints:
                const BoxConstraints(
              maxWidth: 400,
            ),
            padding:
                const EdgeInsets.all(
              28,
            ),
            decoration:
                BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                20,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(
                    0.05,
                  ),
                  blurRadius: 10,
                  offset:
                      const Offset(
                    0,
                    4,
                  ),
                ),
              ],
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor:
                      Colors.orange,
                  child:
                      Icon(
                    Icons.person,
                    size: 60,
                    color:
                        Colors.white,
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                Text(
                  widget.deliveryPartnerName ??
                      'Delivery Partner',
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 20,
                    color:
                        Colors.black87,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                if (widget
                            .deliveryPartnerMobile !=
                        null &&
                    widget
                        .deliveryPartnerMobile!
                        .isNotEmpty) ...[
                  Text(
                    'Mobile: ${widget.deliveryPartnerMobile}',
                    style:
                        TextStyle(
                      fontSize: 14,
                      color:
                          Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(
                    height: 10,
                  ),
                ],

                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration:
                      BoxDecoration(
                    color: Colors
                        .orange
                        .shade50,
                    borderRadius:
                        BorderRadius
                            .circular(
                      20,
                    ),
                  ),
                  child: Text(
                    hasRoute
                        ? 'Assigned Route: $_assignedRoute'
                        : 'No Route Assigned',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      fontSize: 13,
                      fontWeight:
                          FontWeight
                              .w600,
                      color: Colors
                          .orange
                          .shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // FOOTER
  // =============================================================================

  Widget _buildFooterItem(
    String tabKey,
    IconData icon,
  ) {
    final isActive =
        _activeTab == tabKey;

    return Expanded(
      child: GestureDetector(
        behavior:
            HitTestBehavior.opaque,

        onTap: () {
          setState(() {
            _activeTab = tabKey;
          });

          if (tabKey == 'Camera' &&
              !_isCameraInitialized) {
            if (_cameras.isEmpty) {
              _initCamera();
            } else {
              _initController(
                _selectedCameraIndex,
              );
            }
          }
        },

        child: Padding(
          padding:
              const EdgeInsets
                  .symmetric(
            vertical: 2,
          ),

          child: Column(
            mainAxisSize:
                MainAxisSize.min,

            children: [
              Icon(
                icon,
                color: isActive
                    ? Colors.white
                    : Colors.white70,
                size: 22,
              ),

              const SizedBox(
                height: 3,
              ),

              Text(
                tabKey,
                style:
                    TextStyle(
                  fontSize: 10,
                  color: isActive
                      ? Colors.white
                      : Colors.white70,
                  fontWeight:
                      isActive
                          ? FontWeight
                              .bold
                          : FontWeight
                              .normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}