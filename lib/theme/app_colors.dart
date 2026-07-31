import 'package:flutter/material.dart';

/// The single source of truth for Adhani's palette.
///
/// Mirrors `DESIGN_IDENTITY.md` §1 exactly — when a value changes there, it
/// changes here, and nowhere else. Introduced because the same hexes were
/// being hand-typed across five screens, which is how `Colors.white70` and
/// three different reds crept in before.
abstract final class AppColors {
  // ── Backgrounds — navy ────────────────────────────────────────────────
  /// Mid navy — the main surface the app sits on.
  static const surface = Color(0xFF0A2740);

  /// Top of the radial glow.
  static const glowTop = Color(0xFF12405C);
  static const glowTopSoft = Color(0xFF154762);

  /// Bottom fade.
  static const bottomFade = Color(0xFF061726);
  static const bottomDeep = Color(0xFF05131F);

  /// Bottom-sheet / dialog gradient pair.
  static const sheetTop = Color(0xFF123A55);
  static const sheetBottom = Color(0xFF0B2740);

  /// Scrim behind a dialog — rgba(3,10,17,.62).
  static const scrim = Color(0x9E030A11);

  // ── Surfaces (translucent, over the background) ───────────────────────
  /// Cards & rows: rgba(255,255,255,.045) fill, .06 border.
  static const cardFill = Color(0x0BFFFFFF);
  static const cardBorder = Color(0x0FFFFFFF);

  /// Tab bar, icon buttons: rgba(255,255,255,.07).
  static const barFill = Color(0x12FFFFFF);

  // ── Light dial / clock panel ──────────────────────────────────────────
  /// "Arch" gradient for the light card.
  static const archTop = Color(0xFFF5F9FC);
  static const archMid = Color(0xFFE2ECF3);
  static const archBottom = Color(0xFFCFDEE9);

  /// Compass dial face.
  static const dialFace = Color(0xFFF1F7FB);

  /// Clock hands, dial numerals.
  static const onLight = Color(0xFF0E2F47);
  static const onLightAlt = Color(0xFF12354F);

  /// Secondary text on light surfaces.
  static const onLightSecondary = Color(0xFF5B7E97);

  // ── Accent — cyan ─────────────────────────────────────────────────────
  static const accent = Color(0xFF7AD2F7);
  static const accentDeep = Color(0xFF3FA3D8);

  /// Tinted accent fills (.12–.22) and borders (.28–.45).
  static const accentFillSoft = Color(0x1F7AD2F7);
  static const accentFill = Color(0x387AD2F7);
  static const accentBorderSoft = Color(0x477AD2F7);
  static const accentBorder = Color(0x737AD2F7);

  // ── Text (on dark surfaces) ───────────────────────────────────────────
  static const heading = Color(0xFFFFFFFF);
  static const body = Color(0xFFE6F1F9);
  static const bodyAlt = Color(0xFFDCEAF5);
  static const secondary = Color(0xFFC6DBEA);
  static const muted = Color(0xFFA9C3D6);
  static const label = Color(0xFF8BA7BD);
  static const faint = Color(0xFF7D97AD);
  static const inactive = Color(0xFF6B869C);

  // ── Status ────────────────────────────────────────────────────────────
  /// Countdown / urgency, and the compass north needle.
  static const danger = Color(0xFFFF6B5E);
  static const dangerDeep = Color(0xFFFF5D52);

  /// Aligned with Qibla / alarm working.
  static const success = Color(0xFF5FE08E);

  /// Same hue, darkened — for a solid fill that has to carry white content
  /// on top of it (the toast's confirmation badge). The mint above is too
  /// light to sit a white glyph on. Mirrors the accent/accentDeep and
  /// danger/dangerDeep pairing rather than introducing a new hue.
  static const successDeep = Color(0xFF34B26C);

  /// Warnings, rating star. Reserved — not yet used.
  static const warning = Color(0xFFFFC46B);
}
