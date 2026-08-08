// =============================================================================
// CUSTOMER DASHBOARD (lib/screens/customer_dashboard.dart)
// =============================================================================

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

class _CustomerDashboardState extends State<CustomerDashboard> {
  final DatabaseService _db = DatabaseService();

  // State variables
  bool _loading = true;
  String _activeTab = 'home';
  String _searchTerm = '';
  String? _mobile;
  String _name = 'Guest Customer';
  String _address = 'Not Added';
  List<Map<String, dynamic>> _pastOrders = [];
  List<CartItemModel> _cart = [];
  MenuItemModel? _selectedProduct;
  final List<String> _selectedExtras = [];
  bool _justAdded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final session = await _db.getSession();
      if (session == null) {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        return;
      }
      _mobile = session['mobile'];
      final profile = await _db.getUserProfile(role: 'customer', mobile: _mobile!);
      final orders = await _db.getOrdersForCustomer(_mobile!);
      if (!mounted) return;
      setState(() {
        _name = profile?['name'] ?? 'Guest Customer';
        _address = profile?['address'] ?? 'Not Added';
        _pastOrders = orders;
      });
    } catch (e) {
      debugPrint('Customer profile load error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load your profile: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _db.clearSession();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _handleCheckout() async {
    if (_cart.isEmpty || _mobile == null) return;

    final cartItemsMapped = _cart.map((item) => {
      'name': item.name,
      'price': item.price,
      'chosenExtras': item.chosenExtras,
    }).toList();

    try {
      await _db.saveOrder(
        customerMobile: _mobile!,
        customerName: _name,
        address: _address,
        items: cartItemsMapped,
        totalAmount: BillingService.calculateCartTotal(_cart),
      );

      setState(() => _cart.clear());
      await _loadProfile();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed successfully!')));
    } catch (e) {
      debugPrint('Checkout error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to place order: $e')));
    }
  }

  void _openProduct(MenuItemModel product) {
    setState(() {
      _selectedProduct = product;
      _selectedExtras.clear();
      _justAdded = false;
    });
  }

  void _toggleExtra(String extra) {
    setState(() {
      if (_selectedExtras.contains(extra)) {
        _selectedExtras.remove(extra);
      } else {
        _selectedExtras.add(extra);
      }
    });
  }

  void _addToCart() {
    if (_selectedProduct == null) return;
    setState(() {
      _cart.add(CartItemModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _selectedProduct!.name,
        price: _selectedProduct!.price,
        img: _selectedProduct!.img,
        chosenExtras: List.from(_selectedExtras),
      ));
      _justAdded = true;
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _selectedProduct = null);
    });
  }

  void _removeFromCart(String id) {
    setState(() => _cart.removeWhere((item) => item.id == id));
  }

  List<MenuItemModel> get _filteredResults {
    if (_searchTerm.trim().isEmpty) return [];
    final term = _searchTerm.toLowerCase();
    return menuGroups.expand((group) => group.items).where((product) => product.name.toLowerCase().contains(term)).toList();
  }

  // Bottom-nav taps: "bills" opens the payment/QR screen as its own page
  // instead of switching the in-page tab, since it's a full billing flow.
  void _handleNavTap(String tabKey) {
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
    setState(() => _activeTab = tabKey);
  }

  Widget _buildProductCard(MenuItemModel product) {
    return GestureDetector(
      onTap: () => _openProduct(product),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE0F2FE), Color(0xFFF0F9FF)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBAE6FD)),
          boxShadow: [BoxShadow(color: const Color(0xFF1E40AF).withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 84, width: double.infinity, color: Colors.white,
                child: Image.asset(product.img, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey, size: 32)),
              ),
            ),
            const SizedBox(height: 6),
            Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1F2937)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(product.price, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8), fontSize: 13)),
            GestureDetector(
              onTap: () => _openProduct(product),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.add, size: 14, color: Colors.white),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top App Bar Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(50),
                            child: Container(
                              width: 36,
                              height: 36,
                              color: Colors.blue.shade100,
                              child: Image.asset(
                                'assets/logo.jpeg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.store, color: Colors.blue, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Viraj Dairy Menu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A))),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_none, color: Color(0xFF1E3A8A), size: 22),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.exit_to_app, color: Colors.red, size: 22),
                            onPressed: _logout,
                            tooltip: 'Logout',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Banner Section (Only on Home tab)
                if (_activeTab == 'home') ...[
                  Container(
                    width: double.infinity,
                    height: 160,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E3A8A),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                            child: Opacity(
                              opacity: 0.2,
                              child: Image.asset(
                                'assets/logo.jpeg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  text: 'Welcome, ',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                                  children: [
                                    TextSpan(
                                      text: '$_name 👋',
                                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search Trigger Bar below banner
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 'search'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.search, color: Color(0xFF2563EB), size: 20),
                            SizedBox(width: 12),
                            Text('Search Milk, Paneer, Ghee...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Scrollable Content Area based on Active Tab
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_activeTab == 'home') ...[
                          for (var group in menuGroups) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              child: Text(group.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF111827))),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.82,
                              ),
                              itemCount: group.items.length,
                              itemBuilder: (context, index) {
                                return _buildProductCard(group.items[index]);
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Visit Our Shop Section
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A8A),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Column(
                              children: [
                                Text('Visit Our Shop', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                SizedBox(height: 4),
                                Text('Viraj Dairy, Kunal Icon', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                Text('Pimple Saudagar, Pune - 411027', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                SizedBox(height: 8),
                                Text('📞 9850921154', style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ] else if (_activeTab == 'search') ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.search, color: Color(0xFF2563EB), size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      autofocus: true,
                                      onChanged: (val) => setState(() => _searchTerm = val),
                                      decoration: const InputDecoration(
                                        hintText: 'Search products...',
                                        border: InputBorder.none,
                                        hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.82,
                            ),
                            itemCount: _filteredResults.length,
                            itemBuilder: (context, index) {
                              return _buildProductCard(_filteredResults[index]);
                            },
                          ),
                        ] else if (_activeTab == 'cart') ...[
                          _cart.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 80),
                                  child: Center(child: Text('Your cart is empty.', style: TextStyle(color: Colors.grey, fontSize: 14))),
                                )
                              : Column(
                                  children: [
                                    ..._cart.map((item) => Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: Image.asset(item.img, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.broken_image)),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F2937))),
                                                    const SizedBox(height: 4),
                                                    Text(item.price, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8), fontSize: 13)),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                                onPressed: () => _removeFromCart(item.id),
                                              ),
                                            ],
                                          ),
                                        )),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF2563EB),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: _handleCheckout,
                                        child: const Text('Proceed to Checkout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                        ] else if (_activeTab == 'profile') ...[
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF4F46E5)]),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                        child: const CircleAvatar(radius: 40, backgroundImage: NetworkImage('https://cdn-icons-png.flaticon.com/512/3135/3135715.png')),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('Hello, Customer 👋', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      const Text('Welcome to Viraj Dairy', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    children: [
                                      _buildProfileDetailRow('Name', _name),
                                      _buildProfileDetailRow('Mobile', _mobile ?? 'Not Added'),
                                      _buildProfileDetailRow('Address', _address),
                                      _buildProfileDetailRow('Orders', '${_pastOrders.length}'),
                                      _buildProfileDetailRow('Member Since', '${DateTime.now().year}'),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF2563EB),
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: _loadProfile,
                                          child: const Text('Refresh Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Colors.red),
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: _logout,
                                          child: const Text('Logout / Exit', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // Footer Navigation Bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem('home', Icons.home_rounded, 'Home'),
                      _buildNavItem('search', Icons.search, 'Search'),
                      _buildNavItem('cart', Icons.shopping_cart_outlined, 'Cart', badgeCount: _cart.length),
                      _buildNavItem('bills', Icons.receipt_long, 'Bills'),
                      _buildNavItem('profile', Icons.person_outline, 'Profile'),
                    ],
                  ),
                ),
              ],
            ),

            // Modal Bottom Sheet Overlay for Options Selection
            if (_selectedProduct != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text('${_selectedProduct!.name} - Select Options', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF111827))),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _selectedProduct = null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._selectedProduct!.extras.map((extra) {
                          final isSelected = _selectedExtras.contains(extra);
                          return GestureDetector(
                            onTap: () => _toggleExtra(extra),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.blue.shade50 : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(extra, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.blue.shade800 : Colors.grey.shade800)),
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (_) => _toggleExtra(extra),
                                    activeColor: const Color(0xFF2563EB),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _addToCart,
                            child: Text(
                              _justAdded ? 'Added to Cart! ✓' : 'Add to Cart',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(String tabKey, IconData icon, String label, {int badgeCount = 0}) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => _handleNavTap(tabKey),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: isActive ? const Color(0xFF2563EB) : Colors.grey.shade400, size: 24),
              if (badgeCount > 0)
                Positioned(
                  right: -8,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? const Color(0xFF2563EB) : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}