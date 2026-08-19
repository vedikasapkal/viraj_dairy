// =============================================================================
// ANIMATED WIDGETS (lib/widgets/animated_widgets.dart)
// Reusable "3D" motion pieces used across the customer dashboard:
//   - Tilt3DCard   -> tilts/scales a card in 3D space on tap (Zomato-style press)
//   - StaggeredFadeIn -> fades + slides grid items in one after another
// =============================================================================

import 'package:flutter/material.dart';

/// Wraps [child] and gives it a subtle 3D tilt + depth-press animation
/// whenever the user taps it. The tilt direction follows where on the
/// card the user pressed, which is what makes it read as "3D" instead
/// of a flat scale-down.
class Tilt3DCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const Tilt3DCard({super.key, required this.child, this.onTap});

  @override
  State<Tilt3DCard> createState() => _Tilt3DCardState();
}

class _Tilt3DCardState extends State<Tilt3DCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Offset _tapOffset = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details, Size size) {
    if (size.width == 0 || size.height == 0) return;
    _tapOffset = Offset(
      (details.localPosition.dx / size.width) - 0.5,
      (details.localPosition.dy / size.height) - 0.5,
    );
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handleTapDown(d, size),
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              final rotateX = _tapOffset.dy * -0.35 * t;
              final rotateY = _tapOffset.dx * 0.35 * t;
              final scale = 1.0 - (0.05 * t);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0016) // perspective -> gives the tilt real depth
                  ..rotateX(rotateX)
                  ..rotateY(rotateY)
                  ..scale(scale),
                child: child,
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Fades + slides a grid/list item into place, delayed a little further
/// for each successive [index] so a whole grid animates in like a wave
/// instead of popping in all at once.
class StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int index;

  const StaggeredFadeIn({super.key, required this.child, required this.index});

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Cap the delay so long grids don't take forever to finish animating in.
    final delayMs = 35 * (widget.index % 12);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}