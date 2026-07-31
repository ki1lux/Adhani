# Privacy Policy — Adhani (أذاني)

**Last updated:** 31 July 2026
**Applies to:** Adhani for Android (`com.ki1lux.adhani`)

Adhani is a prayer-times, Adhan and Qibla app. This policy explains exactly
what the app does with your data. It is short because the app collects very
little.

---

## Summary

- Adhani has **no accounts, no sign-in, and no analytics or advertising SDKs.**
- The developer operates **no server** and therefore **stores nothing about you.**
- Your **approximate location is sent to two third-party services** to calculate
  prayer times and to name your city. Nothing else leaves your device.
- Everything else — your prayer times, settings, chosen Adhan sound and cached
  calendar — is stored **only on your device**.

---

## What the app collects, and why

### Location

**What:** Your device's latitude and longitude, while the app is in use.

**Why:** Prayer times and the Qibla direction are both functions of where you
are; they cannot be calculated without coordinates.

**How it is used:** Your coordinates are sent to:

| Service | Operator | Purpose | Policy |
|---|---|---|---|
| Aladhan API (`api.aladhan.com`) | Islamic Network | Calculates the five daily prayer times and the Hijri date for your position | <https://aladhan.com/privacy-policy> |
| Nominatim (`nominatim.openstreetmap.org`) | OpenStreetMap Foundation | Resolves your coordinates into a city name for display | <https://osmfoundation.org/wiki/Privacy_Policy> |

Both requests are made over HTTPS and contain **only** coordinates and the
calculation settings — no device identifier, no account, nothing that
identifies you personally.

**Location is never collected while the app is in the background.** Adhani does
not request the `ACCESS_BACKGROUND_LOCATION` permission.

**You can decline.** If you refuse the location permission, the app keeps
working: you can choose your city by hand on the prayer-times screen, and the
app continues to use the last coordinates and calendar it cached.

Your last known coordinates are cached on your device so prayer times stay
correct while you are offline. They are not transmitted anywhere else.

### Everything stored on your device only

Held in the app's private storage, readable by no other app, and deleted when
you uninstall Adhani:

- Prayer times for the current and next month (so the app works offline)
- The Hijri date, your city name and last known coordinates
- Your settings: calculation method, which prayers play the Adhan, which Adhan
  recording, and whether the countdown notification is shown

None of this is backed up to the cloud — the app sets `allowBackup="false"`.

---

## What the app does **not** do

- No advertising, no ad identifiers, no ad networks
- No analytics, crash-reporting or telemetry SDKs
- No contacts, photos, microphone, camera, files or SMS access
- No data sold or shared with anyone for any purpose
- No user accounts, so no email address, name or password is ever collected

---

## Permissions the app requests, and why

| Permission | Why it is needed |
|---|---|
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | Calculate prayer times and the Qibla bearing for your position |
| `INTERNET`, `ACCESS_NETWORK_STATE` | Fetch prayer times; retry automatically when a connection returns |
| `POST_NOTIFICATIONS` | Show prayer alerts and the countdown notification |
| `SCHEDULE_EXACT_ALARM` | Sound the Adhan at the exact minute of each prayer. Without it, alerts still fire but may be a few minutes late |
| `RECEIVE_BOOT_COMPLETED` | Re-arm your prayer alarms after the device restarts |
| `WAKE_LOCK`, `VIBRATE` | Wake the device to play the Adhan; vibrate for reminders |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Play the Adhan reliably when the app is closed |
| `FOREGROUND_SERVICE_SPECIAL_USE` | Keep the live countdown notification accurate. You can switch this off in Settings |

---

## Children

Adhani is suitable for all ages and does not knowingly collect any data from
children. It has no accounts, no user-generated content and no advertising.

---

## Your choices

- **Decline location** at the disclosure prompt, or revoke it later in Android
  Settings → Apps → Adhani → Permissions. Choose your city manually instead.
- **Turn off the countdown notification** in the app's Settings screen.
- **Delete everything** by uninstalling the app; all stored data goes with it.

---

## Changes to this policy

If this policy changes, the "Last updated" date above changes with it and the
new version is published at this address before the change takes effect.

---

## Contact

Questions about this policy or your data:

**Ahmed Khalil Benfiala** — khalilbenfiala001@gmail.com
<https://github.com/ki1lux>
