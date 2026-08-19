// =============================================================================
// WEB FRAME WRAPPER
// lib/widgets/web_frame_wrapper.dart
//
// UPDATED:
// - No fake mobile phone frame
// - No fixed 412 x 870 size
// - No fake status bar
// - Full-screen responsive layout
// - Works naturally on laptop, desktop, tablet and mobile
// =============================================================================

import 'package:flutter/material.dart';

class WebFrameWrapper extends StatelessWidget {
  final Widget child;

  const WebFrameWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // The application now uses the complete available screen.
    //
    // No fixed width.
    // No fixed height.
    // No phone border.
    // No artificial status bar.
    //
    // Flutter automatically adapts the child to:
    // - Laptop
    // - Desktop
    // - Tablet
    // - Android
    // - iPhone
    // - Flutter Web

    return SizedBox.expand(
      child: child,
    );
  }
}