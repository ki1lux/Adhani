# Play Store Release Checklist — Adhani

**App:** Adhani (أذاني) · `com.ki1lux.adhani` · v1.0.0 (versionCode 1)
**Status of this checklist:** everything under "Done in code" is finished and
verified by a release build. Everything under "You must do" needs a human — a
Play Console form, a private key, or a design asset.

---

## ✅ Done in code (no action needed)

### Build & release configuration

- [x] `applicationId` changed from `com.example.myadhan` → **`com.ki1lux.adhani`**
      (Play rejects any `com.example.*` package outright)
- [x] Kotlin package + namespace renamed to match; all 11 native source files,
      broadcast actions and ProGuard rules updated together
- [x] Release build **no longer signed with the debug key** — reads
      `android/key.properties`, warns loudly and refuses to pretend otherwise
      when that file is missing
- [x] `key.properties`, `*.jks`, `*.keystore` and `local.properties` gitignored
- [x] `targetSdk = 36`, `compileSdk = 36`, `minSdk = 24` pinned explicitly
- [x] AGP 8.11.1 + Gradle 8.13 (the previous 8.7.0 didn't officially support
      compileSdk 36)
- [x] R8 + resource shrinking on, with keep rules verified against a real
      release build (WorkManager, notification models, widget provider)
- [x] Release build, `bundleRelease`, `lintVitalRelease`, `flutter analyze` and
      `flutter test` all pass clean

### Permissions (Play's most common rejection cause)

- [x] **Removed `ACCESS_BACKGROUND_LOCATION`** — never used, and it requires a
      Play declaration form plus a demo video
- [x] **Removed `USE_FULL_SCREEN_INTENT`** — never used; restricted to
      alarm/calling apps on Android 14+
- [x] **Removed `ACCESS_NOTIFICATION_POLICY`** — never used
- [x] Removed the `org.apache.http.legacy` `<uses-library>` and the invalid
      `android:exported` on `<application>`
- [x] Final merged manifest audited: 12 permissions, every one exercised by code
- [x] `android.hardware.sensor.compass` changed from `required="true"` to
      `required="false"` — it was excluding every compass-less device from the
      listing, for a feature the app already degrades gracefully without

### Privacy & security

- [x] **Prominent location disclosure** added before the runtime permission
      prompt, naming the two services coordinates are sent to (Play's User Data
      policy requires this; its absence is a top-5 first-submission rejection)
- [x] Privacy-policy link added inside the app (Settings → سياسة الخصوصية)
- [x] `PRIVACY_POLICY.md` written and ready to publish
- [x] Data-sources disclosure screen added (Settings → مصادر البيانات)
- [x] No hardcoded secrets, API keys or tokens anywhere (both APIs are keyless)
- [x] All network traffic is HTTPS; no cleartext permitted
- [x] 31 `print()` calls (coordinates, prayer schedules) replaced with a
      debug-only logger — they were shipping to logcat in release
- [x] ~90 Kotlin `Log.d/v/i` calls stripped from release by an R8
      `-assumenosideeffects` rule
- [x] `android:allowBackup="false"` — no stale alarm state restored onto a new
      device

### Store-listing plumbing

- [x] `pubspec.yaml` description replaced ("A new Flutter project.")
- [x] Adaptive launcher icon (+ themed monochrome) added for Android 8+
- [x] App label and widget label moved to `strings.xml`
- [x] Widget picker description + preview layout added
- [x] "Share app" and "Rate app" rows now work (both were `() {}`)
- [x] In-app version string reads from a single constant instead of a
      hardcoded `1.0`

---

## 📋 You must do (Play Console / your machine)

### 1. Signing key — **blocking**

```bash
keytool -genkey -v -keystore ~/adhani-upload.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties
# fill in storePassword / keyPassword / keyAlias / storeFile
flutter build appbundle --release
```

- [ ] Generate the upload keystore (above)
- [ ] Fill in `android/key.properties` — **never commit it**
- [ ] Back the keystore up somewhere you will still have in five years; losing
      it means losing the ability to update the app
- [ ] Enrol in **Play App Signing** (Play Console → Setup → App signing) so
      Google holds the app signing key and yours is only the upload key
- [ ] Confirm the build prints no "signing with the DEBUG key" warning

### 2. Privacy policy URL — **blocking**

- [ ] Push `PRIVACY_POLICY.md` and make the repo public, or host it elsewhere
- [ ] Confirm the URL loads in a browser while signed out
- [ ] If you host it elsewhere, update `AppConfig.privacyPolicyUrl` in
      `lib/services/app_config.dart`
- [ ] Enter the URL in Play Console → App content → Privacy policy

### 3. Data Safety form — **blocking**

Answer it to match `PRIVACY_POLICY.md` exactly. A mismatch is an automatic
rejection. Based on what the code actually does:

| Question | Answer |
|---|---|
| Does your app collect or share user data? | **Yes** |
| Data type | **Location → Approximate location** and **Precise location** |
| Collected or shared? | **Collected and shared** (sent to Aladhan and Nominatim) |
| Is it processed ephemerally? | **Yes** — sent per request, not stored on any server you operate |
| Is collection required? | **No** — the app works with a manually chosen city |
| Purpose | **App functionality** only |
| Encrypted in transit? | **Yes** (HTTPS) |
| Can users request deletion? | **Not applicable** — no server-side data; uninstalling removes everything |
| Any other data types | **None** — no personal info, no identifiers, no analytics, no ads |

### 4. Foreground service declarations — **blocking**

Play Console → App content → **Foreground service permissions**. Two entries:

- [ ] **`FOREGROUND_SERVICE_SPECIAL_USE`** (the countdown notification). This
      is the single highest-risk item in the submission — see the Risk
      Assessment in `PLAY_STORE_AUDIT.md`. Suggested justification:

  > The app shows an ongoing notification with a live countdown to the next
  > prayer time. It must stay accurate while the app is closed and the device
  > is idle, and no standard foreground service type describes a user-visible
  > timer. The user can disable this notification entirely in the app's
  > settings, and the service does not run when they do.

- [ ] **`FOREGROUND_SERVICE_MEDIA_PLAYBACK`** (the Adhan). Suggested
      justification:

  > Plays the recorded call to prayer at the scheduled prayer time on the alarm
  > audio stream. Playback is user-initiated by their configured prayer
  > schedule, is visible as a notification with a stop control, and stops when
  > the recording finishes.

- [ ] Record a short screen capture of each in use — Play often asks

### 5. Other App content declarations

- [ ] **Target audience & content**: general audience, not child-directed
- [ ] **Ads**: No — the app contains no ads
- [ ] **Content rating questionnaire**: expect Everyone / PEGI 3
- [ ] **News app**: No
- [ ] **Government app**: No
- [ ] **Financial features**: None
- [ ] **Data deletion**: no account, so declare "no account creation"
- [ ] **App access**: no login required — say so, or reviewers will ask for
      credentials and reject for lack of access

### 6. Store listing assets

| Asset | Requirement | Status |
|---|---|---|
| App icon | 512×512 PNG, 32-bit, no alpha | ⬜ Export from `assets/mainIcon.png` |
| Feature graphic | 1024×500 PNG/JPG, no alpha | ⬜ Not in repo — must be designed |
| Phone screenshots | 2–8, min 320px, 16:9 or 9:16 | ⬜ Not in repo |
| 7" tablet screenshots | Optional but improves ranking | ⬜ |
| 10" tablet screenshots | Optional | ⬜ |
| Short description | ≤ 80 chars | ⬜ |
| Full description | ≤ 4000 chars | ⬜ |
| Promo video | Optional | ⬜ |

Suggested screenshots (one per screen, all four already look finished):
home with the analog clock and next-prayer card · the prayer times list ·
the Qibla compass · the home-screen widget on a launcher.

Suggested short description:
> مواقيت الصلاة والأذان واتجاه القبلة — تعمل بدون إنترنت

### 7. Device testing — **do not skip**

CLAUDE.md is explicit that native background behaviour must be tested on
physical hardware. Verify on a real device, not an emulator:

- [ ] Adhan sounds at the correct minute with the app **killed**
- [ ] Adhan sounds with the device in **Doze** (leave it idle overnight, or
      `adb shell dumpsys deviceidle force-idle`)
- [ ] Alarms survive a **reboot** (BootReceiver)
- [ ] Home-screen widget rolls over to the next prayer on time
- [ ] Countdown notification updates, and **stops when switched off** in
      Settings — this is the new behaviour Play will look for
- [ ] Denying the location permission still shows prayer times (manual city)
- [ ] Denying the exact-alarm permission still fires the Adhan (a few minutes
      late — this is the new inexact fallback)
- [ ] Airplane mode on a cold start still shows cached times
- [ ] **Test outside UTC+1** (change the device timezone) — the pre-prayer
      reminder used to be hardcoded to Africa/Algiers
- [ ] Screen reader (TalkBack) walk-through of all four tabs
- [ ] Largest system font size on the smallest screen you have

### 8. Release rollout

- [ ] Upload the `.aab` (not the `.apk`) to **internal testing** first
- [ ] Read the **pre-launch report** — it runs the app on real devices and
      surfaces crashes, ANRs and accessibility findings before users do
- [ ] Then promote to closed → open → production, or straight to a staged
      production rollout (start at 10–20%)

---

## Optional polish (not blocking)

- [ ] Re-run `dart run flutter_native_splash:create` — the Android 12+ splash
      currently shows the background colour with no icon, because the generated
      `windowSplashScreenAnimatedIcon` is transparent
- [ ] Delete `assets/audio/adhan1.mp3`, `adhan2.mp3`, `adhan3.mp3` and
      `assets/Vector1.svg` from the repo — they are no longer bundled (the
      preview now plays the `res/raw/` copies), so they are ~7.7 MB of dead
      weight in the working tree only
- [ ] `assets/Vector.svg` is 740 KB for a repeating background pattern; running
      it through an SVG optimiser would cut the download further
