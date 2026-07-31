# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get                    # install Dart deps
flutter analyze                    # static analysis (see analysis_options.yaml note below)
dart analyze <file>                # analyze a single file
flutter test                       # run all tests (currently only test/widget_test.dart)
flutter test test/widget_test.dart # run a single test file
flutter run                        # run on a connected device/emulator
flutter build apk                  # release build (Android)
```

Native Android (Kotlin) changes under `android/`: build/verify with Gradle from
the `android/` directory, e.g. `./gradlew :app:compileDebugKotlin` or
`./gradlew assembleDebug`. Requires a JDK on `PATH`.

There is no CI config in this repo (no `.github/workflows`).
`analysis_options.yaml` **does** enable `package:flutter_lints/flutter.yaml`,
and additionally promotes `avoid_print` and `use_build_context_synchronously`
to errors — the codebase is clean against that set, so a new analyzer finding
is a real regression, not pre-existing noise.

Release builds are signed from `android/key.properties` (gitignored; see
`android/key.properties.example`). Without that file the release build still
succeeds but is signed with the debug key and prints a warning — such an
artifact cannot be uploaded to Play.

Debug logging: use `logDebug`/`logWarning` from `lib/services/app_logger.dart`
on the Dart side (`logDebug` compiles out of release builds); on the Kotlin
side `Log.d/v/i` are stripped from release by an `-assumenosideeffects` rule in
`proguard-rules.pro`, so use `Log.w`/`Log.e` for anything that must survive.

**Test on a physical Android device when touching native background
behavior** (alarms, the countdown notification, boot recovery, the home
screen widget) — emulators don't reliably reproduce Doze/battery-optimization
behavior that this app is specifically built around.

## Architecture

Adhani is a Flutter app whose Dart UI is a relatively thin layer on top of a
deep, independent native Android (Kotlin) backend. The Kotlin side keeps
prayer alarms, a live countdown notification, and a home screen widget
running correctly even when the Flutter engine/Dart isolate is not running
(app killed, device rebooted) — most of the actual "hard" logic lives in
`android/app/src/main/kotlin/com/ki1lux/adhani/`, not in `lib/`.

### The shared-storage contract (the crux of the whole system)

Dart and Kotlin do not talk to each other for prayer data at runtime — they
both read/write the **same Android SharedPreferences file**
(`FlutterSharedPreferences`) and treat it as the source of truth:

- Dart (`shared_preferences` plugin) writes keys like `prayer_1_name`.
- The plugin silently stores those on disk with a `flutter.` prefix, so
  Kotlin reads the *same* key as `flutter.prayer_1_name` via raw
  `SharedPreferences`.

Key naming convention (prayer IDs are always `1..5` = Fajr, Dhuhr, Asr,
Maghrib, Isha, with Arabic names as the "name" value):
- `prayer_{id}_name`, `prayer_{id}_time` (`HH:mm`), `prayer_{id}_trigger_millis` (epoch ms, always resolved to the *next* occurrence)
- `adhan_enabled_{arabicName}` (bool), `adhan_sound_{arabicName}` (string)
- `last_latitude` / `last_longitude`, `calculation_method` (Aladhan API method id, default `19` = Algeria)
- `cached_hijri_date`, `city_name`, `last_prayer_update`

Any change to these key names or formats must be made on **both** the Dart
and Kotlin sides, or the two halves of the app go out of sync silently (no
compiler will catch a typo'd SharedPreferences key across languages).

### Three independent writers of prayer data

Because the app must keep working with the Dart isolate dead, there are
**three separate code paths** that fetch prayer times and write the keys
above — all must stay behaviorally consistent:

1. **Dart**, `PrayerAlarmScheduler.scheduleAllPrayersWithData()`
   (`lib/prayer_alarm_scheduler.dart`) — driven by `prayerTimesProvider`
   (Riverpod), called from `main.dart` after permissions are granted and
   again whenever the user changes location/settings. Writes the prefs, then
   calls the native `scheduleNativePrayerAlarm` method per enabled prayer and
   finally `rescheduleFromPrefs` (see below).
2. **Kotlin**, `PrayerUpdateWorker` — a WorkManager periodic job (~24h,
   anchored to 00:05) that independently fetches from the Aladhan API via
   `AladhanApiClient.kt` (a from-scratch `HttpURLConnection` client — **not**
   a call back into Dart) as a resilience fallback.
3. **Kotlin**, `PrayerCountdownService.fetchFreshDataDirectly()` — a third,
   faster fetch path the foreground countdown service triggers itself the
   moment it detects the calendar day has rolled past Isha+35m, so the live
   countdown doesn't have to wait for the WorkManager job to run.

`lib/services/prayer_times_api_service.dart` (Dart) and
`AladhanApiClient.kt` (Kotlin) are two **independent implementations** of the
same Aladhan HTTP API call (including the same per-prayer minute-offset
adjustments) — they must be changed together if the API contract or offsets
change.

All three writers must end by calling `AlarmSchedulerHelper.rescheduleAllFromPrefs()`
(directly, or via the `rescheduleFromPrefs` MethodChannel call from Dart) —
that function is the single place that actually arms `AlarmManager`, for two
independent purposes:
- `scheduleAlarm()` — a high-priority `setAlarmClock` alarm → `PrayerAlarmReceiver`
  → `AdhanAlarmService`, only for prayers with Adhan enabled.
- `scheduleWidgetRefresh()` — a silent `setExactAndAllowWhileIdle` alarm that
  just re-broadcasts `ACTION_PRAYER_UPDATED` to `PrayerWidgetProvider`,
  armed **regardless** of whether Adhan is enabled for that prayer, so the
  home screen widget still transitions to the next prayer on time.

### Dart ↔ Kotlin bridge

A single `MethodChannel('com.myadhan/notification')`, handled in
`MainActivity.kt`, is the entire bridge surface: `scheduleNativePrayerAlarm`,
`cancelAllNativeAlarms`, `rescheduleFromPrefs`, `registerDailyPrayerWorker`,
`startCountdownService` / `stopCountdownService`, `startAdhanService`, and the
exact-alarm permission checks. There's no plugin/pigeon codegen — it's a
hand-written `when (call.method)` switch.

### Home screen widget

`PrayerWidgetProvider` does **not** trust `trigger_millis` blindly — it
re-derives "which prayer is next" and "which have passed today" itself by
re-parsing the `HH:mm` time strings against the current time on every update.
This is deliberate: it stays correct even if a per-prayer `trigger_millis`
write was skipped or is stale (e.g. previously happened for Adhan-disabled
prayers before that was fixed).

### Countdown & Adhan playback

- `PrayerCountdownService` — foreground service, ticks every 1s via
  `postAtTime(SystemClock.uptimeMillis)` (Doze-resilient), and distinguishes
  "counting down to next prayer" from "currently in the Iqamah window" (15
  min after Maghrib, 30 min after other prayers) as separate states.
- `PrayerAlarmReceiver` (fired by the `AlarmManager` alarm above) starts
  `AdhanAlarmService`, which plays audio via `AdhanPlayer`
  (`AdhdanPlayer.kt`) on the `ALARM` audio stream so it isn't ducked, using a
  custom `RemoteViews` notification with a Stop action.
- `BootReceiver` re-arms everything (`AlarmSchedulerHelper.rescheduleAllFromPrefs`
  + countdown service) after reboot/app-update.

### Dart app structure (`lib/`)

- `providers/` — Riverpod `StateNotifierProvider`s; `prayerTimesProvider` is
  the main one, wrapping fetch/refresh/day-rollover-timer logic.
- `controller/` — thin wrappers around device APIs (`geolocator`/`geocoding`
  for location, `flutter_qiblah` for the compass).
- `services/` — the Dart-side Aladhan API client.
- `model/` — plain data classes (`PrayerTimeModel`, etc.), no serialization
  magic.
- `view/` — screens, wired together via `MainScreen`'s custom
  `FadeIndexedStack` (a state-preserving cross-fade alternative to
  `IndexedStack`) in `main.dart`, not a `Navigator`/route-based flow.
- `prayer_alarm_scheduler.dart` lives at the `lib/` root (not under any of
  the above folders) since it's the cross-cutting bridge into the native
  side described above.

Note the actual dependencies in `pubspec.yaml` diverge from what
`README.md` describes: audio is `audioplayers` (README says `just_audio`),
and there is no `adhan` calculation package — all prayer times, in both Dart
and Kotlin, come from the remote Aladhan HTTP API, not local astronomical
calculation.

### Design system

`DESIGN_IDENTITY.md` at the repo root documents the locked visual identity
(color roles, icon/logo style, the single Cairo typeface used for both
Arabic and Latin text, corner-radius scale) — read it before making any
theming/visual changes.
