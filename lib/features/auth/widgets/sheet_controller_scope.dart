import 'package:flutter/material.dart';

/// A popped sheet remains mounted during its exit animation. Dispose its
/// controllers only when its widget tree is actually removed.
class SheetControllerScope extends StatefulWidget {
  const SheetControllerScope(
      {super.key, required this.controllers, required this.child});
  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<SheetControllerScope> createState() => _SheetControllerScopeState();
}

class _SheetControllerScopeState extends State<SheetControllerScope> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
