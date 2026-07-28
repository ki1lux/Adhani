# Qibla Compass Screen — UI/UX Audit

**Scope:** `lib/view/QiblaScreen.dart` — the bottom-nav "compass" tab: the
loading/unsupported/no-permission states, and the main compass view (dial,
direction readout, reset button).

**Method:** static review of the Dart source against
`design/before/CompassScreen.png`, cross-referenced with `DESIGN_IDENTITY.md`,
`DESIGN_SYSTEM.md`, and the patterns already established this session on the
Home and Prayer Time List screens. No code was changed; no redesign proposed.

This screen hasn't been touched by any of the work done so far — it's still
using the pre-redesign patterns (stock `ElevatedButton`, raw `Colors.white*`,
no shared tap-feedback widget) that were already fixed on the other two
screens. Expect more "bring this screen up to what the rest of the app now
does" findings here than screen-specific novel problems.

## Coverage summary

| Lens | Verdict |
|---|---|
| Information architecture | **Issues found** — #3, #4 |
| Visual hierarchy | **Reviewed, no defect** — see note below |
| Cognitive load | **Issues found** — folded into #3 |
| Spacing | **Issues found** — #10 |
| Typography | **Issues found** — #11 |
| Colour semantics | **Issues found** — #1, #8 |
| Accessibility | **Issues found** — #6 |
| Contrast | **Issues found** — #7 |
| Component consistency | **Issues found** — #2, #9 |
| Responsiveness | **Issues found** — #5 |
| RTL | **Issues found** — #12 |
| Touch targets | **Reviewed, no defect** — see note after the findings |

---

## Findings

### 1. "Facing Qibla" is signaled with `Colors.green` — a hue outside the app's entire palette
- **Severity:** Critical
- **Effort:** S
- **Problem:** When the device is aligned with the Qibla direction, the
  center degree readout and the "في اتجاه القبلة" label switch to
  `Colors.green` (Flutter's default Material green, `#4CAF50`) — otherwise
  they're `#0A2239` (navy). Green doesn't exist anywhere else in the app.
- **Why it matters:** `DESIGN_IDENTITY.md` documents exactly one warm/non-navy
  hue in the entire palette — `#E54D4D`, reserved specifically for this
  screen's own directional markers (`arrow.svg`, `ka3baInCompass.svg`, both
  of which correctly use it). Introducing an unrelated fourth hue family for
  the single most important state on this screen ("you found it") breaks
  that discipline and looks like an afterthought, not a designed state.
- **Recommendation:** Signal "aligned" using the palette already reserved for
  exactly this purpose — the accent blue (`#4DB3E5`, the app's "active/on"
  color) or a treatment built from the existing red directional marker,
  rather than introducing green.
- **Files affected:** `lib/view/QiblaScreen.dart` (the `isPointingToQibla`
  text color branches).

### 2. The whole screen still uses stock `ElevatedButton` and raw `Colors.white*`, untouched by the app's now-established language
- **Severity:** High
- **Effort:** L
- **Problem:** The reset button, the permission-retry button, and every
  loading/error/icon color on this screen use unstyled `ElevatedButton`/
  `ElevatedButton.icon` with ad hoc `Colors.white24`/`Colors.white54`/
  `Colors.white.withValues(alpha: 0.05)` — none of the shared `_TapScale`
  tap-feedback, `#F0F8FF`/`#D3E0EC` tokens, or bespoke shape language now
  used on Home and the Prayer Time List screen appear here at all.
- **Why it matters:** The other two screens now share one tactile/visual
  language (custom scale+fade tap feedback, no stock Material ripple,
  identity color tokens). This screen still feels like the "before" version
  of the app sitting next to two "after" screens in the same bottom nav.
- **Recommendation:** Bring this screen's buttons/loading states onto the
  same shared components (`_TapScale`-based buttons, identity tokens)
  established for the other two screens, rather than a screen-specific
  solution.
- **Files affected:** `lib/view/QiblaScreen.dart` (all four `build()`
  branches).

### 3. No guidance for the (much more common) "not yet aligned" state
- **Severity:** High
- **Effort:** M
- **Problem:** The only instructional text on this screen, "في اتجاه القبلة"
  ("facing Qibla"), appears *exclusively* once the user is already correctly
  aligned. Before that — which is most of the time a user is looking at this
  screen — there's no text explaining what to do: that the small Kaaba icon
  rotating around the dial marks the Qibla direction, and the fixed red
  arrow above the dial marks the phone's own heading, and the two need to be
  brought together.
- **Why it matters:** This is a fairly standard compass-app interaction
  pattern, but it isn't self-explanatory from the visuals alone, and nothing
  ever teaches it — a first-time user has to reverse-engineer the model
  themselves.
- **Recommendation:** Add a persistent (or first-run) hint describing the
  interaction — e.g. "وجّه هاتفك حتى تصطف الكعبة مع السهم" — shown until the
  user first successfully aligns.
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 4. "إعادة ضبط القبلة" (Reset Qibla) doesn't actually reset or recalibrate anything
- **Severity:** Medium
- **Effort:** M (relabeling is S; an actual calibration flow is a bigger,
  separate feature)
- **Problem:** The button's `onPressed` shows a loading spinner for 600ms,
  displays a "تم إعادة التهيئة بنجاح" ("reinitialized successfully")
  snackbar, and calls `_checkPermission()` again — it re-checks permission/
  sensor support, but never touches compass calibration.
- **Why it matters:** Magnetometer drift is the actual, common real-world
  problem with phone compasses, and "Reset Qibla" strongly implies this
  button fixes exactly that. A user experiencing drift will tap it, see a
  success message, and reasonably expect the reading to have improved — it
  hasn't, because nothing about the sensor was touched.
- **Recommendation:** Either relabel to match what the button actually does
  (e.g. "إعادة التحقق من الإذن" / re-check permission), or — as a larger,
  separate feature — add real calibration guidance (the standard
  figure-8-motion prompt many compass apps show).
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 5. The compass container's size is a portrait-only, uncommented formula
- **Severity:** Medium
- **Effort:** M
- **Problem:** `SizedBox(height: screenWidth + 75, width: screenWidth - 32)`
  derives the compass area's height from device *width* with no explanation
  for `+75`, and no handling for landscape orientation or tablet-sized
  screens.
- **Why it matters:** On a wide screen (tablet, or landscape — which nothing
  here guards against) this formula can produce a compass taller than the
  available viewport, and the magic numbers make it unclear what's safe to
  change without visually testing every device shape.
- **Recommendation:** Derive the compass size from available constraints
  (`LayoutBuilder`) with an explicit aspect ratio and a sensible max size,
  documented, rather than a width-derived height formula.
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 6. The compass has no non-visual alternative beyond undocumented haptics
- **Severity:** Medium
- **Effort:** M
- **Problem:** Current heading, distance from Qibla, and the "aligned" state
  are communicated entirely visually (rotating SVGs, a degree number, a
  color change) except for haptic pulses (`HapticFeedback.lightImpact` while
  turning, `heavyImpact` on alignment) — a nice touch, but there's no spoken/
  semantic description of any of this state, and no on-screen indication
  that haptic feedback exists at all.
- **Why it matters:** A screen reader user gets nothing describing "you're
  facing X°, Qibla is Y° to your left" — for an inherently visual tool like
  a compass this is a hard problem, but currently there's no attempt at a
  fallback beyond the (undiscoverable) haptics.
- **Recommendation:** Add a live-updating semantic label describing current
  heading and relative Qibla direction; consider surfacing that haptic
  feedback is available (e.g. in the first-run hint from #3).
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 7. Green-on-light-dial is a borderline contrast pairing
- **Severity:** Low
- **Effort:** S
- **Problem:** Same `Colors.green` from #1 — Material's default green
  against the light dial background (`#F0F8FF`-ish) is a middling-contrast
  pairing, on top of being the wrong hue entirely.
- **Why it matters:** Compounds #1 — whatever replaces green should also be
  checked for contrast against the light dial, not just for identity fit.
- **Recommendation:** Resolved as part of #1's fix.
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 8. `Colors.white`/`white24`/`white54` instead of identity tokens
- **Severity:** Low
- **Effort:** S
- **Problem:** The loading spinner, error/permission icons and text, and
  both `ElevatedButton`s use raw `Colors.white` variants rather than
  `#F0F8FF` and its documented opacity tiers.
- **Why it matters:** Same drift already identified and fixed on the other
  two screens — this screen just hasn't had the pass yet.
- **Recommendation:** Converge onto `#F0F8FF`/`#D3E0EC` + opacity tiers, same
  mapping used on Home and the Prayer Time List screen.
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 9. The confirmation SnackBar doesn't match the one on the other screen
- **Severity:** Low
- **Effort:** S
- **Problem:** This screen's SnackBar (`تم إعادة التهيئة بنجاح`) uses
  Material's default square, bottom-anchored style with a plain `#0A2239`
  background. `PrayerTimeScreen.dart`'s SnackBar for the equivalent
  "confirmation toast" role uses `SnackBarBehavior.floating`, a `12`-radius
  rounded shape, and `#1A3A5C`.
- **Why it matters:** Same UI component, same purpose, two different looks
  depending on which tab triggered it.
- **Recommendation:** Match the floating/rounded/`#1A3A5C` treatment already
  established.
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 10. The reset button's position is a fixed pixel offset, not derived
- **Severity:** Low
- **Effort:** S
- **Problem:** `Positioned(bottom: 80, ...)` — a hand-tuned constant,
  independent of device height or the floating bottom nav's actual size.
- **Why it matters:** Same "magic fixed offset" pattern already identified
  and replaced with derived/`SafeArea`-aware spacing on the other two
  screens.
- **Recommendation:** Derive from `SafeArea`/the nav bar's actual height
  rather than a hand-picked constant.
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 11. `'Cairo'` vs `'cairo'` casing drift, present in this file too
- **Severity:** Low
- **Effort:** S
- **Problem:** Loading/error/permission states use `'Cairo'`; the compass's
  own center text and reset button use `'cairo'`.
- **Why it matters:** Same already-documented drift (`DESIGN_SYSTEM.md` §4),
  reproduced here.
- **Recommendation:** Standardize on `'cairo'` (the pubspec-registered
  casing), matching the fix already applied elsewhere.
- **Files affected:** `lib/view/QiblaScreen.dart`.

### 12. `ElevatedButton.icon`'s icon-before-label order resolves LTR by default
- **Severity:** Low
- **Effort:** S
- **Problem:** The permission-retry button's refresh icon sits before
  "إعادة المحاولة" in reading order because nothing on this screen
  establishes RTL layout direction.
- **Why it matters:** Minor, isolated instance of the same architectural gap
  already flagged (and locally worked around elsewhere) — low impact here
  since it's one small button, not a dense layout.
- **Recommendation:** Same local-`Directionality` treatment already used on
  the other two screens, if/when this button is rebuilt per #2.
- **Files affected:** `lib/view/QiblaScreen.dart`.

---

## Reviewed — good examples, no defect

- **The directional-marker red is used correctly.** Both `arrow.svg` (the
  fixed device-heading pointer) and the small tick mark baked into
  `ka3baInCompass.svg` use the identity's actual `#E54D4D` — exactly the one
  place `DESIGN_IDENTITY.md` reserves that hue for. The green readout in
  finding #1 is the only place this discipline slipped.
- **Haptic feedback** on rotation and alignment is a genuinely nice, calm,
  non-visual touch — it just needs the visible/discoverable counterpart
  described in #6, not removal.
- **Visual hierarchy**: the compass dial appropriately dominates the screen
  — for a single-purpose tool, that's correct weighting, not a defect.

## Touch targets — reviewed, no defect found

Both `ElevatedButton`s on this screen (reset, permission-retry) meet
Material's default minimum height regardless of their custom padding; there
are no other interactive elements. No change needed here specifically —
note that rebuilding these per #2 should preserve at least this same target
size.

## What this audit does NOT do

No code was written or modified. No layout, color, or component changes are
proposed beyond what's described above.
