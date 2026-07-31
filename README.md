# Adhani — أذاني

<div align="center">
  <img src="assets/mainIcon.png" width="150" alt="Adhani Logo">
  <br/>
  <em>Prayer times, the Adhan, and the Qibla — working even with no connection.</em>
  <br/><br/>

  [![Flutter](https://img.shields.io/badge/Flutter-3.7.2+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
  [![Dart](https://img.shields.io/badge/Dart-3.7+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
  [![Kotlin](https://img.shields.io/badge/Kotlin-Native_Android-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)](https://kotlinlang.org)
  [![Android](https://img.shields.io/badge/Android-24_→_36-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com)
</div>

## About

**Adhani** is an Arabic-first Islamic app built with Flutter on top of a deep
native Android backend. It gives you accurate location-based prayer times, a
live countdown to the next prayer, the call to prayer at the right minute, and
a Qibla compass.

The hard part of an app like this isn't the UI — it's staying correct when
nobody is looking at it. Adhani puts most of its real logic in native Kotlin so
that alarms, the countdown notification and the home-screen widget keep working
when the app is killed, the device is rebooted, or there's no connection for a
month.

## Features

- **Accurate prayer times** — fetched from the [Aladhan API](https://aladhan.com/prayer-times-api)
  for your exact coordinates, with **23 calculation methods** to choose from
  (Umm al-Qura, ISNA, Muslim World League, Egypt, Turkey, and more).
- **Genuinely offline** — one request caches a **full month ahead**, so prayer
  times, alarms, the countdown and the widget all keep working with no network.
  Reconnecting refreshes automatically.
- **Reliable Adhan alarms** — `AlarmManager.setAlarmClock` survives Doze, and
  the alarms re-arm themselves every time one fires, so they never run out.
  Falls back to an inexact alarm if you decline the exact-alarm permission,
  rather than going silent.
- **Three Adhan recordings** — chosen per prayer, played on the alarm audio
  stream so notification sounds can't duck them. Preview each one in settings.
- **Live countdown notification** — an ongoing notification counting down to
  the next prayer, and up through the Iqamah window after it. Can be switched
  off entirely.
- **Home-screen widget** — the day's five prayers, a progress ring, and a live
  chronometer to the next one. Re-derives what's next on every update, so it
  stays right even when data is stale.
- **Qibla compass** — a smooth needle to Mecca from the device's
  magnetometer, with haptic and audio feedback as you approach alignment, and
  your great-circle distance to the Kaaba.
- **Hijri date** — turns over at Maghrib, when the Islamic day actually
  begins, not at midnight.
- **Survives reboots and updates** — `BootReceiver` re-arms everything.
- **No accounts, no analytics, no ads** — see [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Architecture

The Dart UI is a relatively thin layer over an independent native Android
backend. The two halves **do not talk to each other at runtime** — they share
one `SharedPreferences` file as the source of truth, so the native side stays
fully functional with the Flutter engine dead.

```
┌───────────────────────────┐        ┌──────────────────────────────┐
│   Flutter / Dart (lib/)   │        │  Native Android (Kotlin)     │
│                           │        │                              │
│  Riverpod providers       │        │  AlarmSchedulerHelper        │
│  4 screens                │        │  PrayerCountdownService (FGS)│
│  Aladhan client           │        │  AdhanAlarmService + Player  │
│  Month cache              │        │  PrayerUpdateWorker          │
│                           │        │  PrayerWidgetProvider        │
└───────────┬───────────────┘        └──────────────┬───────────────┘
            │                                       │
            │        FlutterSharedPreferences       │
            └──────────────►  (shared state)  ◄─────┘
                         prayer_{id}_time
                         prayer_{id}_trigger_millis
                         prayer_month_cache …
                                   ▲
                    MethodChannel('com.myadhan/notification')
                       — used only for commands, not data
```

**Three independent writers** of prayer data keep it consistent no matter what
is or isn't running: the Dart scheduler, a WorkManager job that fetches on its
own (a from-scratch Kotlin HTTP client — *not* a callback into Dart), and the
countdown service's own fast path at the day rollover. All three end by
re-arming alarms from the same shared prefs.

See [CLAUDE.md](CLAUDE.md) for the full contract, including the exact key names
that must stay in sync across both languages.

## Tech Stack

### Flutter

| Concern | Package |
|---|---|
| State management | [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) |
| Prayer times | [`http`](https://pub.dev/packages/http) → Aladhan API |
| Location | [`geolocator`](https://pub.dev/packages/geolocator), [`geocoding`](https://pub.dev/packages/geocoding) |
| Qibla | [`flutter_qiblah`](https://pub.dev/packages/flutter_qiblah) |
| Audio | [`audioplayers`](https://pub.dev/packages/audioplayers) (compass feedback) |
| Notifications | [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications), [`timezone`](https://pub.dev/packages/timezone) |
| Storage | [`shared_preferences`](https://pub.dev/packages/shared_preferences) |
| Connectivity | [`connectivity_plus`](https://pub.dev/packages/connectivity_plus) |
| Permissions | [`permission_handler`](https://pub.dev/packages/permission_handler) |
| UI | [`flutter_svg`](https://pub.dev/packages/flutter_svg), [`intl`](https://pub.dev/packages/intl), Cairo variable font |

> **Note:** prayer times come from the remote Aladhan API on *both* sides —
> there is no local astronomical calculation library. The Adhan recordings play
> through the native player, not `audioplayers`.

### Native Android (Kotlin)

| Component | Role |
|---|---|
| `AlarmSchedulerHelper` | The single place `AlarmManager` is armed — Adhan alarms and silent widget-refresh alarms |
| `PrayerAlarmReceiver` | Fires at prayer time, starts playback, re-arms the next day |
| `AdhanAlarmService` / `AdhanPlayer` | Foreground media playback on the alarm stream, with audio focus |
| `PrayerCountdownService` | Foreground service driving the live countdown notification |
| `PrayerUpdateWorker` | Daily WorkManager sync, cache-first so it works offline |
| `PrayerWidgetProvider` | Home-screen widget, drawn with `RemoteViews` + generated bitmaps |
| `PrayerMonthCache` | Kotlin mirror of the Dart month cache |
| `AladhanApiClient` | Dependency-free `HttpURLConnection` client |
| `BootReceiver` | Restores everything after reboot or app update |

## Project Structure

```text
Adhani/
├── android/app/src/main/
│   ├── kotlin/com/ki1lux/adhani/   # Native backend: services, receivers, workers, widget
│   └── res/                        # Widget & notification layouts, Adhan audio, icons
├── assets/                         # SVG icons, compass graphics, sound effects
├── lib/
│   ├── controller/                 # Thin wrappers over device APIs (location, compass)
│   ├── model/                      # Plain data classes
│   ├── providers/                  # Riverpod state (prayerTimesProvider is the main one)
│   ├── services/                   # Aladhan client, month cache, timezone, config, logging
│   ├── theme/                      # The locked colour palette
│   ├── view/                       # Screens and shared widgets
│   └── prayer_alarm_scheduler.dart # The cross-cutting bridge into the native side
├── test/                           # Cache wire-format, timezone and widget tests
├── CLAUDE.md                       # Architecture & shared-storage contract
├── DESIGN_IDENTITY.md              # Locked visual identity
├── PRIVACY_POLICY.md
└── PLAY_STORE_CHECKLIST.md         # Release checklist
```

## Screenshots

| Home | Qibla Compass | Prayer Times |
|:---:|:---:|:---:|
| <img width="240" alt="Home screen with analog clock and next prayer countdown" src="https://github.com/user-attachments/assets/7af0c2a4-e038-441b-b7c2-208165dbd679" /> | <img width="240" alt="Qibla compass" src="https://github.com/user-attachments/assets/ddc2f61b-c534-4069-b469-473760e41c7e" /> | <img width="240" alt="Daily prayer times list" src="https://github.com/user-attachments/assets/9207f318-b1ca-4633-b55d-c2d7eec5aa09" /> |

## Getting Started

### Prerequisites

- Flutter SDK **3.7.2+**
- JDK 17
- Android SDK — `minSdk 24`, `compileSdk`/`targetSdk 36`

### Run it

```bash
git clone https://github.com/ki1lux/Adhani.git
cd Adhani
flutter pub get
flutter run
```

No API keys or `.env` file are needed — the Aladhan and Nominatim APIs are both
keyless.

> **Test background behaviour on a physical Android device.** Emulators
> don't reproduce the Doze and battery-optimisation behaviour this app is
> specifically built around, and that covers alarms, the countdown
> notification, boot recovery and the widget.

### Everyday commands

```bash
flutter analyze                       # static analysis (flutter_lints, clean)
flutter test                          # run the test suite
flutter build apk --release           # release APK
flutter build appbundle --release     # Play Store bundle

cd android && ./gradlew :app:compileDebugKotlin   # verify native changes
```

### Release signing

Release builds are signed from `android/key.properties`, which is **not** in
version control:

```bash
keytool -genkey -v -keystore ~/adhani-upload.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias upload

cp android/key.properties.example android/key.properties   # then fill it in
```

Without that file the release build still succeeds but is signed with the debug
key and prints a warning — such a build cannot be uploaded to Google Play.
Full pre-launch steps are in [PLAY_STORE_CHECKLIST.md](PLAY_STORE_CHECKLIST.md).

## Privacy

Adhani has no accounts, no analytics and no ads, and the developer runs no
server. Your coordinates are sent to two services — Aladhan (to calculate the
times) and OpenStreetMap Nominatim (to name your city) — and nothing else
leaves the device. Location is never read in the background, and the app works
without the permission at all if you pick your city by hand.

Full details: [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Contributing

Issues and pull requests are welcome. Two things worth knowing first:

1. **Shared preference keys are a cross-language contract.** Change one on the
   Dart side and you must change it on the Kotlin side in the same commit — no
   compiler will catch a typo across that boundary. See CLAUDE.md.
2. **The visual identity is locked** in [DESIGN_IDENTITY.md](DESIGN_IDENTITY.md).
   Read it before any theming change.

Please make sure `flutter analyze` and `flutter test` are clean before opening
a PR.

## Credits

- Prayer times & Hijri dates — [Aladhan API](https://aladhan.com/) by Islamic Network
- Place names — [OpenStreetMap Nominatim](https://nominatim.openstreetmap.org/)
- Typeface — [Cairo](https://fonts.google.com/specimen/Cairo)

---

<div align="center">
  Made with Flutter &amp; Kotlin — by <a href="https://github.com/ki1lux">ki1lux</a>
</div>
