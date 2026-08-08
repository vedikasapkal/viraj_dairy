// =============================================================================
// SIGNUP SCREEN (lib/screens/signup_screen.dart)
// =============================================================================

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'login_screen.dart';
import 'admin_dashboard.dart';
import 'delivery_dashboard.dart';
import 'customer_dashboard.dart';

class SignupScreen extends StatefulWidget {
  final String initialRole;
  const SignupScreen({super.key, this.initialRole = 'customer'});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final DatabaseService _db = DatabaseService();
  late String _role;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Structured Customer Address Controllers
  final TextEditingController _wingController = TextEditingController();
  final TextEditingController _houseNoController = TextEditingController();
  final TextEditingController _societyController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  Future<void> _handleSignup() async {
    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || mobile.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all mandatory fields')));
      return;
    }

    String finalAddress = '';
    if (_role == 'customer') {
      final wing = _wingController.text.trim();
      final houseNo = _houseNoController.text.trim();
      final society = _societyController.text.trim();

      if (wing.isEmpty || houseNo.isEmpty || society.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wing, House No, and Society Name are mandatory!')));
        return;
      }
      finalAddress = 'Wing: $wing, House No: $houseNo, Society: $society';
    } else {
      finalAddress = _addressController.text.trim();
    }

    setState(() => _loading = true);
    try {
      final ok = await _db.registerUser(role: _role, mobile: mobile, password: password, name: name, address: finalAddress);

      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An account for this mobile already exists as $_role.')));
        return;
      }

      await _db.saveSession(mobile: mobile, role: _role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_role.toUpperCase()} account created!')));

      if (_role == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
      } else if (_role == 'delivery') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DeliveryDashboard()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerDashboard()));
      }
    } catch (e) {
      debugPrint('Signup error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signup failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.35,
          width: double.infinity,
          child: Image.asset('assets/flyer-bg.jpeg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E3A8A))),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Create ${_role[0].toUpperCase()}${_role.substring(1)} Account', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  Row(children: [
                    _buildRoleButton('admin', Icons.security, 'Admin', Colors.blue.shade700),
                    const SizedBox(width: 8),
                    _buildRoleButton('delivery', Icons.local_shipping, 'Delivery', Colors.orange.shade600),
                    const SizedBox(width: 8),
                    _buildRoleButton('customer', Icons.group, 'Customer', Colors.green.shade700),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Full Name',
                      prefixIcon: const Icon(Icons.badge_outlined, color: Colors.blue),
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Mobile Number',
                      prefixIcon: const Icon(Icons.phone_android, color: Colors.blue),
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.blue),
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    ),
                  ),
                  if (_role == 'customer') ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _wingController,
                          decoration: InputDecoration(
                            hintText: 'Wing',
                            prefixIcon: const Icon(Icons.domain, color: Colors.blue),
                            filled: true, fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _houseNoController,
                          decoration: InputDecoration(
                            hintText: 'House No',
                            prefixIcon: const Icon(Icons.home, color: Colors.blue),
                            filled: true, fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _societyController,
                      decoration: InputDecoration(
                        hintText: 'Society Name',
                        prefixIcon: const Icon(Icons.location_city, color: Colors.blue),
                        filled: true, fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      decoration: InputDecoration(
                        hintText: 'Full Address',
                        prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.blue),
                        filled: true, fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _handleSignup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Already have an account? ', style: TextStyle(fontSize: 14)),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                      child: const Text('Login', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildRoleButton(String id, IconData icon, String label, Color activeColor) {
    final isSelected = _role == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? activeColor : Colors.grey.shade300),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.grey.shade500),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600)),
          ]),
        ),
      ),
    );
  }
}
