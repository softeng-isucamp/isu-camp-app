import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 140);
  static const entrance = Duration(milliseconds: 260);
  static const sheet = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration duration(BuildContext context, Duration normal) =>
      reduced(context) ? Duration.zero : normal;

  static void settleSheet(BuildContext context,
      DraggableScrollableController controller, double size) {
    if (!controller.isAttached) return;
    if (reduced(context)) {
      controller.jumpTo(size);
    } else {
      controller.animateTo(size, duration: sheet, curve: curve);
    }
  }

  /// A new touch takes ownership immediately, even during a snap animation.
  static void catchSheet(DraggableScrollableController controller) {
    if (controller.isAttached) controller.jumpTo(controller.size);
  }
}
