import 'dart:math' as math;
import 'package:flutter/material.dart';

const Color _puckBlue = Color(0xFF2563EB);

/// The user's location: a white-ringed blue dot with a soft cone toward
/// [heading] (true degrees). Without a compass, only the dot is drawn.
///
/// Map markers turn with the map, so the cone stays true on a rotated map.
class LocationPuck extends StatelessWidget {
  final double? heading;
  const LocationPuck({super.key, this.heading});

  @override
  Widget build(BuildContext context) {
    final heading = this.heading;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (heading != null)
          Positioned.fill(
            child: Transform.rotate(
              angle: heading * math.pi / 180,
              child: const CustomPaint(
                key: ValueKey('location-heading-cone'),
                painter: _HeadingConePainter(),
              ),
            ),
          ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _puckBlue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }
}

/// A cone pointing up from the centre, fading out toward its edge.
class _HeadingConePainter extends CustomPainter {
  const _HeadingConePainter();

  static const double _spread = 70 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          _puckBlue.withValues(alpha: 0.55),
          _puckBlue.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, -math.pi / 2 - _spread / 2, _spread, false)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HeadingConePainter oldDelegate) => false;
}
