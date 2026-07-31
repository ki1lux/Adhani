# Production Readiness Audit — Adhani

**Date:** 31 July 2026
**Scope:** full repository — Android manifest and Gradle configuration, R8
rules, signing, all 11 Kotlin sources, all 29 Dart sources, plugins, assets,
permissions, notifications, alarms, background services, network layer,
storage, localisation, accessibility and release configuration.

**Verification performed after the changes:**

| Check | Result |
|---|---|
| `flutter analyze` (with `flutter_lints` **enabled**) | No issues found |
| `flutter test` | 26/26 passing |
| `flutter build apk --release` | Success |
| `flutter build appbundle --release` | Success — 53.2 MB `.aab` |
| Android `lintVitalRelease` | No issues found |
| Merged release manifest | Audited by hand — 12 permissions, all used |

---

## Summary

### Production readiness: **88 / 100**

**Before this audit the app could not have been submitted at all.** Three
independent hard blockers were present:

1. `applicationId = com.example.myadhan` — Play refuses any `com.example.*`
   package on upload.
2. The release build was signed with the **debug key** — Play rejects the
   artifact.
3. No prominent location disclosure — a direct violation of Play's User Data
   policy for an app that transmits coordinates off-device.

All three are fixed, along with two shipping bugs that would have produced
one-star reviews rather than a rejection: the pre-prayer reminder fired at the
wrong time for every user outside UTC+1, and the Adhan silently never sounded
at all when the exact-alarm permission was withheld.

The remaining 12 points are not code problems. They are the Play Console forms,
the signing key, the store artwork, and one genuine policy judgement call
(`FOREGROUND_SERVICE_SPECIAL_USE`) that only a reviewer can settle — all
detailed under Remaining Manual Items and Risk Assessment.

---

## Changes Made

### Android build & signing

| File | Change |
|---|---|
| `android/app/build.gradle.kts` | `applicationId` `com.example.myadhan` → `com.ki1lux.adhani`; namespace to match; real release `signingConfig` from `key.properties` with a loud warning on fallback; `minSdk`/`targetSdk`/`compileSdk` pinned to 24/36/36; `resourceConfigurations` limited to ar+en; packaging excludes; lint on release builds |
| `android/settings.gradle.kts` | AGP 8.7.0 → 8.11.1 (8.7.0 does not officially support `compileSdk 36`) |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle 8.10.2 → 8.13 (required by AGP 8.11.1) |
| `android/gradle.properties` | `enableJetifier` off (dead weight — every dependency is AndroidX); JVM heap reduced from 8G/4G metaspace to 4G/1G; parallel + build cache on |
| `android/key.properties.example` | **New** — upload-key template with instructions |
| `.gitignore` | `key.properties`, `*.jks`, `*.keystore`, `local.properties` |

### Package rename (11 files)

`android/app/src/main/kotlin/com/example/myadhan/**` →
`android/app/src/main/kotlin/com/ki1lux/adhani/**`, with the package
declaration, the `ACTION_PRAYER_UPDATED` / `STOP_ADHAN` broadcast actions, the
manifest, the ProGuard keep rules and the docs all moved in the same step.

### AndroidManifest.xml

Rewritten. Removed `ACCESS_BACKGROUND_LOCATION`, `USE_FULL_SCREEN_INTENT`,
`ACCESS_NOTIFICATION_POLICY`, the `org.apache.http.legacy` `<uses-library>`,
the invalid `android:exported` on `<application>`, three unused notification
`<meta-data>` entries, and three hand-declared `flutter_local_notifications`
receivers (the plugin declares its own correctly — one of the hand-written ones
was **exported**, letting any installed app trigger it). Added
`ACCESS_NETWORK_STATE`, `supportsRtl`, `allowBackup="false"`, string resources
for the labels, and a real special-use FGS subtype. Changed the compass
`uses-feature` to `required="false"`.

### Kotlin

| File | Change |
|---|---|
| `AlarmSchedulerHelper.kt` | Exact-alarm permission checked before `setAlarmClock`, with an inexact `setAndAllowWhileIdle` fallback (previously a swallowed `SecurityException` = silent no-alarm); same for the widget-refresh alarm; month-cache JSON parsed **once** per reschedule instead of up to five times on a broadcast receiver's main thread |
| `MainActivity.kt` | Rewritten: every handler wrapped so an exception can't cross the channel unhandled; `ActivityNotFoundException` guarded on all four settings intents (an OEM without the exact-alarm screen used to crash); defensive numeric parsing of `triggerAtMillis`; new `previewAdhan` / `stopAdhanPreview` / `shareApp` / `openNotificationSettings`; preview stopped on `onStop`, guarded so it can never silence a real Adhan |
| `AdhanAlarmService.kt` | Removed the 2-second notification watchdog that re-posted the notification the user had just dismissed (user-hostile and a repeating handler); added a 6-minute hard playback ceiling so a wedged `MediaPlayer` can't hold a foreground service and wake lock indefinitely; `RECEIVER_NOT_EXPORTED` on the volume-change receiver for Android 14+ |
| `PrayerCountdownService.kt` | **Tick rate is now screen-aware**: 1 s while the display is on, 60 s while it is off (was 1 s unconditionally — ~86,400 notification rebuilds a day, ~98% of them invisible); a screen-on broadcast snaps back instantly with an immediate repaint; honours a new user preference and stops itself when switched off; countdown digits pinned to `Locale.US` so they don't render as Arabic-Indic numerals on some locales |
| `PrayerWidgetProvider.kt` | Ten `Resources.getIdentifier("text_name_$i")` lookups replaced with compile-checked `R.id` constants — a reflection-shaped lookup that R8 cannot see and that fails silently (blank widget, no exception) |

### Dart

| File | Change |
|---|---|
| `lib/services/local_timezone.dart` | **New.** Resolves `tz.local` from the device by matching UTC offsets across five points in the year. Replaces `tz.setLocalLocation(tz.getLocation('Africa/Algiers'))` |
| `lib/services/app_logger.dart` | **New.** `logDebug` (compiled out of release) / `logWarning` |
| `lib/services/app_config.dart` | **New.** Single source for package id, store URLs, privacy-policy URL, support address |
| `lib/view/LocationDisclosure.dart` | **New.** The prominent disclosure Play requires before the location prompt |
| `lib/main.dart` | Timezone resolution before anything schedules; `registerDailyPrayerWorker` moved off the pre-`runApp` critical path; permissions requested in a sensible order behind the disclosure; exact-alarm prompt only when not already granted; `flutter_localizations` delegates + `supportedLocales`; text scaling clamped to 0.85–1.3; nav bar 58 → 64 dp (tap targets were 42 dp); per-tab `Semantics` labels; `FadeIndexedStack` now builds tabs lazily and wraps inactive ones in `TickerMode(false)` + `ExcludeSemantics` |
| `lib/prayer_alarm_scheduler.dart` | Plugin initialised once instead of on every call; both init paths agree on the status-bar icon; reminders scheduled against the real local zone; notification categories set; `cancelAll` no longer able to throw past the native cancel |
| `lib/view/SettingsScreen.dart` | Dead "full-screen notification" switch replaced with a working countdown-notification toggle; "Share app" and "Rate app" implemented (were `() {}`); privacy-policy and data-sources rows added; alarm-status dialog now reads real state (was permanently "no data"); calculation-method change now awaits the refetch before re-arming alarms (it used to arm the **previous** method's times); every `BuildContext`-after-`await` fixed; version string from a constant; 11 px caption colour raised above the 4.5:1 contrast floor |
| `lib/view/PrayerTimeScreen.dart` | Nominatim `User-Agent` unified and given a contact address, as OSM's usage policy requires; Adhan preview moved from `audioplayers` to the native `AdhanPlayer` — **removes ~7 MB of duplicated audio from the download** and makes the preview an honest rehearsal of the real alarm; leaked `TextEditingController` disposed; three `BuildContext`-across-`await` bugs fixed; `_showSoundDialog` guarded with `mounted` |
| `lib/view/QiblaScreen.dart` | Compass rebuilds coalesced to ~60 Hz with a 0.4° threshold (was one full-screen `setState` per magnetometer sample, 50–100/s); `Key?` → `super.key` |
| `lib/view/adhan_screen.dart` | The per-second clock tick no longer rebuilds the whole screen — only the time text listens, via a `ValueNotifier`; clock sized off `shortestSide` and clamped, fixing a guaranteed landscape/tablet overflow |
| `lib/view/AnalogClockView.dart` | Timer follows the ambient `TickerMode`, so the clock stops when its tab is off screen; `shouldRepaint` no longer unconditionally `true` |
| `lib/view/OfflineBanner.dart` | Dismiss button 24 dp → 48 dp with a semantics label |
| `lib/view/splash_screen.dart` | Fixed delays trimmed: ~2.85 s → ~1.35 s of pure waiting on every cold start; `mounted` guards between animation steps |
| `lib/providers/prayer_times_provider.dart` | 18 `print` calls → `logDebug` |
| `test/widget_test.dart` | Was the unmodified `flutter create` counter template — it **failed** on a clean checkout. Replaced with tests covering timezone resolution, the store URLs, the offline banner and the toast |

### Project configuration

- `analysis_options.yaml` — `flutter_lints` enabled (the `include:` line was
  commented out, which is why the codebase "had no issues"); `avoid_print` and
  `use_build_context_synchronously` promoted to **errors**
- `pubspec.yaml` — real description; `flutter_lints` moved out of the
  `flutter_launcher_icons` config block, where it had been indented as
  configuration and was therefore **not a dependency at all**;
  `flutter_localizations` added; the 7 MB of duplicated Adhan audio and two
  unreferenced SVGs dropped from the asset bundle
- New resources: `values/strings.xml`, `mipmap-anydpi-v26/*.xml` (adaptive +
  themed icons), `drawable-*/ic_launcher_foreground.png`
- `PRIVACY_POLICY.md`, `PLAY_STORE_CHECKLIST.md`, `PLAY_STORE_AUDIT.md`
- `CLAUDE.md` / `README.md` updated for the rename, the new lint baseline, the
  signing setup and the logging conventions

---

## Issues Fixed

### Security

1. **Release builds signed with the debug key.** Anyone can produce a
   debug-key-signed build; it also cannot be uploaded to Play.
2. **Exported third-party receiver.** `FlutterLocalNotificationsReceiver` was
   hand-declared with `android:exported="true"`, so any installed app could
   send it intents. Removed — the plugin declares it correctly itself.
3. **`ACCESS_BACKGROUND_LOCATION` requested but never used.** The most
   sensitive permission on Android, granted for nothing.
4. **User data in release logs.** 31 `print` calls (GPS coordinates, prayer
   schedules, city names) and ~90 Kotlin `Log.d/v/i` calls shipped to logcat.
5. **`allowBackup` defaulted to true**, so prayer state and cached coordinates
   were eligible for cloud backup and restore onto another device.
6. Verified absent: hardcoded secrets, API keys, tokens, debug endpoints,
   cleartext HTTP. Both APIs are keyless and HTTPS-only.

### Performance & battery

7. **The countdown foreground service ticked once a second, forever**,
   including with the screen off. Now 60 s while asleep — a ~98% reduction in
   wakeups for the app's single largest background cost.
8. **The Qibla compass called `setState` on the entire screen per magnetometer
   sample** (50–100/s), rebuilding the dial, distance card and info bar dozens
   of times per frame.
9. **The analog clock rebuilt the whole home screen once a second**, and kept
   ticking while its tab was off screen.
10. **All four screens were constructed during the first frame** — opening the
    app paid for the compass subscription, two audio players and a reverse
    geocode before the user had visited those tabs.
11. **~2.85 s of artificial splash delay** on every cold start, plus a
    `MethodChannel` round trip blocking `runApp`.
12. **~7 MB of duplicated audio** — the three Adhan recordings shipped twice,
    once in `res/raw/` for the alarm and once in `assets/` for the settings
    preview.
13. **The month-cache JSON was parsed up to five times per reschedule**, on a
    broadcast receiver's main thread, during the boot storm.
14. **A wedged `MediaPlayer` could hold a foreground service indefinitely** —
    no timeout existed on Adhan playback.
15. `CustomPainter.shouldRepaint` returning `true` unconditionally.

### UI

16. **"Share app" and "Rate app" were `() {}`** — visible, tappable, doing
    nothing. Reviewers tap every row.
17. **The "full-screen notification" switch controlled nothing** — not
    persisted, not read, and the app has never used a full-screen intent.
18. **The alarm-status dialog was permanently empty** — its data source was
    declared and never populated.
19. **Guaranteed layout overflow** on landscape phones and tablets: the clock
    was sized from screen *width* with no cap.
20. **A stale-data race on changing calculation method** — alarms were re-armed
    from the previous method's times, and success was announced before anything
    had been recalculated.
21. Hardcoded `'Adhani · 1.0'` version string, free to drift from `pubspec.yaml`.

### Accessibility

22. **The bottom navigation was four unlabelled SVGs** — TalkBack read "button,
    button, button, button" with no indication of the current tab.
23. **Tap targets below 48 dp**: nav items were 42 dp; the offline banner's only
    dismiss control was 24 dp.
24. **Unbounded text scaling** — every size in the app is a fixed logical pixel
    inside fixed-height rows; at the 2.0× Android permits, the prayer rows, the
    countdown and the nav bar all overflowed. Now clamped to 0.85–1.3.
25. **No localisation delegates at all**, despite an entirely Arabic UI — so
    Material's own strings and screen-reader announcements came out in English,
    and `DateFormat.jm(locale)` had no data to resolve against.
26. **Off-screen tabs were readable by the screen reader** — TalkBack walked all
    four at once.
27. Contrast: the 11 px version caption sat at ~2.9:1, below the 4.5:1 AA floor.

### Android

28. **Exact alarms failed silently.** Without `SCHEDULE_EXACT_ALARM`,
    `setAlarmClock` throws `SecurityException`; it was caught by a bare
    `catch (Exception)` and **the Adhan simply never sounded**, with no
    fallback and nothing to tell the user why. Now degrades to an inexact
    alarm, and the settings screen says so.
29. **The same failure took down the widget's per-prayer refresh.**
30. **`ActivityNotFoundException` crashes** on devices without the exact-alarm
    or battery-optimisation settings screens.
31. **The battery-settings Dart fallback launched
    `package:com.example.myadhan`** — not a launchable URI scheme, and naming
    the old package. It could never have worked.
32. `getIdentifier`-based widget view lookups, invisible to R8 and silent on
    failure.
33. Missing adaptive launcher icon — Android 8+ drew the legacy bitmap inside a
    white plate.
34. Android 14 `registerReceiver` flags missing on a system-broadcast receiver.
35. `minSdk`/`targetSdk` inherited from the Flutter tool rather than pinned.
36. No WorkManager keep rule under R8 — `PrayerUpdateWorker` is instantiated by
    name from the WorkManager database and nothing references its constructor.
37. Countdown digits formatted with the default locale.

### Flutter

38. **The pre-prayer reminder fired at the wrong time for every user outside
    UTC+1.** `tz.local` was pinned to `Africa/Algiers`; a user in Jakarta got
    their "4 minutes to Fajr" notification six hours late. The Adhan itself was
    unaffected (native alarms deal in epoch millis), which is exactly why this
    was easy to miss.
39. **`flutter_lints` was never actually a dependency** — mis-indented inside
    the `flutter_launcher_icons` block — and `analysis_options.yaml` had its
    `include:` commented out. `flutter analyze` reported "No issues found!" on
    a codebase with five `BuildContext`-across-`await` errors.
40. **Five `BuildContext`-after-`await` bugs**, three of them posting toasts
    through a `Navigator` that had just been popped.
41. **The test suite was the `flutter create` counter template** and failed on a
    clean checkout.
42. A leaked `TextEditingController` per visit to the location dialog.
43. The notification plugin re-initialised on every scheduling pass.
44. Two disagreeing notification icon settings; last one to initialise won.

### Play policy

45. `com.example.*` application id — automatic rejection.
46. No prominent location disclosure before the permission prompt.
47. No in-app privacy-policy link (required for apps requesting location).
48. Three permissions requested and never used, two of them requiring their own
    Play declaration forms.
49. `android.hardware.sensor.compass` marked `required="true"`, excluding every
    compass-less device from the listing for a feature the app already handles
    gracefully.
50. No user control over an ongoing foreground-service notification — the first
    thing Play looks for when reviewing a special-use FGS.

---

## Remaining Manual Items

Only things that genuinely cannot be done from the codebase.

1. **Generate and safeguard the upload keystore**, fill in
   `android/key.properties`, and enrol in Play App Signing. Commands are in
   `PLAY_STORE_CHECKLIST.md` §1. *(A private key cannot be generated for you,
   and must never be committed.)*
2. **Publish the privacy policy at a public URL.** `PRIVACY_POLICY.md` is
   written and the app already links to its GitHub location — the repository
   has to be made public, or the file hosted elsewhere and
   `AppConfig.privacyPolicyUrl` updated.
3. **Complete the Data Safety form.** A pre-filled answer table matching the
   code and the policy exactly is in the checklist §3.
4. **Submit the two foreground-service declarations** with justification text —
   draft wording for both is in the checklist §4. Have a screen recording ready.
5. **Content rating questionnaire, target-audience, ads and app-access
   declarations** — checklist §5. Note the app-access one: with no login,
   saying so explicitly avoids a rejection for "reviewer could not access the
   app".
6. **Store listing artwork**: 512×512 icon, 1024×500 feature graphic, and 2–8
   phone screenshots. None exist in the repo, and they are design work.
7. **Short and full store descriptions** (a suggested short description is in
   the checklist).
8. **Physical-device testing** of the alarm, Doze, reboot, widget and countdown
   paths — CLAUDE.md is explicit that emulators don't reproduce the Doze and
   battery-optimisation behaviour this app is built around. The full list,
   including "test outside UTC+1", is in checklist §7.
9. **Read the pre-launch report** from an internal-testing upload before
   promoting to production.

---

## Risk Assessment

Remaining risks, most likely first.

### 1. `FOREGROUND_SERVICE_SPECIAL_USE` — moderate risk

**Why it can't be resolved in code.** `specialUse` exists for cases no standard
type covers, and Play reviews each one individually against a written
justification. A live countdown genuinely has no standard type — it is not
media playback, not location tracking, not a data transfer. But reviewers do
reject `specialUse` when they judge a standard type would fit or the work could
be done another way, and that judgement is theirs, not something the code can
pre-satisfy.

**What has been done to improve the odds:** the subtype property now carries a
real description instead of the token `prayer_countdown_timer`; the user can
switch the notification off in Settings and the service then genuinely does not
run (checked on every start path, including boot); and the service no longer
burns a wakeup per second with the screen off, which is what an
efficiency-focused reviewer would object to.

**If it is rejected:** the countdown can be reworked to a periodic
`AlarmManager`-driven notification update (no foreground service, minute
granularity instead of seconds). That is a real feature downgrade, so it was
not done pre-emptively.

### 2. Location data safety declaration mismatch — low risk, high impact

A Data Safety form that disagrees with observed network behaviour is an
automatic rejection, and it is easy to under-declare "shared with third
parties" when the third party is an open API rather than an SDK. The app *does*
send coordinates to two external services, so both must be declared as shared.
The pre-filled table in the checklist matches the code and the policy; this is
only a risk if the form is filled in from memory instead.

### 3. `SCHEDULE_EXACT_ALARM` — low risk

Requested, and the user can grant or refuse it — that is the permission's
intended use and it doesn't need a Play declaration. Note the alternative:
`USE_EXACT_ALARM` is auto-granted without a prompt, and prayer-alarm apps
often qualify as "alarm clock" apps for it — but claiming it invites a policy
review that can go the other way. The lower-risk permission was kept
deliberately, now with a working inexact fallback when it is refused.

### 4. The chosen application id — low risk, but decide now

`com.ki1lux.adhani` was chosen to match the developer handle already shown in
the app. **It is permanent from the first upload.** If a different id is
wanted, change `applicationId` in `android/app/build.gradle.kts` and
`AppConfig.packageName`, and re-run the tests — before the first upload, this
is a two-line change; afterwards it is a new app listing.

### 5. Untested-on-hardware background behaviour — low risk, but unverified

The alarm, Doze, reboot and widget paths were changed (exact-alarm fallback,
screen-aware ticking, the countdown toggle) and verified by compilation and
static analysis only. This environment has no connected device. CLAUDE.md is
explicit that this class of change must be tested on physical hardware, and
checklist §7 lists exactly what to exercise.

### 6. Aladhan API availability — low risk

Every prayer time comes from one third-party API. The month-ahead cache makes
the app fully functional offline for ~30 days, so an outage degrades rather
than breaks it, and a reviewer would still see working prayer times. Worth
knowing rather than acting on.

### 7. Nominatim rate limiting — low risk

OpenStreetMap's Nominatim rate-limits heavy clients. The app calls it sparingly
(one reverse geocode when the location changes, and a debounced search only on
explicit user input), and the User-Agent now identifies the app and carries a
contact address as their usage policy asks — it previously sent two different
strings from the two call sites, neither with a contact. Should the app become
popular enough to be throttled, city names would degrade to the platform
geocoder and then to the last known name; prayer times, which come from a
different service, are unaffected.
