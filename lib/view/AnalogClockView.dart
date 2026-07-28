import 'dart:math';
import 'package:flutter/material.dart';
import 'package:myadhan/controller/ClockController.dart';
import 'package:myadhan/model/ClockModel.dart';
import 'package:myadhan/theme/app_colors.dart';

/// A purely decorative analog clock face. The digital time is not rendered
/// here — a parent renders its own accessible time text via [onTick], so
/// screen readers get one clear spoken time instead of two competing ones.
class Analogclockview extends StatefulWidget {
  final double size;
  final ValueChanged<DateTime>? onTick;

  const Analogclockview({super.key, required this.size, this.onTick});

  @override
  _AnalogclockviewState createState() => _AnalogclockviewState();
}

class _AnalogclockviewState extends State<Analogclockview> {
  late ClockModel model;
  late ClockController controller;

  @override
  void initState() {
    super.initState();
    model = ClockModel(DateTime.now());
    controller = ClockController(
      onTick: (newModel) {
        if (!mounted) return;
        setState(() => model = newModel);
        widget.onTick?.call(newModel.time);
      },
    );
    // Fire once immediately so a parent's digital time isn't blank on the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onTick?.call(model.time);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Decorative — the parent's digital time text is the accessible source
    // of truth for the current time, so this doesn't need its own label.
    return ExcludeSemantics(
      child: CustomPaint(
        painter: ClockPainter(model),
        size: Size(widget.size, widget.size),
      ),
    );
  }
}

class ClockPainter extends CustomPainter {
  final ClockModel degree;

  ClockPainter(this.degree);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Radius is most of the canvas half-width, leaving just enough margin
    // for the tick marks not to clip at the edge. Previously this divided
    // by 3.5, a leftover from when this widget was always given the full
    // device width as its canvas — that made the visible dial only ~57% of
    // whatever size was passed in, so callers had to over-size the widget
    // to compensate. Now `size` maps directly and predictably to the
    // visible clock diameter.
    final radius = size.width / 2.2;

    final paintCircle =
        Paint()
          ..color = AppColors.archBottom
          ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius / 2, paintCircle);

    // علامات الساعة — darkened relative to the original flat #D3E0EC so they
    // stay legible against the light card (previous contrast was ~1.25:1).
    final tickPaint =
        Paint()
          ..color = AppColors.onLight.withValues(alpha: 0.35)
          ..strokeWidth = 3.3;

    for (int i = 0; i < 60; i++) {
      final angle = 2 * pi * i / 60;
      final outer = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final inner = Offset(
        center.dx + (radius - 8) * cos(angle),
        center.dy + (radius - 8) * sin(angle),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    // عقرب الساعات
    final hourAngle = degree.hourAngle;
    final hourHand = Offset(
      center.dx + radius * 0.5 * cos(hourAngle - pi / 2),
      center.dy + radius * 0.5 * sin(hourAngle - pi / 2),
    );
    final hourPaint =
        Paint()
          ..color = AppColors.onLight
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, hourHand, hourPaint);

    // عقرب الدقائق
    final minuteAngle = degree.minuteAngle;
    final minuteHand = Offset(
      center.dx + radius * 0.8 * cos(minuteAngle - pi / 2),
      center.dy + radius * 0.8 * sin(minuteAngle - pi / 2),
    );
    final minutePaint =
        Paint()
          ..color = AppColors.onLight
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, minuteHand, minutePaint);



    // عقرب الثواني
    final secondAngle = degree.second;
    final secondHand = Offset(
      center.dx + radius * cos(secondAngle - pi / 2),
      center.dy + radius * sin(secondAngle - pi / 2),
    );
    final secondPaint =
        Paint()
          ..color = AppColors.onLight
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;

    final tailLength = radius * 0.15;
    final secondHandTail = Offset(
      center.dx - tailLength * cos(secondAngle - pi / 2),
      center.dy - tailLength * sin(secondAngle - pi / 2),
    );
    canvas.drawLine(secondHandTail, secondHand, secondPaint);

    // دائرة في المنتصف
    final centerDot = Paint()..color = AppColors.onLight;
    canvas.drawCircle(center, 6.5, centerDot);
    final additionalCenterDot = Paint()..color = AppColors.archBottom;
    canvas.drawCircle(center, 3, additionalCenterDot);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
