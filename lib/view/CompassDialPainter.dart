import 'dart:math';
import 'package:flutter/material.dart';

/// Draws the compass face itself — outer ring, degree ticks, N/E/S/W labels
/// — entirely in Flutter instead of a static SVG. It's painted in a fixed
/// "north at the top" frame; the caller wraps it in the same
/// `AnimatedRotation` that used to spin `assets/test.svg`, so rotating this
/// canvas is exactly equivalent to rotating that image was.
class CompassRingPainter extends CustomPainter {
  final Color fillColor;
  final Color ringColor;
  final Color tickColor;
  final Color labelColor;
  final Color cardinalColor;

  const CompassRingPainter({
    required this.fillColor,
    required this.ringColor,
    required this.tickColor,
    required this.labelColor,
    required this.cardinalColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius - 1, Paint()..color = fillColor);

    final ringPaint =
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius - 1, ringPaint);

    _drawDashedCircle(canvas, center, radius * 0.76, tickColor.withValues(alpha: 0.35));

    for (int deg = 0; deg < 360; deg += 10) {
      final isMajor = deg % 30 == 0;
      final angleRad = (deg - 90) * pi / 180;
      final direction = Offset(cos(angleRad), sin(angleRad));

      final outerPoint = center + direction * (radius - 4);
      final innerPoint = center + direction * (radius - (isMajor ? 15 : 8));
      canvas.drawLine(
        outerPoint,
        innerPoint,
        Paint()
          ..color = isMajor ? tickColor : tickColor.withValues(alpha: 0.5)
          ..strokeWidth = isMajor ? 2 : 1,
      );

      if (!isMajor) continue;

      String label;
      Color color;
      double fontSize;
      FontWeight weight;
      switch (deg) {
        case 0:
          label = 'N';
          color = cardinalColor;
          fontSize = 15;
          weight = FontWeight.bold;
          break;
        case 90:
          label = 'E';
          color = cardinalColor;
          fontSize = 15;
          weight = FontWeight.bold;
          break;
        case 180:
          label = 'S';
          color = cardinalColor;
          fontSize = 15;
          weight = FontWeight.bold;
          break;
        case 270:
          label = 'W';
          color = cardinalColor;
          fontSize = 15;
          weight = FontWeight.bold;
          break;
        default:
          label = '$deg';
          color = labelColor;
          fontSize = 11;
          weight = FontWeight.w600;
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
            fontFamily: 'cairo',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelPoint = center + direction * (radius - 30);
      textPainter.paint(
        canvas,
        labelPoint - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Color color) {
    const dashCount = 72;
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = (i / dashCount) * 2 * pi;
      final sweep = (2 * pi / dashCount) * 0.5;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CompassRingPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.cardinalColor != cardinalColor;
  }
}

/// The highlighted arc from the top (the fixed heading marker) around to the
/// Qibla marker's current position. Deliberately a separate, unrotated
/// overlay — the marker orbits the ring via its own rotation value, so the
/// arc reads that same value directly rather than being baked into the ring
/// (which rotates with the device heading instead).
class QiblaArcPainter extends CustomPainter {
  final double sweepDegrees;
  final Color color;

  const QiblaArcPainter({required this.sweepDegrees, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 2);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, sweepDegrees * pi / 180, false, paint);
  }

  @override
  bool shouldRepaint(covariant QiblaArcPainter oldDelegate) {
    return oldDelegate.sweepDegrees != sweepDegrees || oldDelegate.color != color;
  }
}
