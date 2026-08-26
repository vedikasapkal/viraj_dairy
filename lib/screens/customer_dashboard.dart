// =============================================================================
// CUSTOMER DASHBOARD
// lib/screens/customer_dashboard.dart
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../models/menu_data.dart';
import '../services/database_service.dart';
import '../services/billing_service.dart';
import 'login_screen.dart';
import 'customer_payment_screen.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard>
    with TickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();

  // ===========================================================================
  // STATE
  // ===========================================================================

  bool _loading = true;

  String _activeTab = 'home';
  String _searchTerm = '';

  String? _mobile;

  String _name = 'Guest Customer';
  String _address = 'Not Added';

  List<CartItemModel> _cart = [];

  MenuItemModel? _selectedProduct;

  final List<String> _selectedExtras = [];

  bool _justAdded = false;

  String? _selectedBrandFilter;

  // ===========================================================================
  // MAIN PAGE ANIMATION
  // ===========================================================================

  late AnimationController _pageAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // ===========================================================================
  // BANNER ANIMATION
  // ===========================================================================

  late AnimationController _bannerController;
  late Animation<double> _bannerScaleAnimation;
  late Animation<Offset> _bannerSlideAnimation;

  // ===========================================================================
  // SEARCH ANIMATION
  // ===========================================================================

  late AnimationController _searchController;
  late Animation<double> _searchScaleAnimation;

  // ===========================================================================
  // BRAND AUTO SCROLL
  // ===========================================================================

  final ScrollController _brandScrollController = ScrollController();

  Timer? _brandAutoScrollTimer;

  bool _brandMovingRight = true;

  // ===========================================================================
  // NEARBY SHOP ANIMATION
  // ===========================================================================

  late AnimationController _nearbyController;
  late Animation<double> _nearbyScaleAnimation;
  late Animation<double> _nearbyFloatAnimation;

  // ===========================================================================
  // NAVIGATION ANIMATION
  // ===========================================================================

  late AnimationController _navController;

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    // -------------------------------------------------------------------------
    // MAIN PAGE ANIMATION
    // -------------------------------------------------------------------------

    _pageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _pageAnimationController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _pageAnimationController,
        curve: Curves.easeOutBack,
      ),
    );

    // -------------------------------------------------------------------------
    // BANNER ANIMATION
    // -------------------------------------------------------------------------

    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    _bannerScaleAnimation = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _bannerController,
        curve: Curves.easeOutBack,
      ),
    );

    _bannerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _bannerController,
        curve: Curves.easeOutCubic,
      ),
    );

    // -------------------------------------------------------------------------
    // SEARCH ANIMATION
    // -------------------------------------------------------------------------

    _searchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _searchScaleAnimation = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _searchController,
        curve: Curves.easeOutBack,
      ),
    );

    // -------------------------------------------------------------------------
    // NEARBY SHOP ANIMATION
    // -------------------------------------------------------------------------

    _nearbyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _nearbyScaleAnimation = TweenSequence<double>(
      [
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 0.96,
            end: 1.04,
          ),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1.04,
            end: 0.96,
          ),
          weight: 50,
        ),
      ],
    ).animate(
      CurvedAnimation(
        parent: _nearbyController,
        curve: Curves.easeInOut,
      ),
    );

    _nearbyFloatAnimation = TweenSequence<double>(
      [
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 0,
            end: -5,
          ),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: -5,
            end: 0,
          ),
          weight: 50,
        ),
      ],
    ).animate(
      CurvedAnimation(
        parent: _nearbyController,
        curve: Curves.easeInOut,
      ),
    );

    // -------------------------------------------------------------------------
    // BOTTOM NAVIGATION
    // -------------------------------------------------------------------------

    _navController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // -------------------------------------------------------------------------
    // START ANIMATIONS
    // -------------------------------------------------------------------------

    _pageAnimationController.forward();

    Future.delayed(
      const Duration(milliseconds: 150),
      () {
        if (!mounted) return;

        _bannerController.forward();
        _searchController.forward();
        _nearbyController.repeat();
        _navController.forward();
      },
    );

    // -------------------------------------------------------------------------
    // LOAD ONLY PROFILE
    // -------------------------------------------------------------------------

    _loadProfile();

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        _startBrandAutoScroll();
      },
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _pageAnimationController.dispose();
    _bannerController.dispose();
    _searchController.dispose();
    _nearbyController.dispose();
    _navController.dispose();

    _brandAutoScrollTimer?.cancel();
    _brandScrollController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // LOAD CUSTOMER PROFILE
  //
  // IMPORTANT:
  // Orders are NOT loaded here.
  // Profile section contains ONLY profile information.
  // ===========================================================================

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final session = await _db.getSession();

      if (session == null) {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
        );

        return;
      }

      _mobile = session['mobile']?.toString();

      if (_mobile == null || _mobile!.isEmpty) {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
        );

        return;
      }

      // -----------------------------------------------------------------------
      // ONLY CUSTOMER PROFILE IS FETCHED.
      //
      // No getOrdersForCustomer() here.
      // -----------------------------------------------------------------------

      final profile = await _db.getUserProfile(
        role: 'customer',
        mobile: _mobile!,
      );

      if (!mounted) return;

      setState(() {
        _name = profile?['name']?.toString() ?? 'Guest Customer';

        _address =
            profile?['address']?.toString() ?? 'Not Added';
      });
    } catch (e) {
      debugPrint(
        'Customer profile load error: $e',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load your profile: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  Future<void> _logout() async {
    try {
      await _db.clearSession();
    } catch (e) {
      debugPrint(
        'Logout error: $e',
      );
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  // ===========================================================================
  // CHECKOUT
  // ===========================================================================

  Future<void> _handleCheckout() async {
    if (_cart.isEmpty || _mobile == null) {
      return;
    }

    final cartItemsMapped = _cart
        .map(
          (item) => {
            'name': item.name,
            'price': item.price,
            'chosenExtras': item.chosenExtras,
          },
        )
        .toList();

    try {
      await _db.saveOrder(
        customerMobile: _mobile!,
        customerName: _name,
        address: _address,
        items: cartItemsMapped,
        totalAmount:
            BillingService.calculateCartTotal(
          _cart,
        ),
      );

      setState(() {
        _cart.clear();
      });

      // Refresh profile only.
      await _loadProfile();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Order placed successfully!',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Checkout error: $e',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to place order: $e',
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // PRODUCT
  // ===========================================================================

  void _openProduct(
    MenuItemModel product,
  ) {
    setState(() {
      _selectedProduct = product;

      _selectedExtras.clear();

      if (product.extras.isNotEmpty) {
        _selectedExtras.add(
          product.extras.first,
        );
      }

      _justAdded = false;
    });
  }

  void _addToCart() {
    if (_selectedProduct == null) {
      return;
    }

    setState(() {
      _cart.add(
        CartItemModel(
          id: DateTime.now()
              .millisecondsSinceEpoch
              .toString(),
          name: _selectedProduct!.name,
          price: _selectedProduct!.price,
          img: _selectedProduct!.img,
          chosenExtras:
              List.from(
            _selectedExtras,
          ),
        ),
      );

      _justAdded = true;
    });

    Future.delayed(
      const Duration(
        milliseconds: 800,
      ),
      () {
        if (!mounted) return;

        setState(() {
          _selectedProduct = null;
        });
      },
    );
  }

  void _removeFromCart(
    String id,
  ) {
    setState(() {
      _cart.removeWhere(
        (item) => item.id == id,
      );
    });
  }

  // ===========================================================================
  // BRAND FILTERS
  // ===========================================================================

  List<String> get _brandFilters {
    return menuGroups
        .where(
          (group) => group.title.startsWith(
            'Brand -',
          ),
        )
        .map(
          (group) => group.title.replaceFirst(
            'Brand - ',
            '',
          ),
        )
        .toList();
  }

  // ===========================================================================
  // BRAND IMAGE
  // ===========================================================================

  String? _getBrandImage(
    MenuGroupModel group,
  ) {
    if (group.items.isEmpty) {
      return null;
    }

    final image = group.items.first.img;

    if (image.trim().isEmpty) {
      return null;
    }

    return image;
  }

  // ===========================================================================
  // FILTERED GROUPS
  // ===========================================================================

  List<MenuGroupModel> get _filteredBrandGroups {
    var groups = menuGroups;

    if (_selectedBrandFilter != null) {
      groups = groups
          .where(
            (g) =>
                g.title ==
                    'Brand - $_selectedBrandFilter' ||
                g.title.contains(
                  _selectedBrandFilter!,
                ),
          )
          .toList();
    }

    if (_searchTerm.trim().isNotEmpty) {
      final term = _searchTerm
          .toLowerCase()
          .trim();

      groups = groups.where(
        (group) {
          final matchesGroup = group.title
              .toLowerCase()
              .contains(term);

          final matchesItem = group.items.any(
            (item) => item.name
                .toLowerCase()
                .contains(term),
          );

          return matchesGroup || matchesItem;
        },
      ).toList();
    }

    return groups;
  }

  // ===========================================================================
  // BRAND AUTO SCROLL
  // ===========================================================================

  void _startBrandAutoScroll() {
    _brandAutoScrollTimer?.cancel();

    _brandAutoScrollTimer = Timer.periodic(
      const Duration(
        milliseconds: 45,
      ),
      (_) {
        if (!mounted) return;

        if (!_brandScrollController.hasClients) {
          return;
        }

        final maxExtent =
            _brandScrollController
                .position
                .maxScrollExtent;

        if (maxExtent <= 0) {
          return;
        }

        double current =
            _brandScrollController.offset;

        if (_brandMovingRight) {
          current += 1.1;

          if (current >= maxExtent) {
            _brandMovingRight = false;
          }
        } else {
          current -= 1.1;

          if (current <= 0) {
            _brandMovingRight = true;
          }
        }

        current = current.clamp(
          0.0,
          maxExtent,
        );

        _brandScrollController.jumpTo(
          current,
        );
      },
    );
  }

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  void _handleNavTap(
    String tabKey,
  ) {
    // -------------------------------------------------------------------------
    // BILLS
    // -------------------------------------------------------------------------

    if (tabKey == 'bills') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerPaymentScreen(
            customer: {
              'mobile': _mobile ?? '',
              'name': _name,
              'address': _address,
            },
          ),
        ),
      );

      return;
    }

    // -------------------------------------------------------------------------
    // OTHER TABS
    // -------------------------------------------------------------------------

    setState(() {
      _activeTab = tabKey;
    });

    _pageAnimationController.reset();
    _pageAnimationController.forward();

    // -------------------------------------------------------------------------
    // HOME ANIMATION
    // -------------------------------------------------------------------------

    if (tabKey == 'home') {
      _bannerController.reset();
      _searchController.reset();

      Future.delayed(
        const Duration(
          milliseconds: 100,
        ),
        () {
          if (!mounted) return;

          _bannerController.forward();
          _searchController.forward();
        },
      );
    }
  }

  // ===========================================================================
  // PRODUCT CARD
  // ===========================================================================

  Widget _buildProductCard(
    MenuItemModel product, {
    int index = 0,
  }) {
    return _AnimatedHoverZoomTiltCard(
      product: product,
      index: index,
      onTap: () => _openProduct(product),
    );
  }

  // ===========================================================================
  // NAV ITEM
  // ===========================================================================

  Widget _buildNavItem(
    String tabKey,
    IconData icon,
    String label, {
    int badgeCount = 0,
  }) {
    final bool isActive =
        _activeTab == tabKey;

    return GestureDetector(
      onTap: () => _handleNavTap(
        tabKey,
      ),
      child: AnimatedContainer(
        duration: const Duration(
          milliseconds: 350,
        ),
        curve: Curves.easeOutBack,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF2563EB)
                  .withOpacity(0.12)
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(
            18,
          ),
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Stack(
              clipBehavior:
                  Clip.none,
              children: [
                AnimatedContainer(
                  duration:
                      const Duration(
                    milliseconds: 300,
                  ),
                  padding:
                      EdgeInsets.all(
                    isActive ? 4 : 2,
                  ),
                  decoration:
                      BoxDecoration(
                    color: isActive
                        ? const Color(
                            0xFF2563EB,
                          ).withOpacity(0.10)
                        : Colors.transparent,
                    shape:
                        BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isActive
                        ? const Color(
                            0xFF2563EB,
                          )
                        : Colors.grey.shade600,
                    size:
                        isActive ? 26 : 24,
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      constraints:
                          const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding:
                          const EdgeInsets.all(
                        3,
                      ),
                      decoration:
                          const BoxDecoration(
                        color: Colors.red,
                        shape:
                            BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$badgeCount',
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                            fontSize: 9,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(
              height: 2,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: isActive
                    ? const Color(
                        0xFF2563EB,
                      )
                    : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PROFILE INFORMATION ROW
  // ===========================================================================

  Widget _buildProfileInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration:
              BoxDecoration(
            color: const Color(
              0xFFEFF6FF,
            ),
            borderRadius:
                BorderRadius.circular(
              13,
            ),
          ),
          child: Icon(
            icon,
            color: const Color(
              0xFF2563EB,
            ),
            size: 22,
          ),
        ),
        const SizedBox(
          width: 13,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              const SizedBox(
                height: 4,
              ),
              Text(
                value.isEmpty
                    ? 'Not Added'
                    : value,
                maxLines: 4,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      Color(0xFF1F2937),
                  fontSize: 14,
                  fontWeight:
                      FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PROFILE
  //
  // IMPORTANT:
  // NO ORDERS ARE DISPLAYED HERE.
  // ===========================================================================

  Widget _buildProfile() {
    return Padding(
      padding: const EdgeInsets.only(
        top: 18,
        bottom: 30,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // -------------------------------------------------------------------
          // PROFILE HEADER
          // -------------------------------------------------------------------

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(
              22,
            ),
            decoration:
                BoxDecoration(
              gradient:
                  const LinearGradient(
                colors: [
                  Color(0xFF0F2F75),
                  Color(0xFF1D4ED8),
                  Color(0xFF2563EB),
                ],
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.circular(
                24,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      const Color(
                    0xFF2563EB,
                  ).withOpacity(0.25),
                  blurRadius: 18,
                  offset:
                      const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration:
                      BoxDecoration(
                    color: Colors.white
                        .withOpacity(0.16),
                    shape:
                        BoxShape.circle,
                    border:
                        Border.all(
                      color: Colors.white
                          .withOpacity(
                        0.35,
                      ),
                      width: 2,
                    ),
                  ),
                  child:
                      const Icon(
                    Icons
                        .person_rounded,
                    color:
                        Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(
                  width: 15,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      const Text(
                        'Customer Profile',
                        style:
                            TextStyle(
                          color:
                              Colors.white70,
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        _name,
                        maxLines: 2,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize: 21,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      const SizedBox(
                        height: 5,
                      ),
                      const Text(
                        'Your account information',
                        style:
                            TextStyle(
                          color:
                              Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          // -------------------------------------------------------------------
          // PERSONAL INFORMATION
          // -------------------------------------------------------------------

          const Text(
            'Personal Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w900,
              color:
                  Color(0xFF1E3A8A),
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(
              18,
            ),
            decoration:
                BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(
                21,
              ),
              border: Border.all(
                color:
                    Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(
                    0.045,
                  ),
                  blurRadius: 14,
                  offset:
                      const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildProfileInfoCard(
                  icon: Icons
                      .person_outline_rounded,
                  title: 'Full Name',
                  value: _name,
                ),

                const Divider(
                  height: 24,
                ),

                _buildProfileInfoCard(
                  icon: Icons
                      .phone_outlined,
                  title: 'Mobile Number',
                  value:
                      _mobile ??
                          'Not Available',
                ),

                const Divider(
                  height: 24,
                ),

                _buildProfileInfoCard(
                  icon: Icons
                      .location_on_outlined,
                  title:
                      'Delivery Address',
                  value: _address,
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          // -------------------------------------------------------------------
          // ACCOUNT INFORMATION
          // -------------------------------------------------------------------

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(
              18,
            ),
            decoration:
                BoxDecoration(
              color:
                  const Color(
                0xFFEFF6FF,
              ),
              borderRadius:
                  BorderRadius.circular(
                20,
              ),
              border: Border.all(
                color:
                    const Color(
                  0xFFBFDBFE,
                ),
              ),
            ),
            child: const Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Icon(
                  Icons
                      .verified_user_outlined,
                  color:
                      Color(0xFF2563EB),
                  size: 25,
                ),
                SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Customer Account',
                        style:
                            TextStyle(
                          color:
                              Color(
                            0xFF1E3A8A,
                          ),
                          fontSize: 14,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      SizedBox(
                        height: 5,
                      ),
                      Text(
                        'Your profile information is securely linked to your customer account.',
                        style:
                            TextStyle(
                          color:
                              Color(
                            0xFF4B5563,
                          ),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(
              0.04,
            ),
            blurRadius: 12,
            offset:
                const Offset(0, 4),
          ),
        ],
        border:
            Border(
          bottom: BorderSide(
            color:
                Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment
                .spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding:
                    const EdgeInsets.all(
                  2,
                ),
                decoration:
                    BoxDecoration(
                  color: Colors.white,
                  shape:
                      BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(
                        0xFF2563EB,
                      ).withOpacity(0.18),
                      blurRadius: 10,
                      offset:
                          const Offset(
                        0,
                        4,
                      ),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/logo.jpeg',
                    fit:
                        BoxFit.cover,
                    errorBuilder:
                        (
                      _,
                      __,
                      ___,
                    ) =>
                            const Icon(
                      Icons.store,
                      color:
                          Colors.blue,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                width: 9,
              ),
              const Text(
                'Viraj Dairy Menu',
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 16,
                  color:
                      Color(0xFF1E3A8A),
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon:
                    const Icon(
                  Icons
                      .notifications_none,
                  color:
                      Color(0xFF1E3A8A),
                  size: 23,
                ),
                onPressed: () {},
              ),
              IconButton(
                icon:
                    const Icon(
                  Icons.exit_to_app,
                  color:
                      Colors.red,
                  size: 22,
                ),
                onPressed: _logout,
                tooltip:
                    'Logout',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ANIMATED BANNER
  // ===========================================================================

  Widget _buildBanner() {
    return SlideTransition(
      position:
          _bannerSlideAnimation,
      child: ScaleTransition(
        scale:
            _bannerScaleAnimation,
        child: Container(
          width:
              double.infinity,
          height: 158,
          margin:
              const EdgeInsets.fromLTRB(
            16,
            10,
            16,
            8,
          ),
          decoration:
              BoxDecoration(
            gradient:
                const LinearGradient(
              colors: [
                Color(0xFF0F2F75),
                Color(0xFF1E3A8A),
                Color(0xFF2563EB),
              ],
              begin:
                  Alignment.topLeft,
              end:
                  Alignment.bottomRight,
            ),
            borderRadius:
                BorderRadius.circular(
              28,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(
                  0xFF1E3A8A,
                ).withOpacity(0.30),
                blurRadius: 22,
                spreadRadius: 1,
                offset:
                    const Offset(
                  0,
                  10,
                ),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -35,
                top: -45,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration:
                      BoxDecoration(
                    color: Colors
                        .white
                        .withOpacity(0.07),
                    shape:
                        BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: -60,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration:
                      BoxDecoration(
                    color: Colors
                        .white
                        .withOpacity(0.06),
                    shape:
                        BoxShape.circle,
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    28,
                  ),
                  child: Opacity(
                    opacity: 0.11,
                    child:
                        Image.asset(
                      'assets/logo.jpeg',
                      fit:
                          BoxFit.cover,
                      errorBuilder:
                          (
                        _,
                        __,
                        ___,
                      ) =>
                              const SizedBox
                                  .shrink(),
                    ),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.all(
                  20,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          RichText(
                            text:
                                TextSpan(
                              text:
                                  'Welcome, ',
                              style:
                                  const TextStyle(
                                fontSize:
                                    20,
                                fontWeight:
                                    FontWeight.w600,
                                color:
                                    Colors.white,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '$_name 👋',
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.amber,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          const Text(
                            'Fresh dairy & partner brands',
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          const Text(
                            'Delivered fresh to your door.',
                            style:
                                TextStyle(
                              color:
                                  Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 76,
                      height: 76,
                      decoration:
                          BoxDecoration(
                        color: Colors
                            .white
                            .withOpacity(
                          0.14,
                        ),
                        shape:
                            BoxShape.circle,
                        border:
                            Border.all(
                          color: Colors
                              .white
                              .withOpacity(
                            0.20,
                          ),
                        ),
                      ),
                      child: ClipOval(
                        child:
                            Image.asset(
                          'assets/logo.jpeg',
                          fit:
                              BoxFit.cover,
                          errorBuilder:
                              (
                            _,
                            __,
                            ___,
                          ) =>
                                  const Icon(
                            Icons
                                .local_drink,
                            color:
                                Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
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

  // ===========================================================================
  // SEARCH BAR
  // ===========================================================================

  Widget _buildAnimatedSearchBar() {
    return ScaleTransition(
      scale:
          _searchScaleAnimation,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          4,
          16,
          4,
        ),
        child: Container(
          height: 54,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 15,
          ),
          decoration:
              BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            border:
                Border.all(
              color:
                  const Color(
                0xFFDBEAFE,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(
                  0xFF2563EB,
                ).withOpacity(0.10),
                blurRadius: 15,
                offset:
                    const Offset(
                  0,
                  6,
                ),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.all(
                  7,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFEFF6FF,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child:
                    const Icon(
                  Icons.search,
                  color:
                      Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: TextField(
                  onChanged:
                      (value) {
                    setState(() {
                      _searchTerm =
                          value;
                    });
                  },
                  decoration:
                      const InputDecoration(
                    hintText:
                        'Search brands or products...',
                    border:
                        InputBorder.none,
                    hintStyle:
                        TextStyle(
                      color:
                          Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (_searchTerm
                  .isNotEmpty)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _searchTerm =
                          '';
                    });
                  },
                  child:
                      const Icon(
                    Icons.clear,
                    size: 19,
                    color:
                        Colors.grey,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BRAND SLIDER
  // ===========================================================================

  Widget _buildBrandSlider() {
    final groups = menuGroups
        .where(
          (group) =>
              group.items.isNotEmpty,
        )
        .toList();

    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Padding(
          padding:
              EdgeInsets.fromLTRB(
            18,
            15,
            18,
            8,
          ),
          child: Row(
            children: [
              Icon(
                Icons
                    .storefront_rounded,
                color:
                    Color(0xFF2563EB),
                size: 20,
              ),
              SizedBox(
                width: 7,
              ),
              Text(
                'Popular Brands',
                style:
                    TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w900,
                  color:
                      Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 118,
          child: ListView.builder(
            controller:
                _brandScrollController,
            scrollDirection:
                Axis.horizontal,
            physics:
                const BouncingScrollPhysics(),
            padding:
                const EdgeInsets
                    .symmetric(
              horizontal: 16,
            ),
            itemCount:
                groups.length,
            itemBuilder:
                (context, index) {
              return _AnimatedBrandCard(
                group:
                    groups[index],
                index: index,
                selected:
                    _selectedBrandFilter ==
                        groups[index]
                            .title
                            .replaceFirst(
                      'Brand - ',
                      '',
                    ),
                image:
                    _getBrandImage(
                  groups[index],
                ),
                onTap: () {
                  final brand =
                      groups[index]
                          .title
                          .replaceFirst(
                    'Brand - ',
                    '',
                  );

                  setState(() {
                    _selectedBrandFilter =
                        _selectedBrandFilter ==
                                brand
                            ? null
                            : brand;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // FILTER CARDS
  // ===========================================================================

  Widget _buildFilterCards() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        10,
        16,
        3,
      ),
      child: SizedBox(
        height: 46,
        child: ListView(
          scrollDirection:
              Axis.horizontal,
          physics:
              const BouncingScrollPhysics(),
          children: [
            _AnimatedFilterCard(
              label: 'All Items',
              icon:
                  Icons.apps_rounded,
              selected:
                  _selectedBrandFilter ==
                      null,
              onTap: () {
                setState(() {
                  _selectedBrandFilter =
                      null;
                });
              },
            ),
            ..._brandFilters.map(
              (brand) {
                return _AnimatedFilterCard(
                  label: brand,
                  icon: Icons
                      .local_mall_rounded,
                  selected:
                      _selectedBrandFilter ==
                          brand,
                  onTap: () {
                    setState(() {
                      _selectedBrandFilter =
                          _selectedBrandFilter ==
                                  brand
                              ? null
                              : brand;
                    });
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PRODUCT GROUPS
  // ===========================================================================

  Widget _buildProductGroups() {
    if (_filteredBrandGroups.isEmpty) {
      return const Padding(
        padding:
            EdgeInsets.symmetric(
          vertical: 70,
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.search_off_rounded,
                color: Colors.grey,
                size: 45,
              ),
              SizedBox(
                height: 10,
              ),
              Text(
                'No products match your filter.',
                style:
                    TextStyle(
                  color:
                      Colors.grey,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        for (
          int groupIndex = 0;
          groupIndex <
              _filteredBrandGroups.length;
          groupIndex++
        ) ...[
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              4,
              13,
              4,
              9,
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 22,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFF2563EB,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      8,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Text(
                    _filteredBrandGroups[
                            groupIndex]
                        .title,
                    style:
                        const TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.w900,
                      color:
                          Color(0xFF111827),
                    ),
                  ),
                ),
                Text(
                  '${_filteredBrandGroups[groupIndex].items.length} items',
                  style:
                      const TextStyle(
                    color:
                        Colors.grey,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics:
                const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: 0.73,
            ),
            itemCount:
                _filteredBrandGroups[
                        groupIndex]
                    .items
                    .length,
            itemBuilder:
                (context, index) {
              return _buildProductCard(
                _filteredBrandGroups[
                        groupIndex]
                    .items[index],
                index:
                    index +
                        groupIndex,
              );
            },
          ),
          const SizedBox(
            height: 10,
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // NEARBY SHOP CARD
  // ===========================================================================

  Widget _buildNearbyShopCard() {
    return AnimatedBuilder(
      animation:
          _nearbyController,
      builder:
          (context, child) {
        return Transform.translate(
          offset: Offset(
            0,
            _nearbyFloatAnimation
                .value,
          ),
          child: Transform.scale(
            scale:
                _nearbyScaleAnimation
                    .value,
            child: child,
          ),
        );
      },
      child: Container(
        margin:
            const EdgeInsets.fromLTRB(
          0,
          18,
          0,
          20,
        ),
        padding:
            const EdgeInsets.all(
          20,
        ),
        decoration:
            BoxDecoration(
          gradient:
              const LinearGradient(
            colors: [
              Color(0xFF0F2F75),
              Color(0xFF1D4ED8),
              Color(0xFF2563EB),
            ],
            begin:
                Alignment.topLeft,
            end:
                Alignment.bottomRight,
          ),
          borderRadius:
              BorderRadius.circular(
            25,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  const Color(
                0xFF1D4ED8,
              ).withOpacity(0.30),
              blurRadius: 20,
              offset:
                  const Offset(
                0,
                10,
              ),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -25,
              child: Container(
                width: 100,
                height: 100,
                decoration:
                    BoxDecoration(
                  color: Colors
                      .white
                      .withOpacity(0.07),
                  shape:
                      BoxShape.circle,
                ),
              ),
            ),
            Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration:
                          BoxDecoration(
                        color: Colors
                            .white
                            .withOpacity(
                          0.15,
                        ),
                        shape:
                            BoxShape.circle,
                      ),
                      child:
                          const Icon(
                        Icons
                            .location_on_rounded,
                        color:
                            Colors.white,
                        size: 29,
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            'Nearby Store',
                            style:
                                TextStyle(
                              color:
                                  Colors.white70,
                              fontSize:
                                  12,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                          SizedBox(
                            height: 2,
                          ),
                          Text(
                            'Visit Our Shop',
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize:
                                  19,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration:
                          BoxDecoration(
                        color: Colors
                            .green
                            .withOpacity(
                          0.90,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                      ),
                      child:
                          const Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 7,
                            color:
                                Colors.white,
                          ),
                          SizedBox(
                            width: 5,
                          ),
                          Text(
                            'OPEN',
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize:
                                  10,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 17,
                ),
                Container(
                  width:
                      double.infinity,
                  padding:
                      const EdgeInsets.all(
                    13,
                  ),
                  decoration:
                      BoxDecoration(
                    color: Colors
                        .white
                        .withOpacity(
                      0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                    border:
                        Border.all(
                      color: Colors
                          .white
                          .withOpacity(
                        0.10,
                      ),
                    ),
                  ),
                  child:
                      const Column(
                    children: [
                      Text(
                        'Viraj Dairy, Kunal Icon',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontSize:
                              14,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Text(
                        'Pimple Saudagar, Pune - 411027',
                        style:
                            TextStyle(
                          color:
                              Colors.white70,
                          fontSize:
                              12,
                        ),
                        textAlign:
                            TextAlign
                                .center,
                      ),
                      SizedBox(
                        height: 8,
                      ),
                      Text(
                        '📞 9850921154',
                        style:
                            TextStyle(
                          color:
                              Colors.amber,
                          fontSize:
                              14,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HOME
  // ===========================================================================

  Widget _buildHome() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _buildBanner(),
        _buildAnimatedSearchBar(),
        _buildBrandSlider(),
        _buildFilterCards(),
        _buildProductGroups(),
        _buildNearbyShopCard(),
      ],
    );
  }

  // ===========================================================================
  // SEARCH TAB
  // ===========================================================================

  Widget _buildSearchTab() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const SizedBox(
          height: 12,
        ),
        _buildAnimatedSearchBar(),
        _buildFilterCards(),
        const SizedBox(
          height: 8,
        ),
        _buildProductGroups(),
      ],
    );
  }

  // ===========================================================================
  // CART
  // ===========================================================================

  Widget _buildCart() {
    if (_cart.isEmpty) {
      return const Padding(
        padding:
            EdgeInsets.only(
          top: 90,
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons
                    .shopping_cart_outlined,
                color:
                    Colors.grey,
                size: 58,
              ),
              SizedBox(
                height: 12,
              ),
              Text(
                'Your cart is empty.',
                style:
                    TextStyle(
                  color:
                      Colors.grey,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (
          int i = 0;
          i < _cart.length;
          i++
        )
          _AnimatedCartCard(
            item: _cart[i],
            index: i,
            onDelete: () {
              _removeFromCart(
                _cart[i].id,
              );
            },
          ),

        const SizedBox(
          height: 12,
        ),

        // ---------------------------------------------------------------------
        // TOTAL
        // ---------------------------------------------------------------------

        Container(
          padding:
              const EdgeInsets.all(
            17,
          ),
          decoration:
              BoxDecoration(
            color:
                Colors.white,
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            border:
                Border.all(
              color:
                  Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(
                  0.04,
                ),
                blurRadius: 10,
                offset:
                    const Offset(
                  0,
                  5,
                ),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
            children: [
              const Text(
                'Total Amount:',
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                '₹${BillingService.calculateCartTotal(_cart)}',
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 19,
                  color:
                      Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(
          height: 16,
        ),

        // ---------------------------------------------------------------------
        // CHECKOUT
        // ---------------------------------------------------------------------

        SizedBox(
          width:
              double.infinity,
          height: 52,
          child:
              ElevatedButton(
            style:
                ElevatedButton.styleFrom(
              elevation: 5,
              shadowColor:
                  const Color(
                0xFF2563EB,
              ).withOpacity(0.35),
              backgroundColor:
                  const Color(
                0xFF2563EB,
              ),
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
              ),
            ),
            onPressed:
                _handleCheckout,
            child:
                const Text(
              'Proceed to Checkout',
              style:
                  TextStyle(
                color:
                    Colors.white,
                fontWeight:
                    FontWeight.bold,
                fontSize:
                    15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PRODUCT DETAIL POPUP
  // ===========================================================================

  Widget _buildProductDialog() {
    if (_selectedProduct == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Material(
        color:
            Colors.black.withOpacity(
          0.58,
        ),
        child: Center(
          child: TweenAnimationBuilder<
              double>(
            tween: Tween(
              begin: 0.82,
              end: 1.0,
            ),
            duration:
                const Duration(
              milliseconds: 400,
            ),
            curve:
                Curves.easeOutBack,
            builder:
                (
              context,
              value,
              child,
            ) {
              return Transform.scale(
                scale: value,
                child: child,
              );
            },
            child:
                ConstrainedBox(
              constraints:
                  BoxConstraints(
                maxWidth:
                    MediaQuery.of(
                          context,
                        ).size.width *
                        0.91,
                maxHeight:
                    MediaQuery.of(
                          context,
                        ).size.height *
                        0.86,
              ),
              child:
                  Container(
                padding:
                    const EdgeInsets.all(
                  20,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.white,
                  borderRadius:
                      BorderRadius.circular(
                    25,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors
                          .black
                          .withOpacity(
                        0.30,
                      ),
                      blurRadius: 30,
                      offset:
                          const Offset(
                        0,
                        15,
                      ),
                    ),
                  ],
                ),
                child:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child:
                              Text(
                            _selectedProduct!
                                .name,
                            style:
                                const TextStyle(
                              fontSize:
                                  18,
                              fontWeight:
                                  FontWeight
                                      .bold,
                              color:
                                  Color(
                                0xFF1F2937,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(
                            Icons.close,
                          ),
                          onPressed:
                              () {
                            setState(
                              () {
                                _selectedProduct =
                                    null;
                              },
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    _AnimatedDialogImage(
                      image:
                          _selectedProduct!
                              .img,
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      _selectedProduct!
                          .price,
                      style:
                          const TextStyle(
                        fontSize:
                            17,
                        fontWeight:
                            FontWeight
                                .w900,
                        color:
                            Color(
                          0xFF1D4ED8,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 15,
                    ),

                    const Text(
                      'Select Pack Size / Quantity Option:',
                      style:
                          TextStyle(
                        fontSize:
                            14,
                        fontWeight:
                            FontWeight
                                .bold,
                        color:
                            Color(
                          0xFF1F2937,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Container(
                      padding:
                          const EdgeInsets
                              .all(
                        9,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.blue
                                .shade50,
                        borderRadius:
                            BorderRadius
                                .circular(
                          10,
                        ),
                      ),
                      child:
                          const Text(
                        'ℹ️ Choose your preferred size or packet volume below.',
                        style:
                            TextStyle(
                          fontSize:
                              11,
                          fontWeight:
                              FontWeight
                                  .w600,
                          color:
                              Color(
                            0xFF1E3A8A,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Flexible(
                      child: _selectedProduct!
                              .extras
                              .isEmpty
                          ? const Center(
                              child:
                                  Text(
                                'Standard Pack Size Available',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.grey,
                                ),
                              ),
                            )
                          : ListView(
                              shrinkWrap:
                                  true,
                              children:
                                  _selectedProduct!
                                      .extras
                                      .map(
                                (
                                  extraOption,
                                ) {
                                  final isSelected =
                                      _selectedExtras.contains(
                                    extraOption,
                                  );

                                  return CheckboxListTile(
                                    contentPadding:
                                        EdgeInsets.zero,
                                    secondary:
                                        Container(
                                      width:
                                          40,
                                      height:
                                          40,
                                      decoration:
                                          BoxDecoration(
                                        color:
                                            Colors.blue.shade50,
                                        borderRadius:
                                            BorderRadius.circular(
                                          9,
                                        ),
                                      ),
                                      child:
                                          const Icon(
                                        Icons
                                            .local_mall,
                                        size:
                                            20,
                                        color:
                                            Color(
                                          0xFF2563EB,
                                        ),
                                      ),
                                    ),
                                    title:
                                        Text(
                                      extraOption,
                                      style:
                                          const TextStyle(
                                        fontSize:
                                            13,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                    subtitle:
                                        const Text(
                                      'Extra / Size Variant',
                                      style:
                                          TextStyle(
                                        fontSize:
                                            11,
                                        color:
                                            Colors.grey,
                                      ),
                                    ),
                                    value:
                                        isSelected,
                                    activeColor:
                                        const Color(
                                      0xFF2563EB,
                                    ),
                                    onChanged:
                                        (
                                      checked,
                                    ) {
                                      setState(
                                        () {
                                          if (checked ==
                                              true) {
                                            _selectedExtras
                                                .clear();

                                            _selectedExtras
                                                .add(
                                              extraOption,
                                            );
                                          } else {
                                            _selectedExtras
                                                .remove(
                                              extraOption,
                                            );
                                          }
                                        },
                                      );
                                    },
                                  );
                                },
                              ).toList(),
                            ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    SizedBox(
                      width:
                          double.infinity,
                      height: 49,
                      child:
                          ElevatedButton(
                        style:
                            ElevatedButton
                                .styleFrom(
                          elevation:
                              5,
                          backgroundColor:
                              _justAdded
                                  ? Colors
                                      .green
                                  : const Color(
                                      0xFF2563EB,
                                    ),
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              14,
                            ),
                          ),
                        ),
                        onPressed:
                            _addToCart,
                        child:
                            Text(
                          _justAdded
                              ? 'Added to Cart! ✓'
                              : 'Add to Cart',
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .bold,
                            fontSize:
                                14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          const Color(0xFFF8FAFC),
      body: SafeArea(
        child: FadeTransition(
          opacity:
              _fadeAnimation,
          child: ScaleTransition(
            scale:
                _scaleAnimation,
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(),

                    Expanded(
                      child:
                          SingleChildScrollView(
                        padding:
                            const EdgeInsets
                                .fromLTRB(
                          16,
                          0,
                          16,
                          100,
                        ),
                        physics:
                            const BouncingScrollPhysics(),
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            if (_activeTab ==
                                'home')
                              _buildHome()
                            else if (_activeTab ==
                                'search')
                              _buildSearchTab()
                            else if (_activeTab ==
                                'cart')
                              _buildCart()
                            else if (_activeTab ==
                                'profile')
                              _buildProfile(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // -----------------------------------------------------------------
                // PRODUCT POPUP
                // -----------------------------------------------------------------

                if (_selectedProduct !=
                    null)
                  _buildProductDialog(),

                // -----------------------------------------------------------------
                // BOTTOM NAVIGATION
                // -----------------------------------------------------------------

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child:
                      SlideTransition(
                    position:
                        Tween<Offset>(
                      begin:
                          const Offset(
                        0,
                        1,
                      ),
                      end:
                          Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent:
                            _navController,
                        curve:
                            Curves.easeOutBack,
                      ),
                    ),
                    child:
                        Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors
                                .black
                                .withOpacity(
                              0.09,
                            ),
                            blurRadius:
                                18,
                            offset:
                                const Offset(
                              0,
                              -6,
                            ),
                          ),
                        ],
                        border:
                            Border(
                          top:
                              BorderSide(
                            color: Colors
                                .grey
                                .shade200,
                          ),
                        ),
                      ),
                      child:
                          Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceAround,
                        children: [
                          _buildNavItem(
                            'home',
                            Icons
                                .home_rounded,
                            'Home',
                          ),
                          _buildNavItem(
                            'search',
                            Icons
                                .search_rounded,
                            'Search',
                          ),
                          _buildNavItem(
                            'cart',
                            Icons
                                .shopping_cart_rounded,
                            'Cart',
                            badgeCount:
                                _cart
                                    .length,
                          ),
                          _buildNavItem(
                            'bills',
                            Icons
                                .receipt_long_rounded,
                            'Bills',
                          ),
                          _buildNavItem(
                            'profile',
                            Icons
                                .person_rounded,
                            'Profile',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ANIMATED PRODUCT CARD
// =============================================================================

class _AnimatedHoverZoomTiltCard
    extends StatefulWidget {
  final MenuItemModel product;
  final int index;
  final VoidCallback onTap;

  const _AnimatedHoverZoomTiltCard({
    required this.product,
    required this.index,
    required this.onTap,
  });

  @override
  State<_AnimatedHoverZoomTiltCard>
      createState() =>
          _AnimatedHoverZoomTiltCardState();
}

class _AnimatedHoverZoomTiltCardState
    extends State<_AnimatedHoverZoomTiltCard>
    with TickerProviderStateMixin {
  late AnimationController
      _hoverController;

  late AnimationController
      _imageController;

  late Animation<double>
      _cardScale;

  late Animation<double>
      _cardLift;

  late Animation<double>
      _imageScale;

  bool _isHovering = false;

  @override
  void initState() {
    super.initState();

    _hoverController =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 220,
      ),
    );

    _cardScale =
        Tween<double>(
      begin: 1.0,
      end: 1.035,
    ).animate(
      CurvedAnimation(
        parent:
            _hoverController,
        curve:
            Curves.easeOutCubic,
      ),
    );

    _cardLift =
        Tween<double>(
      begin: 0.0,
      end: -4.0,
    ).animate(
      CurvedAnimation(
        parent:
            _hoverController,
        curve:
            Curves.easeOutCubic,
      ),
    );

    _imageController =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 700,
      ),
    );

    _imageScale =
        Tween<double>(
      begin: 1.0,
      end: 1.10,
    ).animate(
      CurvedAnimation(
        parent:
            _imageController,
        curve:
            Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  void _startHover() {
    if (!mounted) return;

    setState(() {
      _isHovering = true;
    });

    _hoverController.forward();
    _imageController.forward();
  }

  void _endHover() {
    if (!mounted) return;

    setState(() {
      _isHovering = false;
    });

    _hoverController.reverse();
    _imageController.reverse();
  }

  void _onTapDown(
    TapDownDetails details,
  ) {
    _startHover();
  }

  void _onTapUp(
    TapUpDetails details,
  ) {
    _endHover();

    widget.onTap();
  }

  void _onTapCancel() {
    _endHover();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return MouseRegion(
      onEnter:
          (_) => _startHover(),
      onExit:
          (_) => _endHover(),
      cursor:
          SystemMouseCursors.click,
      child:
          GestureDetector(
        onTapDown:
            _onTapDown,
        onTapUp:
            _onTapUp,
        onTapCancel:
            _onTapCancel,
        child:
            AnimatedBuilder(
          animation:
              _hoverController,
          builder:
              (
            context,
            child,
          ) {
            return Transform
                .translate(
              offset:
                  Offset(
                0,
                _cardLift
                    .value,
              ),
              child:
                  Transform
                      .scale(
                scale:
                    _cardScale
                        .value,
                child:
                    child,
              ),
            );
          },
          child:
              AnimatedContainer(
            duration:
                const Duration(
              milliseconds: 220,
            ),
            curve:
                Curves.easeOutCubic,
            decoration:
                BoxDecoration(
              color:
                  Colors.white,
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border:
                  Border.all(
                color:
                    _isHovering
                        ? const Color(
                            0xFF2563EB,
                          )
                        : Colors
                            .grey
                            .shade200,
                width:
                    _isHovering
                        ? 1.5
                        : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      _isHovering
                          ? const Color(
                              0xFF2563EB,
                            ).withOpacity(
                              0.20,
                            )
                          : Colors
                              .black
                              .withOpacity(
                              0.055,
                            ),
                  blurRadius:
                      _isHovering
                          ? 18
                          : 9,
                  spreadRadius:
                      _isHovering
                          ? 1
                          : 0,
                  offset:
                      _isHovering
                          ? const Offset(
                              0,
                              8,
                            )
                          : const Offset(
                              0,
                              4,
                            ),
                ),
              ],
            ),
            child:
                ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Expanded(
                    child:
                        ClipRRect(
                      borderRadius:
                          const BorderRadius
                              .vertical(
                        top:
                            Radius.circular(
                          18,
                        ),
                      ),
                      child:
                          SizedBox(
                        width:
                            double.infinity,
                        child:
                            AnimatedBuilder(
                          animation:
                              _imageController,
                          builder:
                              (
                            context,
                            child,
                          ) {
                            return Transform
                                .scale(
                              scale:
                                  _imageScale
                                      .value,
                              child:
                                  child,
                            );
                          },
                          child:
                              Image.asset(
                            widget
                                .product
                                .img,
                            width:
                                double.infinity,
                            height:
                                double.infinity,
                            fit:
                                BoxFit.cover,
                            errorBuilder:
                                (
                              _,
                              __,
                              ___,
                            ) {
                              return Container(
                                color:
                                    Colors.grey.shade100,
                                child:
                                    const Center(
                                  child:
                                      Icon(
                                    Icons
                                        .image,
                                    color:
                                        Colors.grey,
                                    size:
                                        36,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width:
                        double.infinity,
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFEFF6FF,
                      ),
                      border:
                          Border(
                        top:
                            BorderSide(
                          color:
                              Colors.blue.shade100,
                        ),
                      ),
                    ),
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          widget
                              .product
                              .name,
                          maxLines:
                              1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight
                                    .bold,
                            fontSize:
                                13,
                            color:
                                Color(
                              0xFF1E3A8A,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .spaceBetween,
                          children: [
                            Flexible(
                              child:
                                  Text(
                                widget
                                    .product
                                    .price,
                                maxLines:
                                    1,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .w900,
                                  color:
                                      Color(
                                    0xFF1D4ED8,
                                  ),
                                  fontSize:
                                      12,
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 6,
                            ),
                            AnimatedContainer(
                              duration:
                                  const Duration(
                                milliseconds:
                                    200,
                              ),
                              padding:
                                  const EdgeInsets
                                      .all(
                                5,
                              ),
                              decoration:
                                  BoxDecoration(
                                color: _isHovering
                                    ? const Color(
                                        0xFF1D4ED8,
                                      )
                                    : const Color(
                                        0xFF2563EB,
                                      ),
                                shape:
                                    BoxShape.circle,
                              ),
                              child:
                                  const Icon(
                                Icons.add,
                                size:
                                    14,
                                color:
                                    Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ANIMATED BRAND CARD
// =============================================================================

class _AnimatedBrandCard
    extends StatefulWidget {
  final MenuGroupModel group;
  final int index;
  final bool selected;
  final String? image;
  final VoidCallback onTap;

  const _AnimatedBrandCard({
    required this.group,
    required this.index,
    required this.selected,
    required this.image,
    required this.onTap,
  });

  @override
  State<_AnimatedBrandCard>
      createState() =>
          _AnimatedBrandCardState();
}

class _AnimatedBrandCardState
    extends State<_AnimatedBrandCard>
    with TickerProviderStateMixin {
  late AnimationController
      _controller;

  late AnimationController
      _imageController;

  late Animation<double>
      _scaleAnimation;

  late Animation<double>
      _imageAnimation;

  bool _hovering = false;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 220,
      ),
    );

    _imageController =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 600,
      ),
    );

    _scaleAnimation =
        Tween<double>(
      begin: 1.0,
      end: 1.045,
    ).animate(
      CurvedAnimation(
        parent:
            _controller,
        curve:
            Curves.easeOutCubic,
      ),
    );

    _imageAnimation =
        Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(
      CurvedAnimation(
        parent:
            _imageController,
        curve:
            Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _imageController.dispose();
    super.dispose();
  }

  void _hoverStart() {
    if (!mounted) return;

    setState(() {
      _hovering = true;
    });

    _controller.forward();
    _imageController.forward();
  }

  void _hoverEnd() {
    if (!mounted) return;

    setState(() {
      _hovering = false;
    });

    _controller.reverse();
    _imageController.reverse();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final brandName =
        widget.group.title
            .replaceFirst(
      'Brand - ',
      '',
    );

    return MouseRegion(
      onEnter:
          (_) => _hoverStart(),
      onExit:
          (_) => _hoverEnd(),
      cursor:
          SystemMouseCursors.click,
      child:
          GestureDetector(
        onTapDown:
            (_) => _hoverStart(),
        onTapUp:
            (_) {
          _hoverEnd();
          widget.onTap();
        },
        onTapCancel:
            _hoverEnd,
        child:
            AnimatedBuilder(
          animation:
              _controller,
          builder:
              (
            context,
            child,
          ) {
            return Transform.scale(
              scale:
                  _scaleAnimation
                      .value,
              child:
                  child,
            );
          },
          child:
              AnimatedContainer(
            duration:
                const Duration(
              milliseconds:
                  220,
            ),
            width: 92,
            margin:
                const EdgeInsets
                    .only(
              right: 11,
            ),
            padding:
                const EdgeInsets
                    .all(
              7,
            ),
            decoration:
                BoxDecoration(
              color:
                  widget.selected
                      ? const Color(
                          0xFFEFF6FF,
                        )
                      : Colors.white,
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border:
                  Border.all(
                color:
                    widget.selected
                        ? const Color(
                            0xFF2563EB,
                          )
                        : _hovering
                            ? const Color(
                                0xFF60A5FA,
                              )
                            : Colors
                                .grey
                                .shade200,
                width:
                    widget.selected
                        ? 2
                        : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      _hovering ||
                              widget.selected
                          ? const Color(
                              0xFF2563EB,
                            ).withOpacity(
                              0.18,
                            )
                          : Colors
                              .black
                              .withOpacity(
                              0.05,
                            ),
                  blurRadius:
                      _hovering
                          ? 14
                          : 7,
                  offset:
                      const Offset(
                    0,
                    4,
                  ),
                ),
              ],
            ),
            child:
                Column(
              mainAxisAlignment:
                  MainAxisAlignment
                      .center,
              children: [
                Expanded(
                  child:
                      ClipRRect(
                    borderRadius:
                        BorderRadius
                            .circular(
                      14,
                    ),
                    child:
                        Container(
                      width:
                          double.infinity,
                      color:
                          Colors
                              .grey
                              .shade100,
                      child:
                          widget.image ==
                                  null
                              ? const Icon(
                                  Icons
                                      .storefront_rounded,
                                  color:
                                      Color(
                                    0xFF2563EB,
                                  ),
                                  size:
                                      32,
                                )
                              : AnimatedBuilder(
                                  animation:
                                      _imageController,
                                  builder:
                                      (
                                    context,
                                    child,
                                  ) {
                                    return Transform
                                        .scale(
                                      scale:
                                          _imageAnimation
                                              .value,
                                      child:
                                          child,
                                    );
                                  },
                                  child:
                                      Image.asset(
                                    widget
                                        .image!,
                                    fit:
                                        BoxFit.cover,
                                    errorBuilder:
                                        (
                                      _,
                                      __,
                                      ___,
                                    ) {
                                      return const Center(
                                        child:
                                            Icon(
                                          Icons
                                              .storefront_rounded,
                                          color:
                                              Color(
                                            0xFF2563EB,
                                          ),
                                          size:
                                              32,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                    ),
                  ),
                ),
                const SizedBox(
                  height: 6,
                ),
                Text(
                  brandName,
                  maxLines:
                      1,
                  overflow:
                      TextOverflow.ellipsis,
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    fontSize:
                        11,
                    fontWeight:
                        FontWeight.w800,
                    color:
                        widget.selected
                            ? const Color(
                                0xFF1D4ED8,
                              )
                            : const Color(
                                0xFF374151,
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ANIMATED FILTER CARD
// =============================================================================

class _AnimatedFilterCard
    extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AnimatedFilterCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_AnimatedFilterCard>
      createState() =>
          _AnimatedFilterCardState();
}

class _AnimatedFilterCardState
    extends State<_AnimatedFilterCard>
    with SingleTickerProviderStateMixin {
  late AnimationController
      _controller;

  late Animation<double>
      _scaleAnimation;

  bool _hovering = false;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 200,
      ),
    );

    _scaleAnimation =
        Tween<double>(
      begin: 1.0,
      end: 1.045,
    ).animate(
      CurvedAnimation(
        parent:
            _controller,
        curve:
            Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hoverStart() {
    if (!mounted) return;

    setState(() {
      _hovering = true;
    });

    _controller.forward();
  }

  void _hoverEnd() {
    if (!mounted) return;

    setState(() {
      _hovering = false;
    });

    _controller.reverse();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return MouseRegion(
      onEnter:
          (_) => _hoverStart(),
      onExit:
          (_) => _hoverEnd(),
      cursor:
          SystemMouseCursors.click,
      child:
          GestureDetector(
        onTapDown:
            (_) => _hoverStart(),
        onTapUp:
            (_) {
          _hoverEnd();
          widget.onTap();
        },
        onTapCancel:
            _hoverEnd,
        child:
            AnimatedBuilder(
          animation:
              _controller,
          builder:
              (
            context,
            child,
          ) {
            return Transform.scale(
              scale:
                  _scaleAnimation
                      .value,
              child:
                  child,
            );
          },
          child:
              AnimatedContainer(
            duration:
                const Duration(
              milliseconds:
                  200,
            ),
            margin:
                const EdgeInsets
                    .only(
              right: 8,
            ),
            padding:
                const EdgeInsets
                    .symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration:
                BoxDecoration(
              color:
                  widget.selected
                      ? const Color(
                          0xFF2563EB,
                        )
                      : Colors.white,
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              border:
                  Border.all(
                color:
                    widget.selected
                        ? const Color(
                            0xFF2563EB,
                          )
                        : _hovering
                            ? const Color(
                                0xFF60A5FA,
                              )
                            : Colors
                                .grey
                                .shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      _hovering ||
                              widget.selected
                          ? const Color(
                              0xFF2563EB,
                            ).withOpacity(
                              0.18,
                            )
                          : Colors
                              .black
                              .withOpacity(
                              0.04,
                            ),
                  blurRadius:
                      _hovering
                          ? 10
                          : 6,
                  offset:
                      const Offset(
                    0,
                    3,
                  ),
                ),
              ],
            ),
            child:
                Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color:
                      widget.selected
                          ? Colors.white
                          : const Color(
                              0xFF2563EB,
                            ),
                ),
                const SizedBox(
                  width: 6,
                ),
                Text(
                  widget.label,
                  style:
                      TextStyle(
                    fontSize:
                        11,
                    fontWeight:
                        FontWeight.w800,
                    color:
                        widget.selected
                            ? Colors.white
                            : const Color(
                                0xFF374151,
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ANIMATED CART CARD
// =============================================================================

class _AnimatedCartCard
    extends StatefulWidget {
  final CartItemModel item;
  final int index;
  final VoidCallback onDelete;

  const _AnimatedCartCard({
    required this.item,
    required this.index,
    required this.onDelete,
  });

  @override
  State<_AnimatedCartCard>
      createState() =>
          _AnimatedCartCardState();
}

class _AnimatedCartCardState
    extends State<_AnimatedCartCard>
    with SingleTickerProviderStateMixin {
  late AnimationController
      _controller;

  late Animation<double>
      _entryAnimation;

  bool _hovering = false;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            350 +
                (widget.index *
                    60),
      ),
    );

    _entryAnimation =
        CurvedAnimation(
      parent:
          _controller,
      curve:
          Curves.easeOutCubic,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return FadeTransition(
      opacity:
          _entryAnimation,
      child:
          SlideTransition(
        position:
            Tween<Offset>(
          begin:
              const Offset(
            0.12,
            0,
          ),
          end:
              Offset.zero,
        ).animate(
          _entryAnimation,
        ),
        child:
            MouseRegion(
          onEnter:
              (_) {
            if (!mounted) return;

            setState(
              () => _hovering =
                  true,
            );
          },
          onExit:
              (_) {
            if (!mounted) return;

            setState(
              () => _hovering =
                  false,
            );
          },
          cursor:
              SystemMouseCursors.click,
          child:
              AnimatedContainer(
            duration:
                const Duration(
              milliseconds:
                  220,
            ),
            margin:
                const EdgeInsets
                    .only(
              bottom: 11,
            ),
            padding:
                const EdgeInsets
                    .all(
              11,
            ),
            transform:
                _hovering
                    ? (Matrix4.identity()
                      ..translate(
                        0.0,
                        -3.0,
                      )
                      ..scale(
                        1.015,
                      ))
                    : Matrix4.identity(),
            decoration:
                BoxDecoration(
              color:
                  Colors.white,
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border:
                  Border.all(
                color:
                    _hovering
                        ? const Color(
                            0xFF60A5FA,
                          )
                        : Colors
                            .grey
                            .shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      _hovering
                          ? const Color(
                              0xFF2563EB,
                            ).withOpacity(
                              0.15,
                            )
                          : Colors
                              .black
                              .withOpacity(
                              0.045,
                            ),
                  blurRadius:
                      _hovering
                          ? 15
                          : 10,
                  offset:
                      const Offset(
                    0,
                    5,
                  ),
                ),
              ],
            ),
            child:
                Row(
              children: [
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    13,
                  ),
                  child:
                      SizedBox(
                    width: 72,
                    height: 72,
                    child:
                        Image.asset(
                      widget
                          .item
                          .img,
                      fit:
                          BoxFit.cover,
                      errorBuilder:
                          (
                        _,
                        __,
                        ___,
                      ) {
                        return Container(
                          color:
                              Colors
                                  .grey
                                  .shade100,
                          child:
                              const Icon(
                            Icons
                                .image,
                            color:
                                Colors.grey,
                            size:
                                30,
                          ),
                        );
                      },
                    ),
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
                      Text(
                        widget
                            .item
                            .name,
                        maxLines:
                            2,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style:
                            const TextStyle(
                          fontSize:
                              14,
                          fontWeight:
                              FontWeight
                                  .w800,
                          color:
                              Color(
                            0xFF1F2937,
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      if (widget
                          .item
                          .chosenExtras
                          .isNotEmpty)
                        Text(
                          widget
                              .item
                              .chosenExtras
                              .join(
                            ', ',
                          ),
                          maxLines:
                              2,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            fontSize:
                                11,
                            color:
                                Colors.grey,
                          ),
                        ),
                      const SizedBox(
                        height: 5,
                      ),
                      Text(
                        widget
                            .item
                            .price,
                        style:
                            const TextStyle(
                          fontSize:
                              13,
                          fontWeight:
                              FontWeight
                                  .w900,
                          color:
                              Color(
                            0xFF1D4ED8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip:
                      'Remove',
                  onPressed:
                      widget
                          .onDelete,
                  icon:
                      const Icon(
                    Icons
                        .delete_outline_rounded,
                    color:
                        Colors.red,
                    size: 23,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ANIMATED DIALOG IMAGE
// =============================================================================

class _AnimatedDialogImage
    extends StatefulWidget {
  final String image;

  const _AnimatedDialogImage({
    required this.image,
  });

  @override
  State<_AnimatedDialogImage>
      createState() =>
          _AnimatedDialogImageState();
}

class _AnimatedDialogImageState
    extends State<_AnimatedDialogImage>
    with SingleTickerProviderStateMixin {
  late AnimationController
      _controller;

  late Animation<double>
      _scaleAnimation;

  bool _hovering = false;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 500,
      ),
    );

    _scaleAnimation =
        Tween<double>(
      begin: 1.0,
      end: 1.07,
    ).animate(
      CurvedAnimation(
        parent:
            _controller,
        curve:
            Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (!mounted) return;

    setState(() {
      _hovering = true;
    });

    _controller.forward();
  }

  void _end() {
    if (!mounted) return;

    setState(() {
      _hovering = false;
    });

    _controller.reverse();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return MouseRegion(
      onEnter:
          (_) => _start(),
      onExit:
          (_) => _end(),
      child:
          GestureDetector(
        onTapDown:
            (_) => _start(),
        onTapUp:
            (_) => _end(),
        onTapCancel:
            _end,
        child:
            Container(
          width:
              double.infinity,
          height: 190,
          decoration:
              BoxDecoration(
            color:
                Colors.grey.shade100,
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            border:
                Border.all(
              color:
                  _hovering
                      ? const Color(
                          0xFF60A5FA,
                        )
                      : Colors
                          .grey
                          .shade200,
            ),
          ),
          child:
              ClipRRect(
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            child:
                AnimatedBuilder(
              animation:
                  _controller,
              builder:
                  (
                context,
                child,
              ) {
                return Transform.scale(
                  scale:
                      _scaleAnimation
                          .value,
                  child:
                      child,
                );
              },
              child:
                  Image.asset(
                widget.image,
                width:
                    double.infinity,
                height:
                    double.infinity,
                fit:
                    BoxFit.contain,
                errorBuilder:
                    (
                  _,
                  __,
                  ___,
                ) {
                  return const Center(
                    child:
                        Icon(
                      Icons
                          .image_not_supported_outlined,
                      color:
                          Colors.grey,
                      size:
                          45,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}