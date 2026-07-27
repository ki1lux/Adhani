# Design System — Adhani

**This is how we build UI.**

This document is the practical rulebook for composing screens and
components. It's grounded in what the codebase actually does most often —
picking one canonical pattern where several currently compete — not
invented from scratch.

How this relates to the other two docs:
- **`DESIGN_IDENTITY.md`** — the brand: locked color roles, icon/logo style,
  the Cairo typeface, the corner-radius scale. *What must not change.*
- **`DESIGN_SYSTEM.md`** (this file) — the patterns for turning those tokens
  into actual screens: spacing, components, state handling, navigation,
  layout rules. *How to build with the tokens.*
- **`CLAUDE.md`** — the architecture: Riverpod providers, the native
  Kotlin backend, the shared-storage contract. *How the app works underneath.*

When they conflict, `DESIGN_IDENTITY.md` wins on anything it defines (colors,
fonts, radii); this document governs everything else.

## 1. Spacing scale

Canonical scale (derived from the padding/margin values already dominant in
`lib/view/`):

| Token | Value | Use |
|---|---|---|
| `xs` | `4` | Tight gaps (icon-to-label, inline chips) |
| `sm` | `8` | Compact padding, small gaps |
| `md` | `12` | Default control/card padding (most common value in the codebase) |
| `lg` | `16` | Section padding, standard horizontal margins |
| `xl` | `20` | Card/sheet padding |
| `xxl` | `24` | Generous section spacing, dialog padding |
| `xxxl` | `32` | Screen-edge horizontal margins on key CTAs |

Rules:
- New spacing values come from this scale. Don't reach for an arbitrary
  number because it "looks right" in one spot.
- **Never derive spacing from `MediaQuery.sizeOf(context).height/width * 0.0X`.**
  This pattern exists in a couple of places today (flagged in
  `PrayerHome_UI_AUDIT.md` #3) and is drift, not a pattern to repeat — it
  produces a different rhythm on every device size for no design reason.
  Use the fixed scale above, and let `Expanded`/`Flexible`/`SafeArea` absorb
  the difference between device sizes instead of a hand-computed percentage.
- One-off values below 4 or between scale steps (e.g. a lone `6`, `13`, `15`,
  `18`, `22`, `28` seen in a few places) are drift to reconcile onto the
  scale when that code is next touched, not additional canonical values.

## 2. Corner radius

Use `DESIGN_IDENTITY.md` §4 as-is: `{12, 24, 36}` for rectangular surfaces,
fully circular (or `Radius.circular(70)`) for dial/badge-style elements.
Don't introduce a new radius value without checking that scale first.

## 3. Color

Use `DESIGN_IDENTITY.md` §1 for the palette and role meanings. Two rules on
top of that for day-to-day component building:

- **Pull the literal hex from `DESIGN_IDENTITY.md`, not a `Colors.*`
  shortcut.** `Colors.white` / `Colors.white70` / `Colors.white60` show up
  throughout the view layer standing in for `#F0F8FF` and its opacity tiers.
  They render close enough to pass a glance, but they're not the documented
  token, and they silently ignore the "derive muted/highlight states via
  opacity on the primary content color" rule (`DESIGN_IDENTITY.md` §1). New
  code should use `#F0F8FF` (+ the `66`/`1A` alpha tiers) directly.
- **Dialogs/sheets use `#0E2031`.** `AlertDialog` backgrounds currently vary
  between `#0E2031`, `#2D4356`, and `#0A2239` across `SettingsScreen.dart`
  and `PrayerTimeScreen.dart`. `#0E2031` is both the most common of the three
  today and it's the hex `DESIGN_IDENTITY.md` already assigns the "elevated
  dark surface... sheets sitting on top of the base surface" role to — i.e.
  it's the semantically-correct one. New dialogs/bottom sheets should use it;
  existing `#2D4356`/`#0A2239` dialogs are drift to converge when touched.

## 4. Typography

Follow `DESIGN_IDENTITY.md` §3: Cairo everywhere, both scripts, no second
Latin font.

- **Canonical casing: `'cairo'` (all lowercase)** — matching exactly how it's
  registered in `pubspec.yaml` (`family: cairo`). Copy that string, don't
  retype it; `'Cairo'` is the drift form seen in some screens.
- **Type scale** (from the sizes already dominant in the codebase — don't
  add a new size without a reason):

  | Role | Size |
  |---|---|
  | Caption / meta | `12` |
  | Secondary body | `14` |
  | Body / default | `16` (by far the most common size in the app — the default for anything not explicitly a heading) |
  | Headline / title | `24` |

  Large one-off display type (the Home tab's digital clock, splash screen
  branding) is allowed to sit outside this scale since it's a single
  hero element per screen, not a body-text style — but per
  `PrayerHome_UI_AUDIT.md` #5, any size derived from `MediaQuery` width must
  still be clamped and should account for the platform text-scale factor.

## 5. Motion

Durations and curves, taken from what's already repeated across the app
(splash screen's bespoke multi-second intro choreography is a one-off and
exempt — it's not a reusable interaction pattern):

| Token | Value | Use |
|---|---|---|
| Fast | `150ms` | Small state toggles (row highlight/press feedback) |
| Standard | `200–300ms` | Icon/scale feedback, dialog and sheet transitions |
| Screen cross-fade | `350ms` | Top-level tab transitions (`FadeIndexedStack`'s default) |

- Default curve: **`Curves.easeInOut`** for cross-fades and transitions.
- Default curve for snappy feedback (press/select scale): **`Curves.easeOut`**
  — matches the existing bottom-nav selection animation.
- Don't introduce a third curve family (e.g. `elasticOut`, `bounceOut`) for
  routine UI feedback; reserve expressive curves for one-off moments like the
  splash screen, not recurring components.

## 6. Component patterns

- **Buttons:** no shared button theme exists yet (`ThemeData` in `main.dart`
  only sets `scaffoldBackgroundColor`/`canvasColor`/`pageTransitionsTheme` —
  no `elevatedButtonTheme`). Every screen currently hand-styles
  `ElevatedButton.styleFrom(...)` independently, and the results vary
  (`Colors.white24`, `Colors.white.withValues(alpha: 0.05)`, `#4DB3E5`, plain
  white). When adding a button, styleFrom with `radius: 12` (§2) and a color
  from `DESIGN_IDENTITY.md` §1 — don't invent a new translucent white tint
  per screen.
- **Dialogs:** `AlertDialog` with `backgroundColor: #0E2031` (§3), radius
  `12` or `24` depending on size (§2).
- **List rows** (the `PrayerTimeScreen` pattern): a rounded (`12`) container,
  background highlight for the "active/next" row using the `#4DB3E5`/opacity
  treatment, muted (`#F0F8FF` at ~40% alpha) for "already passed" rows. This
  is the reference pattern for any future list of similar "one of these is
  current" items — reuse it rather than inventing a new selected-state
  language.
- **Bottom navigation:** the 4-tab bar in `main.dart` (`_buildBottomNav`) is
  the one and only navigation chrome — see §8. Don't add a second nav
  paradigm (e.g. a drawer, a top tab bar) without a strong reason.
- **Snackbars:** `SnackBar` with `shape: RoundedRectangleBorder(radius: 12)`,
  `SnackBarBehavior.floating`. Keep using this for transient confirmations
  rather than introducing toast-style overlays.

## 7. Async state handling

Every screen or widget backed by a Riverpod `AsyncValue` (the app's standard
async pattern — `prayerTimesProvider` and friends) must implement all three
branches of `.when(loading:, error:, data:)` **meaningfully**, not just
structurally:

- `loading` — a visible loading affordance (or last-known-cached content,
  as `adhan_screen.dart` does for the Hijri date).
- `error` — a **visible, distinct state**, not silently reused as if it were
  `loading`. `PrayerHome_UI_AUDIT.md` #9 documents a screen where `error`
  falls through to the same rendering as `loading` and can produce a blank
  region with no indication anything went wrong. Don't repeat that: give
  `error` its own message/retry affordance.
- `data` — the normal render path.

## 8. Navigation pattern

Top-level sections are **tabs, not routes**: `MainScreen` holds all 4 screens
alive simultaneously in a custom `FadeIndexedStack` (a state-preserving
cross-fade alternative to `IndexedStack`, in `main.dart`), switched via the
bottom nav — there is no `Navigator`/named-route flow for the main app
sections. If you're adding a new top-level section, add it to that stack +
nav bar, don't introduce a route.

`Navigator.push`/`showDialog`/`showModalBottomSheet` are for secondary,
transient UI within a tab (settings sub-dialogs, pickers) — not for
top-level navigation.

## 9. Layout & responsiveness

- **Wrap screen content in `SafeArea`** unless there's a specific reason not
  to (e.g. a deliberate edge-to-edge background). `PrayerHome_UI_AUDIT.md`
  #11 documents a screen built entirely from manual
  `Positioned(top: -(height * 0.05), ...)` math with no `SafeArea` — don't
  add more of that pattern.
- Size elements from layout constraints (`Expanded`, `Flexible`,
  `LayoutBuilder`, `AspectRatio`) rather than hard-coded
  `MediaQuery.sizeOf(context).width/height` percentages, especially for
  anything that has to hold up on a tablet or a small/older phone.
- See §1 for why percentage-of-screen spacing is out.

## 10. RTL & localization

The app's content is Arabic-first throughout, but there is currently **no
app-wide `Directionality`/`locale` configuration** in `MaterialApp`
(`lib/main.dart`) — RTL is handled ambient/implicitly via Unicode bidi
auto-detection, with at least one place manually forcing
`textDirection: TextDirection.rtl` on a single `Text` widget
(`PrayerHome_UI_AUDIT.md` #12).

- **Don't add more per-widget `textDirection` overrides.** That's a
  workaround for the missing app-wide configuration, not a pattern to
  extend — it papers over one symptom without fixing the cause.
- Avoid mixing scripts in one string where an Arabic-locale convention
  exists (e.g. prefer 24-hour time or Arabic AM/PM markers over Latin
  "AM/PM" — `PrayerHome_UI_AUDIT.md` #13).
- Treat proper app-wide RTL configuration as a prerequisite piece of
  architecture work, not something to solve one screen at a time.

## 11. Accessibility baseline

- Minimum touch target: **48×48dp** (the existing bottom nav already clears
  this comfortably — match it, don't shrink below it).
- Any custom-painted or decorative content that conveys information
  (not purely ornamental) needs a `Semantics` label — screen readers get
  nothing from a bare `CustomPaint`.
- Don't size body/interactive text purely from device width
  (`MediaQuery.sizeOf(context).width * 0.0X`) without a cap — it bypasses the
  user's OS text-scale setting, which is the actual accessibility signal to
  respect.
- Maintain WCAG contrast minimums (4.5:1 for text, 3:1 for meaningful
  non-text graphics) for anything other than intentionally decorative
  texture — check new color pairings against `DESIGN_IDENTITY.md`'s palette,
  don't assume two "light" or two "dark" tokens are automatically legible
  together.

## 12. Reuse before you build

Before writing new state or a new widget, check whether it already exists —
this codebase has a history of the same logic being built once and used in
only one place when it could serve more:

- Need "next prayer + live countdown"? Use `CountdownTimer`
  (`lib/view/CountDown.dart`) + `prayerTimesProvider`
  (`lib/providers/prayer_times_provider.dart`) — don't rebuild the countdown
  math (Iqamah-phase handling included).
- Need prayer time data at all? It comes from `prayerTimesProvider`. Don't
  read `SharedPreferences` prayer keys directly from a new widget — see
  `CLAUDE.md`'s shared-storage contract for why those keys are sensitive to
  get wrong, and let the provider be the single Dart-side source of truth.
- Check `lib/view/` for an existing screen using a similar pattern (list row,
  dialog, countdown) before styling a new one from scratch.

## Known drift to reconcile (not additional canon)

Called out throughout this document, collected here for visibility:
spacing values outside the §1 scale; `AlertDialog` backgrounds other than
`#0E2031`; ad hoc button colors instead of a shared style; `'Cairo'`
(capitalized) instead of `'cairo'`; per-widget `textDirection` overrides.
None of these are "the way we do it" — they're the gap between current code
and this document, to close opportunistically as each area is touched.
