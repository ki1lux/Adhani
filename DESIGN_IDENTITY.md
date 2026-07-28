| `#5FE08E` | 🔒 | **Success / target-state reached.** Refines `#4DE599` (same role: "you got it"). Still not a general confirmation/success color for arbitrary snackbars or checkmarks — that discipline hasn't changed, only the hex. | `QiblaScreen.dart` (aligned with Qibla), `SettingsScreen.dart` (alarm scheduled/working) || `#FFC46B` | 🔒 | **Warning.** A fourth semantic hue. Now in use for the "scheduled for tomorrow" alarm state in Settings, paired against `#5FE08E` for "scheduled today / alarm working" — which is exactly the pairing this token was reserved for. | `SettingsScreen.dart` alarm-status list || `AccentCard`'s border, nav-bar selected glow || Nav bar selected pill, next-prayer row/card, active switches and radios || Dialog barriers || Dialogs (`AlertDialog` backgrounds use `sheetBottom`; `sheetTop` also carries snackbars) |# Design Identity — Adhani

This document is the brand contract for any UI redesign. It captures what makes
the app recognizably *this* app. Layouts, spacing, component structure, and
screen composition are free to change. The tokens below carry meaning (dark =
the app's "night sky" surface, the blue accent = "active/next prayer", red =
"directional marker") — that meaning, and the hue families that carry it, are
locked. Exact values within a locked family can still be refined (contrast,
accessibility, consolidating inconsistencies) — see the status key in §1. The
one deliberate exception is the blue accent, which is explicitly open to being
replaced with a better-performing hue as long as it keeps its role.

Everything here was extracted from the current codebase (not invented). Where
the code itself is inconsistent, that's called out explicitly so it isn't
mistaken for intentional identity.

## 1. Color

**Status key:**
- 🔒 **Locked family** — the hue and its role must survive. Refining the exact
  value (contrast, accessibility, consolidating inconsistent literals) is
  encouraged; replacing the hue or repurposing what it means is not.
- 🔁 **Open for replacement** — the *role* must survive, the hex does not.
  Currently only the blue accent.

**Rollout status:** ✅ **fully applied.** Every screen now reads its colors
from `lib/theme/app_colors.dart`, which mirrors this section one-for-one.
There are no remaining raw `Color(0x…)` literals or `Colors.white*` /
`Colors.red` / `Colors.green` shortcuts in `lib/` outside that token file
(plus one deliberate `Colors.white.withValues(alpha: .035)` for the pattern
overlay, and the splash screen's own glow/shadow alphas).

**Add or change a color in `app_colors.dart`, never inline in a widget** —
that file existing is what keeps this section honest.

### 1a. Backgrounds — navy family

The base surface is now a subtle vertical/radial glow rather than one flat
tone — a lighter navy easing into a darker one — instead of a single flat
`Container` color everywhere.

| Hex | Status | Role | Where |
|---|---|---|---|
| `#0A2740` | 🔒 | **Base surface.** The mid-navy the app sits on (refines the previous `#0A2239` — same hue, barely different value). | Scaffold background |
| `#12405C` / `#154762` | 🔒 | **Top of the background glow.** The lighter navy the base-surface gradient eases *from*, near the top of the screen. | New background-gradient recipe |
| `#05131F` / `#061726` | 🔒 | **Bottom of the background glow.** The darker navy the same gradient eases *into*, toward the bottom. | New background-gradient recipe |
| `#123A55` → `#0B2740` | 🔒 | **Bottom-sheet / dialog pair.** Replaces the old flat `#0E2031`. `sheetBottom` is the dialog background; `sheetTop` carries snackbars and the lighter end of any sheet gradient. | Both dialogs, all snackbars |
| `rgba(3,10,17,.62)` | 🔒 | **Dialog scrim.** Replaced `Colors.black54` as the barrier behind a dialog. | Dialog barriers |

**Translucent surfaces** (§ "Surfaces" in the brief) sit *on top of* the
background rather than replacing it — the old opaque `#283F54`/`#2D4356`
card tones are gone in favor of these:

| Value | Role | Where |
|---|---|---|
| `rgba(255,255,255,.045)` fill + `rgba(255,255,255,.06)` border | Cards & rows | Prayer rows, `AccentCard` |
| `rgba(255,255,255,.07)` | Tab bar, icon buttons | Bottom nav |
| White at ~5%, Islamic geometric tiling (`assets/Vector.svg`) | Pattern overlay | `AppBackground` |

**Applied:** every screen renders through the shared `AppBackground` widget
(`lib/view/AppBackground.dart`), which owns the linear fade, the radial
hotspot, and the pattern overlay. It consolidates the "flat `Container` +
full-bleed `Vector.svg`" pair each screen used to stack itself — `Vector.svg`
is still the decoration, just declared in one place now instead of three.

**The pattern is the identity's Islamic geometry, not a generic texture.**
`assets/Vector.svg` is a girih-style tiling (~3,000 paths, one fill). It's
tinted white at low opacity in `AppBackground` rather than using its own
baked-in `#071C30`, so it reads evenly over the whole gradient instead of
vanishing into the dark bottom. Swap the asset or the tint there and every
screen follows; don't add a second background decoration per screen.

### 1b. Light surfaces (cards, compass dial)

| Hex | Status | Role | Where |
|---|---|---|---|
| `#F5F9FC` → `#E2ECF3` → `#CFDEE9` | 🔒 | **"Arch" gradient** — the light card/panel shape (e.g. Home's clock card), now a three-stop gradient instead of a flat `#F0F8FF`. | Light card surfaces |
| `#F1F7FB` | 🔒 | **Compass dial background** ("white compass"). Near-identical to the arch tones but its own token since the dial is its own element. | `QiblaScreen` dial |
| `#0E2F47` / `#12354F` | 🔒 | **Clock hands, dial numerals.** Refines the previous `#283F54`. | `AnalogClockView`, compass dial |
| `#5B7E97` | 🔒 | **Secondary text on light surfaces.** A distinct token from `#D3E0EC` (§1d) — that one is for dark surfaces, this is specifically for text sitting on the light card/dial. | Text on light cards |

### 1c. Accent — cyan

| Hex | Status | Role | Where |
|---|---|---|---|
| `#7AD2F7` primary / `#3FA3D8` deep | 🔁 **open** | **Accent — "active / next / on."** Same role as before (§ intro), refreshed from `#4DB3E5`/`#0768C5` to this cyan gradient pair. Still the one deliberately swappable hue in the palette. | Nav bar selected pill, next-prayer name/card, active switches and radios |
| `rgba(122,210,247,.12–.22)` fills / `.28–.45` borders | 🔁 **open** | Opacity tiers *of the accent* for tinted fills/borders — "related to the active item" without full accent-color text. | `AccentCard`'s border, nav-bar selected glow |

### 1d. Text (on dark surfaces)

Replaces the old two-tier `#F0F8FF` (primary) / `#D3E0EC` (secondary) system
with a six-tier scale — same *intent* (near-white primary content, graduated
muting for lower emphasis), more graduation between them.

| Hex | Status | Role |
|---|---|---|
| `#FFFFFF` | 🔒 | Headings |
| `#DCEAF5` / `#E6F1F9` | 🔒 | Body text |
| `#C6DBEA` | 🔒 | Secondary text |
| `#A9C3D6` | 🔒 | Muted text |
| `#8BA7BD` | 🔒 | Labels/captions |
| `#7D97AD` / `#6B869C` | 🔒 | Faint text, inactive icons (nav bar unselected icons — migrated) |

**Applied:** all screens now use this scale via `AppColors`. The old `#F0F8FF`/`#D3E0EC` pair was mapped by context — headings to `heading`, most content to `body`, secondary labels to `secondary`, and de-emphasized/passed states to `label`.

**Opacity tiers on the primary content color** (still valid, now read against
whichever text tier above is in play): `~40%` alpha → "passed" state (a
prayer that already happened today); `~10%` alpha → subtle row/surface
highlight background. Muted/highlighted states are derived via opacity, not
separate gray hexes.

### 1e. Status colors

| Hex | Status | Role | Where |
|---|---|---|---|
| `#FF6B5E` / `#FF5D52` | 🔒 | **Directional marker + countdown/urgency.** Refines `#E54D4D`, and its role is deliberately widened from "Qibla marker only" to also cover countdown/urgency displays (e.g. an Iqama countdown) — a considered exception to how tightly this hue used to be scoped, not scope creep. Still never a generic error/danger color for arbitrary UI. | `arrow.svg`, `ka3baInCompass.svg`, `CountDown.dart`'s Iqama color |
| `#5FE08E` | 🔒 | **Success / target-state reached.** Refines `#4DE599` (same role: "you got it"). Still not a general confirmation color for arbitrary snackbars or checkmarks — that discipline hasn't changed, only the hex. | `QiblaScreen` (aligned with Qibla), `SettingsScreen` (alarm scheduled today / working) |
| `#FFC46B` | 🔒 | **Warning.** The fourth semantic hue. Now in use for the "scheduled for tomorrow" alarm state, paired against `#5FE08E` for "scheduled today" — which is precisely the pairing it was reserved for, so it went in as soon as that pairing surfaced. | `SettingsScreen` alarm-status list |

Note this means the palette now deliberately holds **two** warm hues (red +
amber) alongside the cool navy/cyan/green — each still scoped to exactly one
meaning, which is the discipline that matters, not "stay monochrome."

**Previously a known inconsistency, now resolved:** screens used to reach for
`Colors.white`/`Colors.white70`/`Colors.red`/`Colors.green` instead of a
documented tier. Those are gone — `lib/theme/app_colors.dart` is the only
place a color is defined. Keep it that way.

## 2. Logo & icon style

The app icon (`assets/mainIcon.png`) defines the icon language:

- **Flat silhouette, single fill color, no strokes, no gradients.** A mosque
  dome + crescent moon rendered as solid shapes.
- **Inverted contrast vs. the rest of the app on purpose:** the icon tile is
  light (`#F0F8FF` background) with a dark navy (`#0A2239`) silhouette, while
  every other in-app surface is the reverse (dark navy background, light
  content). Do not "fix" this by making the icon dark-on-dark to match the
  app — the inversion is intentional and is what makes the icon read on a
  home screen.
- **Rounded-square tile**, not a full circle or a hard-edged square (see
  corner radius language below).
- In-app iconography (`settingsIcon.svg`, `h1.svg`/`h2.svg`/`h3.svg`) follows
  the same flat/no-stroke/no-gradient rule, just inverted to white-on-navy to
  match the base surface. New icons should match this: solid geometric
  silhouettes, one fill color, no outline style, no skeuomorphism.
- The red accent appears *only* in compass/direction graphics (`arrow.svg`,
  `ka3baInCompass.svg`) — never in the general icon set. Both SVGs' `fill`
  attributes and the Dart-level `Color(...)` usages in `QiblaScreen.dart`
  were all refreshed together to `#FF6B5E`, so the icon and the code stay
  the same token.

## 3. Typography — Arabic + Latin pairing

The app does **not** pair two different typefaces for Arabic vs. Latin text.
It uses a single variable font, **Cairo** (`fonts/Cairo-VariableFont_slnt,wght.ttf`,
declared as font family `cairo` in `pubspec.yaml`), for everything — Arabic
labels, Latin numerals, and any Latin UI strings alike, across every screen
(`PrayerTimeScreen`, `QiblaScreen`, `SettingsScreen`, `AnalogClockView`,
`adhan_screen`).

**This "one unified typeface across scripts" is the identity — not a
pairing.** Do not introduce a second Latin-only font for numbers/English
strings; Cairo already carries both scripts and that consistency (same
x-height, same weight feel, same letterforms) between Arabic and Latin text is
the intended look.

**Known inconsistency, not to be codified:** the font family is registered as
`cairo` (lowercase) but referenced as both `'cairo'` and `'Cairo'` across the
codebase. Flutter resolves these to the same family, but a redesign pass
should standardize on one casing — it should not introduce an actual second
font.

## 4. Corner radius language

Radii follow a small, deliberate scale — a multiple-of-12 progression for
rectangular surfaces, plus full circles for dial/badge elements:

| Radius | Use |
|---|---|
| `12` | Smallest — default control/snackbar/small-card radius |
| `24` | Medium — larger containers/sheets |
| `36` | Large — prominent rounded surfaces/buttons |
| `Radius.circular(70)` (or fully circular) | Dial/badge-style circular elements (e.g. compass) |
| `16dp` | Home screen widget card background (native Android) |
| `8dp` | Home screen widget row highlight (native Android) |

Keep rounded, never sharp — no corner in this app should read as a hard
90° rectangle; the softness of the curve is part of the identity. When adding
new components, pick from `{12, 24, 36}` (or fully circular for round
elements) rather than an arbitrary value.

**Known outliers, not to be codified:** a couple of one-off radii (`25`, `40`)
exist in the current code and don't fit the 12/24/36 scale — treat these as
drift to be reconciled onto the scale, not as additional canonical values.
