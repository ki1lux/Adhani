import 'package:flutter/foundation.dart';

/// Debug-only logging.
///
/// The app used to call `print()` in ~30 places, several of them on the hot
/// path (a fetch logs the user's coordinates; the day-rollover timer logs the
/// prayer schedule). `print` is **not** stripped from release builds — every
/// one of those lines lands in logcat on a user's device, where any app
/// holding READ_LOGS on an older OS, or anyone with adb, can read it. It also
/// costs real time: `print` is synchronous and each call formats its
/// interpolated string whether or not anyone will ever read it.
///
/// [debugPrint] is already rate-limited by Flutter, and the [kDebugMode] guard
/// means the argument expression is never even evaluated in a release build.
void logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Something went wrong, but the app carried on.
///
/// Kept in release builds — unlike [logDebug] — because this is the class of
/// message that makes a user's bug report actionable. It deliberately carries
/// no user data: pass a description of *what* failed, not the values involved.
void logWarning(String message, [Object? error]) {
  debugPrint(error == null ? '⚠️ $message' : '⚠️ $message: $error');
}
