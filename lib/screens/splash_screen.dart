import 'package:flutter/material.dart';
import 'dart:js_interop';
import 'login_screen.dart';

// Bridges to the hideAppSplash() function defined in web/script.js.
// Calling this is what tells your HTML farm/cow splash it's safe
// to fade out — it does NOT happen automatically on first frame.
@JS('hideAppSplash')
external void _hideAppSplash();

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startApp();
  }

  Future<void> _startApp() async {
    // ---- REAL LOADING WORK GOES HERE ----
    // Your HTML splash (index.html) stays fully visible, with its
    // progress bar and animation running, for the entire time this
    // takes. Replace the placeholder delay with your actual checks:
    //
    // await AuthService.checkSession();
    // await DatabaseService.init();
    // await BillingService.preload();
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // Tell the HTML splash loading is genuinely done NOW.
    try {
      _hideAppSplash();
    } catch (_) {
      // Ignore if running outside a browser (e.g. during tests).
    }

    // Small buffer so the splash's own fade-out (500ms in script.js)
    // has time to finish before the login page appears underneath.
    await Future.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same navy as the HTML splash background — invisible seam
    // underneath it while it's still showing.
    return const Scaffold(
      backgroundColor: Color(0xFF0D1B2A),
      body: SizedBox.shrink(),
    );
  }
}