# Design Identity — Adhani

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

| Hex | Status | Role / meaning | Where it's used |
|---|---|---|---|
| `#0A2239` | 🔒 | **Base surface.** The app's canvas — scaffold background, canvas color, app bar. This is the "night sky navy" the whole app sits on. | `main.dart` theme, `PrayerTimeScreen`, native widget background |
| `#0E2031` | 🔒 | **Elevated dark surface.** A touch darker than base, for bars/buttons/sheets sitting on top of the base surface. | `PrayerTimeScreen` app bars, elevated button backgrounds |
| `#1A3A5C` / `#1E2A3A` / `#0B1220` | 🔒 | Secondary dark surfaces (snackbars, one-off containers) — same family as the two above, do not introduce unrelated dark hues. | `PrayerTimeScreen` snackbar, misc containers |
| `#283F54` / `#2D4356` | 🔒 | **Card / mid-surface tone.** Sits between base and elevated — used for cards and secondary panels. | Various screens |
| `#F0F8FF` | 🔒 | **Primary content color.** Near-white ("Alice Blue") text/icon color on dark surfaces. This is *also* the app icon's tile background — see §2. | Prayer names/times, headers, icons; widget "current" text |
| `#D3E0EC` | 🔒 | Secondary/muted content on dark surfaces (lower emphasis than `#F0F8FF`, higher than the opacity tiers below). | Secondary labels |
| `#4DB3E5` / `#0768C5` | 🔁 **open** | **Accent — "active / next / on".** Reserved for the thing that's currently selected or upcoming: the next-prayer highlight, active toggle/switch thumb, the widget's next-prayer text. The *role* (a single, distinct hue meaning "this one is active/next") is locked; the specific blue is not — swap it for a better-performing hue (e.g. better contrast on `#0A2239`/`#0E2031`, better distinction from the base-surface blues) as long as it still reads clearly as "the active one" and doesn't collide with the red directional accent below. | Next-prayer highlight (in-app and in the home screen widget), active switches |
| `#E54D4D` | 🔒 | **Accent — directional marker only.** Reserved specifically for the Qibla/compass direction indicators (arrow tip, compass tick). It is deliberately the only warm color in an otherwise cool (navy/blue) palette — that contrast *is* the point: red = "this way." Never use it as a generic error/danger color or a general accent. | `arrow.svg`, `ka3baInCompass.svg` |

Overall, the navy-surface + near-white-content + red-directional-marker
palette is locked as a *system* — refine shades within it freely, but don't
add unrelated hue families or remove any of these roles. The accent blue is
the one deliberate exception: it's a placeholder for "whatever hue best says
active/next" and is fair game if you find something better.

**Opacity tiers on the primary content color** (used instead of separate gray hexes):
- `#F0F8FF` at ~40% alpha (`#66F0F8FF`) → "passed" state (a prayer that already happened today).
- `#F0F8FF` at ~10% alpha (`#1AF0F8FF`) → subtle row/surface highlight background.

Keep this pattern — muted and highlighted states are derived from the primary
content color via opacity, not from separate gray/tint hexes.

**Known inconsistency, not to be codified:** many screens use `Colors.white` /
`Colors.white70` directly instead of `#F0F8FF` / the opacity tiers for the same
"primary content on dark" role. The *intent* (near-white content on navy) is
canon; the raw `Colors.white` literal is not — a redesign should converge these
onto the documented hex, not preserve the inconsistency.

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
- The red accent (`#E54D4D`) appears *only* in compass/direction graphics
  (`arrow.svg`, `ka3baInCompass.svg`) — never in the general icon set.

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
