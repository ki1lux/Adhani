# Prayer Home Screen — UI/UX Audit

**Scope:** `lib/view/adhan_screen.dart` (the bottom-nav "Home" tab) and its
embedded `lib/view/AnalogClockView.dart`. The bottom navigation bar itself is
shared across all 4 tabs (defined in `lib/main.dart`) and is noted where
relevant but is not this screen's own code.

**Method:** static review of the Dart source against `design/before/HomeScreen.png`,
cross-referenced with `DESIGN_IDENTITY.md` (locked visual identity) and
`CLAUDE.md` (architecture). No code was changed; no redesign proposed.

## Coverage summary

| Lens | Verdict |
|---|---|
| Information architecture | **Issues found** — #1, #9 |
| Visual hierarchy | **Issues found** — #1, #2 |
| Cognitive load | **Issues found** — folded into #1 |
| Spacing | **Issues found** — #3 |
| Typography | **Issues found** — #4, #5 |
| Colour semantics | **Issues found** — #6 |
| Accessibility | **Issues found** — #5, #7 |
| Contrast | **Issues found** — #8 |
| Component consistency | **Issues found** — #4, #10 |
| Responsiveness | **Issues found** — #11 |
| RTL | **Issues found** — #12, #13 |
| Touch targets | **Reviewed, no defect** — see note after the findings |

---

## Findings

### 1. The Home tab shows none of the app's core information
- **Severity:** Critical
- **Effort:** L
- **Problem:** `adhan_screen.dart` renders an analog clock, a digital time,
  and (when available) the Hijri date — and nothing else. There is no next
  prayer name, no countdown, no location/city. Below the Hijri date the
  screen is empty navy space down to the bottom nav (roughly 40–50% of the
  viewport in `design/before/HomeScreen.png`).
- **Why it matters:** This is a prayer-times app; "what's the next prayer and
  how long until it" is the reason the app exists, and it's already fully
  implemented — `CountdownTimer` in `lib/view/CountDown.dart` computes next-prayer
  name, live remaining time, and Iqamah-phase countdown from
  `prayerTimesProvider`, and is wired into `PrayerTimeScreen.dart` (the *second*
  tab). The native Android countdown notification and the home-screen widget
  both show this. The one screen that's actually the app's landing tab is the
  only surface that doesn't. A user has to leave the Home tab to answer the
  question they most likely opened the app for.
- **Recommendation:** Surface next-prayer name + live countdown (and ideally
  city/location) on this screen, reusing the existing `CountdownTimer` widget
  and `prayerTimesProvider` rather than building new state — the data and
  timer logic already exist, only placement is missing.
- **Files affected:** `lib/view/adhan_screen.dart`; reuse
  `lib/view/CountDown.dart` and `lib/providers/prayer_times_provider.dart`.

### 2. Visual weight is spent on redundant clock displays, not on what matters
- **Severity:** High
- **Effort:** M
- **Problem:** The analog clock (dominant, ~45–50% of screen height on a
  high-contrast white card) and the digital "6:51 PM" beneath it show the
  *same* information twice, and the device status bar already shows the time
  a third time. This redundant pair currently receives the strongest visual
  treatment on the screen.
- **Why it matters:** Visual hierarchy should point at the most important
  content first. Right now the biggest, highest-contrast shape on the screen
  is decorative, while the actually-decision-relevant content (see #1) isn't
  present at all to compete for attention.
- **Recommendation:** Once next-prayer/countdown content exists (#1), give it
  hierarchy at least equal to the clock — the clock can shrink or share
  billing rather than dominate the layout by default.
- **Files affected:** `lib/view/adhan_screen.dart`, `lib/view/AnalogClockView.dart`.

### 3. Large ungoverned empty region; spacing driven by screen-percentage magic numbers
- **Severity:** Medium
- **Effort:** M
- **Problem:** The gap between the Hijri date and the bottom nav has no
  content and no deliberate rhythm — it's what's left over, not a designed
  space. Spacing throughout the screen is expressed as `MediaQuery.sizeOf(context).height * 0.05`
  / `* 0.01`, and the top card is positioned at `top: -(height * 0.05)` — percentages
  of the live screen size rather than fixed/adaptive spacing values.
- **Why it matters:** Percentage-of-screen spacing doesn't compose with a
  spacing scale (compare `DESIGN_IDENTITY.md`'s deliberate 12/24/36
  corner-radius scale) and produces different visual rhythm on every device
  size — small phone vs. tablet get proportionally different gaps for no
  design reason, and the negative top offset is a fragile hand-tuned value.
- **Recommendation:** Once #1 fills the empty region, re-derive spacing from
  a small fixed set of values (in line with the corner-radius scale's spirit)
  instead of screen-size percentages.
- **Files affected:** `lib/view/adhan_screen.dart`.

### 4. Font-family casing inconsistency reproduced within this one screen
- **Severity:** Low
- **Effort:** S
- **Problem:** `AnalogClockView.dart` sets `fontFamily: 'cairo'` (lowercase)
  for the digital time; `adhan_screen.dart`'s `_buildHijriText` sets
  `fontFamily: 'Cairo'` (capitalized) for the date directly beneath it.
  Flutter resolves both to the same registered family, so it renders fine
  today, but it's the exact inconsistency `DESIGN_IDENTITY.md` already flags
  as drift to reconcile — and here it's present twice on the same screen.
- **Why it matters:** Harmless now, but two spellings of the same token
  invite a future typo (a *third* spelling) that silently falls back to the
  system default font, breaking the single-typeface identity.
- **Recommendation:** Standardize on one casing (`DESIGN_IDENTITY.md` doesn't
  mandate which — pick one and apply repo-wide).
- **Files affected:** `lib/view/AnalogClockView.dart`, `lib/view/adhan_screen.dart`.

### 5. Digital time's font size is unbounded and ignores text-scale accessibility settings
- **Severity:** High
- **Effort:** M
- **Problem:** `fontSize: MediaQuery.sizeOf(context).width * 0.12` — sized
  purely off device width, with no upper/lower clamp, and no use of
  `MediaQuery.textScaler`/`textScaleFactor`. It's the largest text on the
  screen.
- **Why it matters:** On a tablet or large foldable this produces very large
  type; more importantly, a user who has increased their OS text-scale for
  readability gets no benefit at all on the screen's most prominent text,
  while it *does* respond to device width — the wrong input is driving the
  size.
- **Recommendation:** Cap the width-derived size within a sensible range and
  incorporate the platform text-scale factor so accessibility font-size
  settings are honored.
- **Files affected:** `lib/view/AnalogClockView.dart`.

### 6. Clock-face colors repurpose surface-role tokens as content colors; the "active" accent is unused here
- **Severity:** Medium
- **Effort:** S
- **Problem:** `ClockPainter` paints the hour/minute/second hands and center
  dot with `#283F54` — documented in `DESIGN_IDENTITY.md` as a **card/mid-surface**
  tone — and the tick marks/inner circle with `#D3E0EC`, documented as
  **secondary content on dark surfaces**, here applied to a *light* card
  instead. Separately, `#4DB3E5` (the "active/next" accent) doesn't appear
  anywhere on this screen.
- **Why it matters:** Reusing a surface token as a foreground stroke color,
  and a dark-surface-content token on a light surface, isn't "wrong" (both
  stay within the locked navy family) but it blurs the roles
  `DESIGN_IDENTITY.md` assigns them. Separately, once #1 adds "next prayer"
  content, the accent that's supposed to mean exactly that is available and
  should be used.
- **Recommendation:** When touching this screen, prefer dedicated
  content-color tokens for the clock hands rather than reusing surface tones;
  reserve `#4DB3E5` for the next-prayer/countdown content from #1.
- **Files affected:** `lib/view/AnalogClockView.dart` (`ClockPainter`).

### 7. No accessibility semantics on the clock, time, or date
- **Severity:** Medium
- **Effort:** M
- **Problem:** The clock face is a bare `CustomPaint` (invisible to the
  accessibility tree by default) and the time/date are plain `Text` widgets
  with no `Semantics` labels distinguishing "current time" from "Hijri date"
  for assistive technology.
- **Why it matters:** A screen-reader user gets little or nothing useful from
  this screen — worse than #1's sighted-user gap, since there's no textual
  fallback at all for the clock.
- **Recommendation:** Wrap the clock in a `Semantics` node with a spoken
  label (or exclude it and rely on the adjacent digital text), and label the
  Hijri date explicitly.
- **Files affected:** `lib/view/adhan_screen.dart`, `lib/view/AnalogClockView.dart`.

### 8. Clock tick marks fail contrast against their own card (≈1.25:1)
- **Severity:** Low
- **Effort:** S
- **Problem:** The 60 tick marks and inner face circle are painted
  `#D3E0EC` on the `#F0F8FF` card behind them. Computed WCAG contrast ratio
  ≈ **1.25:1**.
- **Why it matters:** WCAG's own minimum for non-text graphics that convey
  meaning is 3:1; this is far below even that lenient bar, so for anyone with
  reduced contrast sensitivity the tick marks (and to a lesser extent the
  face circle) are effectively invisible — currently only the dark hands
  read clearly.
- **Recommendation:** If the ticks are meant to be legible, darken them
  relative to the card; if purely decorative/texture, that's a valid choice
  but worth making deliberately rather than as a side effect of token reuse
  (see #6).
- **Files affected:** `lib/view/AnalogClockView.dart` (`ClockPainter`).

### 9. No error or empty state if the prayer-time fetch fails with nothing cached
- **Severity:** High
- **Effort:** M
- **Problem:** `prayerTimesAsync.when(...)` routes `loading` and `error` to
  the same `_buildHijriText(_cachedHijri)` call. If `_cachedHijri` is empty
  (fresh install, cache cleared, or persistent fetch failure — e.g. location
  permission denied), `_buildHijriText` returns `SizedBox.shrink()` and nulls
  out silently.
- **Why it matters:** In that state the user sees a clock, a time, and a
  large empty region — no error message, no retry action, no indication
  anything is wrong or what to do about it.
- **Recommendation:** Give the `error` branch (and the empty-cache case) a
  visible, actionable state distinct from normal loading.
- **Files affected:** `lib/view/adhan_screen.dart`.

### 10. A 685KB full-screen background SVG renders with no visible effect
- **Severity:** Medium
- **Effort:** S
- **Problem:** `SvgPicture.asset('assets/Vector.svg', fit: BoxFit.cover)` is
  painted full-bleed behind everything, underneath a solid `#0A2239`
  container. Nothing attributable to this asset is visible in
  `design/before/HomeScreen.png` — the background reads as flat solid navy.
- **Why it matters:** Either this is dead weight (a very large vector asset
  parsed on every build for zero visual payoff) or it's supposed to be
  visible and is silently failing to show (matching color/blend, wrong
  layering) — both are worth resolving rather than leaving ambiguous, and
  neither matches the flat/no-texture surfaces documented in
  `DESIGN_IDENTITY.md`.
- **Recommendation:** Confirm intent — remove if decorative-and-unused, or
  fix if it's meant to be a subtle visible texture.
- **Files affected:** `lib/view/adhan_screen.dart`; `assets/Vector.svg`.

### 11. Layout is built from screen-percentage math with no SafeArea; untested across form factors
- **Severity:** Medium
- **Effort:** M
- **Problem:** The top card uses `Positioned(top: -(height*0.05), ...)` with
  `height: height*0.50`, and the clock is sized `Size(width, width)` — a
  perfect square as wide as the device. There's no `SafeArea` around the
  `Stack`; insets are handled entirely through this hand-computed math.
- **Why it matters:** On a tablet the width-bound clock becomes very large;
  on a short/small phone the fixed 50%-height card may not comfortably fit
  clock + time + date without crowding; devices with different notch/inset
  geometry than whatever this was tuned against aren't protected by
  `SafeArea`.
- **Recommendation:** Replace the percentage/offset math with constraint-
  and `SafeArea`-based layout so it holds up across screen sizes.
- **Files affected:** `lib/view/adhan_screen.dart`, `lib/view/AnalogClockView.dart`.

### 12. RTL is applied manually per-widget, not as app-wide directionality
- **Severity:** High
- **Effort:** L
- **Problem:** `_buildHijriText` hardcodes `textDirection: TextDirection.rtl`
  on that one `Text` widget. `lib/main.dart`'s `MaterialApp` sets no `locale`
  and wraps nothing in `Directionality` — there is no app-wide RTL
  configuration anywhere in the reviewed code.
- **Why it matters:** This app's content is Arabic throughout. Without true
  app-wide directionality, every other widget (alignment defaults, padding
  direction, icon/layout mirroring) is relying on implicit LTR layout with
  Arabic text rendered inside it via Unicode bidi auto-detection — one
  manually-flagged `Text` widget doesn't fix that, it just papers over a
  single visible symptom.
- **Recommendation:** Configure real app-wide RTL (`MaterialApp` locale +
  `Directionality`) rather than per-widget overrides; treat this as an
  architectural fix, not a one-screen fix, before further RTL-sensitive UI
  work.
- **Files affected:** `lib/main.dart` (root cause); `lib/view/adhan_screen.dart`
  (the one local symptom fixed today).

### 13. Latin "PM" mixed into otherwise Arabic content
- **Severity:** Low
- **Effort:** S
- **Problem:** The digital time is formatted with `DateFormat('h:mm a')`,
  producing Western numerals plus an English "AM/PM" marker, directly above
  Arabic Hijri-date text.
- **Why it matters:** Script-mixing on one screen (Latin "PM" next to Arabic
  month names) reads as inconsistent in an Arabic-first app; conventional
  alternatives are Arabic AM/PM markers (ص/م) or a 24-hour format, matching
  what the native Android countdown notification/widget already do
  (`HH:mm`-based, no AM/PM).
- **Recommendation:** Align the time format with the rest of the app's
  Arabic-locale conventions.
- **Files affected:** `lib/view/AnalogClockView.dart`.

---

## Touch targets — reviewed, no defect found

The Home screen itself has no interactive elements of its own (no buttons,
no gestures) — the only touch targets visible in it are the shared bottom
nav (`_buildBottomNav`/`_buildNavItem` in `lib/main.dart`, common to all 4
tabs). Each nav item's `GestureDetector` is `HitTestBehavior.opaque` over its
full `Expanded` cell within a 58px-tall bar — well above the 48×48dp minimum
target size. No change recommended.

---

## What this audit does NOT do

No code was written or modified. No layout, color, or component changes are
proposed beyond what's described above. `DESIGN_IDENTITY.md`'s locked
palette, icon style, Cairo typeface, and corner-radius scale are treated as
constraints on every recommendation (e.g. #6 and #2 work within the locked
colors; none of the above suggests introducing new hues, fonts, or corner
styles).
