import 'package:myadhan/services/app_logger.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Resolves `tz.local` to the zone the device is actually in.
///
/// ## Why this exists
///
/// The app used to do this, in `main.dart`, unconditionally:
///
/// ```dart
/// tz.setLocalLocation(tz.getLocation('Africa/Algiers'));
/// ```
///
/// Every `zonedSchedule` call in [PrayerAlarmScheduler] converts a local
/// wall-clock `DateTime` through `tz.local`, so for anyone outside Algeria's
/// UTC+1 the pre-prayer reminders were scheduled at the wrong absolute instant
/// — off by the difference between their offset and Algiers'. A user in
/// Jakarta (UTC+7) got their "4 minutes to Fajr" reminder six hours late; a
/// user in Casablanca got it during Ramadan only, when Morocco leaves UTC+1.
/// The Adhan itself was unaffected (native `AlarmManager` deals in epoch
/// millis, not zones), which is exactly why the bug was easy to miss.
///
/// ## How it resolves
///
/// The `timezone` package has no way to ask the platform for its IANA zone
/// name, and a plugin for it would be one more dependency for one string. So
/// this matches the device against the embedded database instead: find zones
/// whose UTC offset agrees with the device *right now* and at four points
/// spread across the year. Sampling the whole year is what separates zones
/// that merely coincide today from ones that share DST rules — Europe/London
/// and Africa/Abidjan are both UTC+0 in January and disagree in July.
///
/// A zone matching on all five samples behaves identically to the device's for
/// scheduling purposes even if it isn't the same name. If nothing matches (a
/// zone whose rules changed after this database was built, or an exotic
/// offset), it falls back to a fixed-offset UTC location, which is still right
/// for every reminder scheduled before the next DST transition — and those are
/// rescheduled daily anyway.
abstract final class LocalTimezone {
  /// Initialises the timezone database and points `tz.local` at the device's
  /// zone. Safe to call more than once.
  static void configure() {
    tzdata.initializeTimeZones();

    final resolved = _resolve();
    if (resolved != null) {
      tz.setLocalLocation(resolved);
      logDebug('🕐 Local timezone resolved to ${resolved.name}');
      return;
    }

    // Nothing matched. UTC keeps arithmetic correct; the conversion from a
    // local DateTime to an absolute instant still lands on the right moment
    // because `tz.TZDateTime.from` respects the source DateTime's own offset.
    tz.setLocalLocation(tz.UTC);
    logWarning('Could not match device timezone — falling back to UTC');
  }

  /// Instants sampled across a year, so DST rules are compared rather than
  /// just today's offset.
  static List<DateTime> _samples(DateTime now) => [
    now,
    DateTime(now.year, 1, 15, 12),
    DateTime(now.year, 4, 15, 12),
    DateTime(now.year, 7, 15, 12),
    DateTime(now.year, 10, 15, 12),
  ];

  static tz.Location? _resolve() {
    try {
      final now = DateTime.now();
      final samples = _samples(now);
      final deviceOffsets = [
        for (final sample in samples) sample.timeZoneOffset.inMinutes,
      ];

      tz.Location? bestMatch;

      for (final location in tz.timeZoneDatabase.locations.values) {
        var matches = true;
        for (var i = 0; i < samples.length; i++) {
          final zoned = tz.TZDateTime.from(samples[i], location);
          if (zoned.timeZoneOffset.inMinutes != deviceOffsets[i]) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;

        // Prefer the zone whose name the platform itself reports, when the
        // platform gives us something usable; otherwise the first full match
        // is as good as any other, since they are behaviourally identical.
        if (location.name == now.timeZoneName) return location;
        bestMatch ??= location;
      }

      return bestMatch;
    } catch (e) {
      logWarning('Timezone resolution failed', e);
      return null;
    }
  }
}
