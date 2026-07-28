import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

/// Adhani's shared canvas: the navy glow gradient plus the Islamic
/// geometric pattern overlay.
///
/// Consolidates the "flat `#0A2239` `Container` + full-bleed `Vector.svg`"
/// recipe that each screen used to re-implement itself. The glow (lighter
/// navy at the top easing into near-black at the bottom) gives the app depth
/// without any screen owning gradient math.
///
/// **To change the decoration, change it here** — this is the only place the
/// pattern is defined, so every screen follows automatically.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  // Top of the radial glow → mid navy (the base surface) → bottom fade.
  static const _glowTop = Color(0xFF12405C);
  static const _glowTopSoft = Color(0xFF154762);
  static const _midNavy = Color(0xFF0A2740);
  static const _bottomFade = Color(0xFF061726);
  static const _bottomDeep = Color(0xFF05131F);

  /// How strongly the geometric pattern reads. The design brief calls for a
  /// ~3.5% overlay; nudge this if the tiling feels too faint or too busy.
  static const _patternOpacity = 0.05;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // Expand, don't shrink-wrap. With the default loose fit the Stack
      // sizes itself to its non-positioned child — and on a screen whose
      // content ends in a SingleChildScrollView shorter than the viewport,
      // that collapsed the whole background to the content's height, leaving
      // bare Scaffold color below it.
      fit: StackFit.expand,
      children: [
        // Base vertical fade: glow at the top, deep navy at the bottom.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _glowTopSoft,
                  _midNavy,
                  _bottomFade,
                  _bottomDeep,
                ],
                stops: [0.0, 0.38, 0.82, 1.0],
              ),
            ),
          ),
        ),
        // Radial hotspot near the top so the glow reads as light falling
        // from above rather than a flat linear ramp.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.85),
                radius: 1.1,
                colors: [_glowTop, Color(0x0012405C)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        // Islamic geometric pattern overlay (assets/Vector.svg — a girih-style
        // tiling). Tinted white at low opacity rather than drawn in its own
        // baked-in dark navy, so it stays evenly visible across the whole
        // gradient instead of disappearing into the dark bottom half.
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: _patternOpacity,
              child: SvgPicture.asset(
                'assets/Vector.svg',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
