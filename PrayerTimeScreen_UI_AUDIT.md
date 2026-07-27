# Prayer Time List Screen — UI/UX Audit

**Scope:** `lib/view/PrayerTimeScreen.dart` — the bottom-nav "list" tab (second
tab): location header, the 5-prayer list, and the two dialogs it opens
(change-location, per-prayer sound/Adhan settings).

**Method:** static review of the Dart source against
`design/before/PrayerTimeScreen.png`, `design/before/ChangeLocationMenu.png`,
and `design/before/ChangePrayerMenu.png`, cross-referenced with
`DESIGN_IDENTITY.md`, `DESIGN_SYSTEM.md`, and the fixes already made to the
Home screen this session. No code was changed; no redesign proposed.

**Correction to `DESIGN_SYSTEM.md` found while reviewing this file:** §6 of
that document describes a "list row" pattern here — "background highlight
for the active/next row using `#4DB3E5`/opacity, muted for passed rows" —
and attributes it to this screen. That pattern doesn't actually exist in
`PrayerTimeScreen.dart`. It was a mix-up: that highlight/mute logic really
lives in the **native** `PrayerWidgetProvider.kt` (the home-screen widget),
not here. This is directly related to finding #1 below — the reason the
"next" row isn't visually distinguished is that the pattern was never built
in Flutter, only natively. `DESIGN_SYSTEM.md` §6 should be corrected
separately.

## Coverage summary

| Lens | Verdict |
|---|---|
| Information architecture | **Issues found** — #1, #12 |
| Visual hierarchy | **Issues found** — #1, #2 |
| Cognitive load | **Issues found** — folded into #2 |
| Spacing | **Issues found** — #13, #14 |
| Typography | **Issues found** — #3 |
| Colour semantics | **Issues found** — #8, #10 (accent-blue usage on the switch/radio in the sound dialog is correct — see note after the findings) |
| Accessibility | **Issues found** — #3, #4, #5 |
| Contrast | **Issues found** — #9 |
| Component consistency | **Issues found** — #7, #11, #12 |
| Responsiveness | **Issues found** — #13 |
| RTL | **Issues found** — #6 |
| Touch targets | **Issues found** — #4 |

---

## Findings

### 1. The "next" prayer has almost no visual distinction from the other four
- **Severity:** Critical
- **Effort:** M
- **Problem:** `_AnimatedPrayerCard` renders every row with identical styling
  regardless of `isNext` or whether a prayer already passed today — same
  translucent background, same text color/weight. The *only* difference for
  the next prayer is that a ticking `CountdownTimer` renders in a shared
  slot that's otherwise `SizedBox.shrink()`; even that countdown text
  defaults to `#F0F8FF` (plain content color), not the accent `#4DB3E5`.
- **Why it matters:** This is the single most important piece of
  information on the screen — which prayer is coming up — and yet nothing
  about a row's color, weight, or shape tells you that at a glance. A user
  has to notice a small ticking number appearing in the middle of one
  particular row among five nearly-identical ones. Compare to the native
  home-screen widget (`PrayerWidgetProvider.kt`), which *does* highlight the
  next row and mute passed ones — the Flutter screen is missing the pattern
  its own native sibling already implements.
- **Recommendation:** Give the next-prayer row a real visual treatment
  (accent-colored name/background per `DESIGN_IDENTITY.md`'s "next" role)
  and mute passed rows (`#F0F8FF` at reduced opacity, matching the pattern
  already used natively and now on the redesigned Home screen's
  `NextPrayerCard`).
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_AnimatedPrayerCard`,
  `_buildPrayerCard`).

### 2. The location header dominates the screen's visual hierarchy
- **Severity:** High
- **Effort:** M
- **Problem:** The country name renders at 38px bold — the single largest
  text on the entire screen — with the city name just below at 24px. Together
  with `height * 0.1` of top padding, the location header claims a large,
  visually loud share of the screen for information a user reads once, not
  the reason they opened this tab.
- **Why it matters:** Visual weight should track importance. Right now the
  boldest, biggest element on screen is location metadata, while the 5
  prayer rows underneath — the actual content — are comparatively quiet
  (16px/14px, several in a very thin weight; see #3). This pulls attention
  away from the prayer list on every glance.
- **Recommendation:** Scale the location header down significantly relative
  to the prayer list content, more in line with how Home now treats its own
  secondary/ambient information.
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_buildLocationHeader`).

### 3. Extremely thin font weight hurts legibility on important text
- **Severity:** Medium
- **Effort:** S
- **Problem:** The city name (24px) and **every prayer's time** (14px) use
  `FontWeight.w100` — the thinnest weight available.
- **Why it matters:** `w100` at small sizes is hard to read even for users
  with good vision; for low-vision users it's worse, and it's a strange
  choice for the prayer *time* specifically, arguably the second most
  important text on each row after the name.
- **Recommendation:** Move both up to a more legible weight (e.g. `w400`–`w500`),
  consistent with the rest of the app's body text.
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_buildLocationHeader`,
  `_AnimatedPrayerCard`).

### 4. The mute/unmute icon's touch target is below the minimum, and sits inside a bigger, different-purpose target
- **Severity:** Medium
- **Effort:** S
- **Problem:** The mute/unmute toggle is an `Icon` wrapped in `Padding(all: 8)`
  inside a bare `GestureDetector` — roughly 40×40 total, below the 48×48dp
  minimum `DESIGN_SYSTEM.md` §11 documents (and that the bottom nav already
  meets comfortably). It also sits inside the *entire card's* own tap target,
  which does something different (opens the sound dialog).
- **Why it matters:** A target this small is genuinely harder to hit
  precisely; missing it by a few pixels opens a whole dialog instead of just
  toggling mute — a frustrating mis-tap, not just a minor inconvenience.
- **Recommendation:** Enlarge the icon's own tappable area to at least
  48×48dp.
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_AnimatedPrayerCard`,
  the `FutureBuilder<bool>` mute icon).

### 5. No accessible labels for the mute icon or the "next prayer" countdown
- **Severity:** Medium
- **Effort:** S
- **Problem:** The mute/unmute icon has no semantic label — a screen reader
  announces an unlabeled icon, not "disable Adhan for Asr." The countdown
  value for the next prayer likewise has no label grouping it with "this is
  the next prayer."
- **Why it matters:** Both pieces of information are meaningful and
  currently silent to assistive technology.
- **Recommendation:** Add `Semantics`/`tooltip` labels naming the action and
  prayer (e.g. "كتم أذان الفجر" / "next prayer" grouping).
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_AnimatedPrayerCard`).

### 6. Dialogs render with LTR layout conventions despite fully Arabic content
- **Severity:** Medium
- **Effort:** M
- **Problem:** `RadioListTile`/`SwitchListTile` in `_showSoundDialog` use
  their default `secondary`/leading placement, which follows LTR convention.
  Confirmed in `design/before/ChangePrayerMenu.png`: the radio bullet sits at
  the visual left, the play/pause icon at the visual right, body text
  left-aligned — despite every string being Arabic.
- **Why it matters:** This is a concrete, visible instance of the app-wide
  RTL gap already flagged in `PrayerHome_UI_AUDIT.md` #12 — more visible
  here than on Home because this screen uses stock `ListTile`-family widgets
  (which have real leading/trailing layout logic) instead of manually
  right-aligned `Text`/`Row` pairs.
- **Recommendation:** Same as previously noted: the real fix is app-wide
  `Directionality`/locale configuration (still out of scope per that
  decision). Short of that, these specific dialogs could set `controlAffinity`/
  wrap content to visually match RTL expectations without waiting on the
  app-wide fix.
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_showSoundDialog`).

### 7. The "next prayer" concept now looks completely different on this screen vs. Home
- **Severity:** Medium
- **Effort:** M
- **Problem:** The redesigned Home screen gave "next/active" a specific,
  bespoke visual signature (asymmetric card radius, accent edge, breathing
  glow — `lib/view/NextPrayerCard.dart`). This screen's next-prayer row
  shares none of it (see #1) — the same concept reads as two unrelated
  designs depending on which tab you're on.
- **Why it matters:** The task explicitly named the Home redesign as "the
  design reference for the rest of the app" — this is the first place that
  reference should visibly apply.
- **Recommendation:** When fixing #1, borrow the same visual language
  (accent color + edge/glow treatment) rather than inventing a second one.
- **Files affected:** `lib/view/PrayerTimeScreen.dart`, cross-reference
  `lib/view/NextPrayerCard.dart`.

### 8. Dialogs use generic `Colors.white*` instead of the identity's content color
- **Severity:** Low
- **Effort:** S
- **Problem:** `_showLocationDialog` and `_showSoundDialog` use
  `Colors.white`, `white54`, `white60`, `white70`, `white24`, `white38`
  throughout, rather than `#F0F8FF` and its documented opacity tiers.
- **Why it matters:** This is the single most concentrated instance in the
  app of the drift `DESIGN_IDENTITY.md`/`DESIGN_SYSTEM.md` already flag
  generically — worth calling out concretely since it's nearly every text
  style in both dialogs.
- **Recommendation:** Converge onto `#F0F8FF` + the `66`/`1A`-alpha tiers.
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (both dialog builders).

### 9. Several low-alpha whites likely fall below contrast minimums
- **Severity:** Low
- **Effort:** S
- **Problem:** `Colors.white38` (disabled mute icon), `Colors.white24`
  (divider), and `Colors.white60` (search hint text) are quite faint against
  the `#0A2239`/`#0E2031` dark surfaces.
- **Why it matters:** Rough contrast estimates put these noticeably below
  WCAG's 4.5:1 text minimum — the hint text and disabled icon are
  meaningful, not purely decorative, so this is a real legibility concern,
  not just a token-naming one (related to #8 but distinct).
- **Recommendation:** Darken the surface or lighten these specific instances
  when converging onto the identity's opacity tiers.
- **Files affected:** `lib/view/PrayerTimeScreen.dart`.

### 10. The error message uses generic `Colors.red`, not the app's own red
- **Severity:** Low
- **Effort:** S
- **Problem:** `_buildErrorState`'s "حدث خطأ" text uses `Colors.red` rather
  than `#E54D4D`.
- **Why it matters:** Same issue just fixed in `CountDown.dart`'s Iqamah
  color this session — a second, slightly different red exists in the app
  alongside the identity's actual red.
- **Recommendation:** Use `#E54D4D` here too for consistency (independent of
  the separate question of whether an error state should use red at all,
  given `DESIGN_IDENTITY.md` reserves red for the Qibla marker).
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_buildErrorState`).

### 11. Duplicated dialog-transition code, and stock Material dialog styling
- **Severity:** Low
- **Effort:** M
- **Problem:** The `ScaleTransition`+`FadeTransition` transition builder
  (same curve, duration, `Tween`) is copy-pasted between `_showLocationDialog`
  and `_showSoundDialog`. Separately, `RadioListTile`/`SwitchListTile` carry
  Flutter's default ripple/ink styling, unstyled to match the app's flat,
  no-stock-widget look used elsewhere.
- **Why it matters:** The duplication is a straightforward "reuse before you
  build" miss (`DESIGN_SYSTEM.md` §12); the stock-widget look is a "feels
  bespoke vs. generic" concern, the same kind raised (and fixed) for the
  Home screen's `NextPrayerCard` before this session.
- **Recommendation:** Extract a shared dialog-transition helper; consider
  restyling the sound dialog's list rows to match the app's flat aesthetic.
- **Files affected:** `lib/view/PrayerTimeScreen.dart`.

### 12. The giant location header doubles as a button with a weak affordance
- **Severity:** Low
- **Effort:** S
- **Problem:** The entire header `Row` (including the huge 38px country
  text) is wrapped in `InkWell(onTap: _showLocationDialog)`, but the only
  visual cue that *anything* here is tappable is a small pencil icon next to
  the much smaller city text.
- **Why it matters:** A user has little reason to suspect the big headline
  text is a button rather than a static label.
- **Recommendation:** Make the tappable affordance visible at the same scale
  as the tappable area (e.g. a subtle border/icon sized to the header, not
  just a tiny pencil next to secondary text).
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_buildLocationHeader`).

### 13. Percentage-of-screen-height spacing, not yet aligned with the Home fix
- **Severity:** Low
- **Effort:** S
- **Problem:** `_buildLocationHeader`'s top padding
  (`MediaQuery.sizeOf(context).height * 0.1`) and the gap before the list
  (`* 0.05`) are the exact anti-pattern already identified and removed from
  the Home screen this session (`DESIGN_SYSTEM.md` §1/§9).
- **Why it matters:** Same risk as before — this drifts differently across
  device aspect ratios — and now it's also an inconsistency between the two
  screens (one fixed, one not).
- **Recommendation:** Replace with fixed/derived spacing, same approach used
  in `adhan_screen.dart`.
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_buildSuccessState`,
  `_buildLocationHeader`).

### 14. A fixed 64px gap combined with `spaceBetween` is a fragile layout technique
- **Severity:** Low
- **Effort:** S
- **Problem:** Each row uses `mainAxisAlignment: MainAxisAlignment.spaceBetween`
  across three groups (mute icon, countdown slot, name/time column) *and*
  inserts an explicit `SizedBox(width: 64)` between the countdown slot and
  the name column.
- **Why it matters:** `spaceBetween` already distributes remaining space;
  layering a fixed gap on top doesn't adapt to different prayer-name widths
  (`الفجر` vs. `المغرب`) or larger text-scale settings, and can crowd or
  leave uneven gaps depending on content width.
- **Recommendation:** Let `spaceBetween` (or `Expanded`/`Flexible` slots) do
  the distribution without an additional fixed spacer.
- **Files affected:** `lib/view/PrayerTimeScreen.dart` (`_AnimatedPrayerCard`).

---

## Reviewed — good examples, no defect

- **Async state handling**: `loading`/`error`/`data` are all handled
  explicitly with a real retry action on error — exactly the pattern
  `DESIGN_SYSTEM.md` §7 asks for, already followed correctly here.
- **Accent-blue usage**: the sound dialog's `activeThumbColor`/`activeColor`
  on the enable-switch and sound radio buttons correctly use `#4DB3E5` for
  "this is the selected/active one" — a textbook-correct use of the
  documented role.
- **Dialog height constraint**: `ConstrainedBox(maxHeight: size.height * 0.5)`
  around the location dialog's scrollable content is a reasonable,
  defensive responsive technique — no issue there.

## Note, not actionable at the UI layer

The location-search field's hint text asks for the city name "بالإنجليزية"
(in English) — a real but backend-driven constraint (the Nominatim/geocoding
lookup needs Latin-script input), not something a UI change alone can fix.
Flagged for awareness, not as a finding.

## What this audit does NOT do

No code was written or modified. No layout, color, or component changes are
proposed beyond what's described above.
