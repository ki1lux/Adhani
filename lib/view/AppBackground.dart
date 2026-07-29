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
  static const _glowTopSoft = Color(0xFF0F3348);
  static const _midNavy = Color(0xFF0A2740);
  static const _bottomFade = Color(0xFF061726);
  static const _bottomDeep = Color(0xFF05131F);

  /// `Vector.svg` already bakes its own `<g opacity="0.51">` around every
  /// path and its own dark-navy fill — that's the exact recipe every screen
  /// used before this widget existed, and it read clearly against the navy
  /// background. Stacking an extra `Opacity`/`ColorFilter` on top of that
  /// (an earlier version of this file did) compounds the alpha down to a
  /// few percent and makes the tiling disappear — so don't add either here.

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
                radius: 0.65,
                // Kept in lockstep with _glowTopSoft (same base hue, same
                // darkening) rather than tuned per-screen — screens without
                // a light card covering the very top (PrayerTimeScreen,
                // Qibla) expose this hotspot directly, so darkening the one
                // shared color keeps every screen consistent instead of
                // forking the background per-screen.
                colors: [Color(0xB30F3348), Color(0x000F3348)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        // Islamic geometric pattern overlay (assets/Vector.svg — a girih-style
        // tiling). Drawn as-is, same as every screen did before this widget
        // existed — its own dark-navy fill and baked-in group opacity are
        // already tuned to read against this background.
        Positioned.fill(
          child: IgnorePointer(
            child: SvgPicture.asset(
              'assets/Vector.svg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
