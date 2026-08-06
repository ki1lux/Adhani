import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myadhan/theme/app_colors.dart';

/// Adhani's shared "this is the active/next one" visual treatment: an
/// asymmetric-radius card with a thin accent edge and a slow breathing
/// glow. Originally built for the Home screen's `NextPrayerCard`; extracted
/// here so the prayer list's next-prayer row can share the exact same
/// visual language instead of inventing a second one for the same concept.
class AccentCard extends StatefulWidget {
  final Widget child;
  final Color color;
  final Color accentColor;
  final BorderRadius borderRadius;
  final double accentEdgeWidth;

  const AccentCard({
    super.key,
    required this.child,
    this.color = AppColors.cardFill,
    this.accentColor = AppColors.accent,
    this.borderRadius = const BorderRadius.only(
      topLeft: Radius.circular(36),
      topRight: Radius.circular(12),
      bottomLeft: Radius.circular(12),
      bottomRight: Radius.circular(36),
    ),
    this.accentEdgeWidth = 4,
  });

  @override
  State<AccentCard> createState() => _AccentCardState();
}

class _AccentCardState extends State<AccentCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // A slow, low-amplitude breathing pulse — a calm "alive" presence
    // rather than a mechanical tick.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The glow repaints every frame forever — isolate it in its own
    // compositor layer so that continuous animation never forces
    // neighboring widgets (other list rows, a dialog opening on top) to
    // redo unrelated painting work.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final glow = 0.12 + (_pulseController.value * 0.14);
          return Container(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: widget.borderRadius,
              border: Border.all(color: AppColors.accentBorderSoft),
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: glow),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          // Thin accent edge on the RTL leading (right) side — a spatial
          // "this is the active one" cue, not just text/background colour.
          //
          // Painted as a stroke that follows the card's own corner radii
          // rather than a straight `Positioned` strip. The strip was a plain
          // rectangle that `ClipRRect` sliced flat wherever the corner curved
          // away from it, so on the 36px bottom-right corner it ended in a
          // blunt diagonal cut that visibly didn't belong to the card's
          // silhouette. Tracing the edge means it wraps into both corners and
          // reads as part of the outline.
          child: CustomPaint(
            painter: _AccentEdgePainter(
              borderRadius: widget.borderRadius,
              color: widget.accentColor,
              maxWidth: widget.accentEdgeWidth,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Draws the card's leading (RTL right) edge as a blade that follows the
/// corner radii and tapers to a point inside each corner.
///
/// The taper is pinned to the corner arcs rather than to a share of the whole
/// edge: the straight run between the corners stays at full [maxWidth], and
/// the narrowing happens only where the edge is actually curving away. That
/// keeps the bar solid where it reads as a bar, and lets it vanish into the
/// silhouette exactly where the card turns — which also means the two ends
/// taper over different lengths, because the corners have different radii.
///
/// The taper is why this is a **filled shape** and not a stroke: a stroke has
/// one width for its whole path, and any cap it offers — butt, round, square —
/// is still that same width at the tip.
///
/// The outline is built by walking the edge with [PathMetric], and at each
/// step stepping inward along the surface normal by the tapered width. The
/// outer samples run forwards and the inner samples backwards, closing into a
/// single polygon that pinches shut at both tips.
class _AccentEdgePainter extends CustomPainter {
  final BorderRadius borderRadius;
  final Color color;
  final double maxWidth;

  const _AccentEdgePainter({
    required this.borderRadius,
    required this.color,
    required this.maxWidth,
  });

  /// One sample per this many logical pixels. The curve only has to survive
  /// being looked at, and the polygon is rebuilt only when the card resizes.
  static const _pixelsPerSample = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || maxWidth <= 0) return;

    final edge = _edgePath(size);
    final metrics = edge.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final length = metric.length;
    if (length <= 0) return;

    // Where each corner arc ends, as a fraction of the edge's length. A
    // quarter-circle of radius r is (π/2)·r long, so these come straight out
    // of the geometry — no tuning constant, and they track the card's own
    // radii if those ever change.
    final topRadius = _topRadius(size);
    final bottomRadius = _bottomRadius(size);
    final topArc = topRadius * math.pi / 2;
    final bottomArc = bottomRadius * math.pi / 2;
    final straight = math.max(0.0, size.height - topRadius - bottomRadius);
    final total = topArc + straight + bottomArc;
    if (total <= 0) return;

    final taperInEnd = topArc / total;
    final taperOutStart = (topArc + straight) / total;

    // Outer samples sit on the card's edge; inner ones are pushed in by the
    // tapered width. Collected separately so the inner run can be reversed to
    // close the polygon.
    final sampleCount = (length / _pixelsPerSample).ceil().clamp(24, 400);
    final outer = <Offset>[];
    final inner = <Offset>[];

    for (var i = 0; i <= sampleCount; i++) {
      final t = i / sampleCount;
      final tangent = metric.getTangentForOffset(t * length);
      if (tangent == null) continue;

      // Rotating the unit tangent a quarter turn gives the inward normal:
      // travelling clockwise down the right-hand edge, (x, y) → (-y, x)
      // always points back into the card.
      final vector = tangent.vector;
      final normal = Offset(-vector.dy, vector.dx);

      final width = maxWidth * _taperAt(t, taperInEnd, taperOutStart);
      outer.add(tangent.position);
      inner.add(tangent.position + normal * width);
    }

    if (outer.length < 2) return;

    // One closed subpath, not two. `addPolygon` begins a fresh subpath on each
    // call, so adding the outer and inner runs separately would fill them as
    // two independent slivers rather than as the region between them.
    final blade = Path()
      ..addPolygon([...outer, ...inner.reversed], true);

    canvas.drawPath(
      blade,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  /// Width multiplier at position [t] along the edge.
  ///
  /// Rises from 0 at the top tip across the top corner arc, holds at full
  /// width along the straight run, then falls back to 0 across the bottom
  /// corner arc. [taperInEnd] and [taperOutStart] are where those arcs end and
  /// begin, as fractions of the edge's length.
  ///
  /// Smoothstepped rather than linear — a straight ramp leaves a visible
  /// crease where it meets full width.
  double _taperAt(double t, double taperInEnd, double taperOutStart) {
    double ramp;
    if (taperInEnd > 0 && t < taperInEnd) {
      ramp = t / taperInEnd;
    } else if (taperOutStart < 1 && t > taperOutStart) {
      ramp = (1 - t) / (1 - taperOutStart);
    } else {
      return 1.0;
    }
    final x = ramp.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// Corner radii, clamped so two big corners on a short card can't overlap
  /// into a path that doubles back on itself.
  double _topRadius(Size size) =>
      math.min(borderRadius.topRight.x, size.height / 2);

  double _bottomRadius(Size size) =>
      math.min(borderRadius.bottomRight.x, size.height / 2);

  /// The card's right-hand outline: into the top-right corner, down the
  /// straight edge, and around the bottom-right corner.
  Path _edgePath(Size size) {
    final right = size.width;
    final topRadius = _topRadius(size);
    final bottomRadius = _bottomRadius(size);

    final path = Path()..moveTo(right - topRadius, 0);

    if (topRadius > 0) {
      path.arcToPoint(
        Offset(right, topRadius),
        radius: Radius.circular(topRadius),
        clockwise: true,
      );
    }

    path.lineTo(right, size.height - bottomRadius);

    if (bottomRadius > 0) {
      path.arcToPoint(
        Offset(right - bottomRadius, size.height),
        radius: Radius.circular(bottomRadius),
        clockwise: true,
      );
    }

    return path;
  }

  @override
  bool shouldRepaint(_AccentEdgePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.borderRadius != borderRadius;
}
