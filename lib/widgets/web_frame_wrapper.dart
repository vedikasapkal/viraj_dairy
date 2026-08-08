// =============================================================================
// WEB FRAME WRAPPER (lib/widgets/web_frame_wrapper.dart)
// Wraps the whole app in a fake phone frame when running on Flutter Web, so
// desktop browser testing still looks like a mobile app. Unchanged from the
// original — just relocated out of main.dart.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebFrameWrapper extends StatelessWidget {
  final Widget child;
  const WebFrameWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Container(
            width: 412,
            height: 870,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: const Color(0xFF334155), width: 10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 15))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Scaffold(backgroundColor: const Color(0xFFF8FAFC), body: Column(children: [
                Container(
                  height: 28,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                    Text('9:41', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                    Row(children: [
                      Icon(Icons.signal_cellular_alt, size: 14, color: Colors.black87),
                      SizedBox(width: 4),
                      Icon(Icons.wifi, size: 14, color: Colors.black87),
                      SizedBox(width: 4),
                      Icon(Icons.battery_full, size: 14, color: Colors.black87),
                    ]),
                  ]),
                ),
                Expanded(child: child),
              ])),
            ),
          ),
        ),
      );
    }
    return child;
  }
}
