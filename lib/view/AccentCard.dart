import 'package:flutter/material.dart';

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
    this.color = const Color(0xFF283F54),
    this.accentColor = const Color(0xFF4DB3E5),
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
          child: Stack(
            children: [
              // Thin accent edge on the RTL leading (right) side — a
              // spatial "this is the active one" cue, not just text/
              // background color.
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: Container(
                  width: widget.accentEdgeWidth,
                  color: widget.accentColor,
                ),
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}
