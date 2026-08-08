// =============================================================================
// LOGIN SCREEN (lib/screens/login_screen.dart)
// =============================================================================

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'admin_dashboard.dart';
import 'delivery_dashboard.dart';
import 'customer_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final DatabaseService _db = DatabaseService();
  String _role = 'customer';
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  Future<void> _handleLogin() async {
    final mobile = _mobileController.text.trim();
    final password = _passwordController.text.trim();

    if (mobile.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    setState(() => _loading = true);
    try {
      final profile = await _db.loginUser(role: _role, mobile: mobile, password: password);

      if (profile != null) {
        await _db.saveSession(mobile: mobile, role: _role);
        if (!mounted) return;
        _navigateToDashboard(_role);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No $_role account found for this mobile/password. Please signup first.')),
        );
      }
    } catch (e) {
      debugPrint('Login error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToDashboard(String role) {
    if (role == 'admin') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
    } else if (role == 'delivery') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DeliveryDashboard()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerDashboard()));
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
          child: Image.asset('assets/flyer-bg.jpeg', fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E3A8A), child: const Center(child: Icon(Icons.store, color: Colors.white, size: 64)))),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    _buildRoleButton('admin', Icons.security, 'Admin', Colors.blue.shade700),
                    const SizedBox(width: 8),
                    _buildRoleButton('delivery', Icons.local_shipping, 'Delivery', Colors.orange.shade600),
                    const SizedBox(width: 8),
                    _buildRoleButton('customer', Icons.group, 'Customer', Colors.green.shade700),
                  ]),
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.blue),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                      child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _role == 'delivery' ? Colors.orange.shade600 : _role == 'admin' ? const Color(0xFF1E3A8A) : Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Login as ${_role[0].toUpperCase()}${_role.substring(1)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 20),
                  if (_role != 'admin')
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('New here? ', style: TextStyle(fontSize: 14)),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SignupScreen(initialRole: _role))),
                        child: const Text('Create an account', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 14)),
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
