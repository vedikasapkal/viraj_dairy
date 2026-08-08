// =============================================================================
// SPLASH ROUTER (lib/screens/splash_router.dart)
// Checks for an existing session on cold start and routes straight to the
// right dashboard instead of always showing Login. Unchanged logic.
// =============================================================================

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'login_screen.dart';
import 'admin_dashboard.dart';
import 'delivery_dashboard.dart';
import 'customer_dashboard.dart';

class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});
  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  final DatabaseService _db = DatabaseService();

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final session = await _db.getSession();
      if (!mounted) return;
      if (session == null) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        return;
      }
      final role = session['role'];
      if (role == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
      } else if (role == 'delivery') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DeliveryDashboard()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerDashboard()));
      }
    } catch (e) {
      debugPrint('SplashRouter session check error: $e');
      if (!mounted) return;
      // If session lookup fails for any reason, fall back to Login instead of
      // leaving the user stuck on the spinner forever.
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
