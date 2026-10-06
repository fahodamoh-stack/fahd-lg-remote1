import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// Press micro-interaction: 1.0 → 0.96 → 1.0 in ~200ms ease-out.
/// One-shot only — never loops, so tests always settle.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? radius;
  const Pressable({super.key, required this.child, this.onTap, this.radius});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? FaMotion.pressScale : 1.0,
        duration: FaMotion.micro,
        curve: FaMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// Staggered entrance: fade + slight rise, one-shot.
/// [index] staggers siblings by [FaMotion.staggerStep] each.
class Stagger extends StatefulWidget {
  final Widget child;
  final int index;
  const Stagger({super.key, required this.child, this.index = 0});

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> {
  bool _in = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(FaMotion.staggerStep * widget.index, () {
      if (mounted) setState(() => _in = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) return widget.child;
    return AnimatedOpacity(
      opacity: _in ? 1 : 0,
      duration: FaMotion.micro,
      curve: FaMotion.curve,
      child: AnimatedSlide(
        offset: _in ? Offset.zero : const Offset(0, 0.08),
        duration: FaMotion.micro,
        curve: FaMotion.curve,
        child: widget.child,
      ),
    );
  }
}
