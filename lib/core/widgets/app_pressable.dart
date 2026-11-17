import 'package:flutter/material.dart';
import '../app_motion.dart';

/// Keyboard focus, button semantics, and press feedback for branded artwork.
class AppPressable extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final BorderRadius borderRadius;

  const AppPressable({
    super.key,
    required this.onPressed,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: widget.borderRadius,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: AnimatedScale(
            scale: _pressed && !AppMotion.reduced(context) ? 0.98 : 1,
            duration: AppMotion.duration(context, AppMotion.quick),
            curve: AppMotion.curve,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: widget.child,
            ),
          ),
        ),
      );
}
