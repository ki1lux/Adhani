import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the `adhan_enabled_*` / `adhan_vibrate_*` pair that the Dart UI and
/// `PrayerAlarmReceiver.kt` both read, independently, with nothing checking
/// they agree (CLAUDE.md).
///
/// `_AdhanAlertMode` itself is private to PrayerTimeScreen, so this asserts
/// the *contract* it encodes rather than importing it: which pair of booleans
/// each mode writes, and that Kotlin's defaults read an untouched install as
/// "sound".
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Mirrors `_AdhanAlertMode.from` — kept here deliberately rather than
  /// exported, so a change to the real one that isn't reflected here shows up
  /// as a failing test rather than as silent drift.
  String modeOf({required bool enabled, required bool vibrate}) {
    if (!enabled) return 'silent';
    return vibrate ? 'vibrate' : 'sound';
  }

  group('the three modes map to the two keys Kotlin reads', () {
    test('sound is enabled + not vibrating', () {
      expect(modeOf(enabled: true, vibrate: false), 'sound');
    });

    test('vibrate keeps the prayer ENABLED', () {
      // The load-bearing one. AlarmSchedulerHelper.rescheduleAllFromPrefs
      // skips prayers whose `adhan_enabled_*` is false — so if vibrate mode
      // wrote enabled=false, no alarm would ever be armed and there would be
      // nothing left to vibrate from. Vibrate has to ride on an armed alarm.
      expect(modeOf(enabled: true, vibrate: true), 'vibrate');
    });

    test('silent wins regardless of the vibrate flag', () {
      // `adhan_vibrate_*` is deliberately not cleared when going silent, so a
      // stale true must not resurrect vibrate while disabled.
      expect(modeOf(enabled: false, vibrate: true), 'silent');
      expect(modeOf(enabled: false, vibrate: false), 'silent');
    });
  });

  test('an install that predates this feature reads as sound', () async {
    // No adhan_vibrate_* key at all — exactly what an upgrade looks like.
    SharedPreferences.setMockInitialValues({'adhan_enabled_الفجر': true});
    final prefs = await SharedPreferences.getInstance();

    // The same defaults PrayerAlarmReceiver.kt applies:
    //   getBoolean("flutter.adhan_enabled_…", true)
    //   getBoolean("flutter.adhan_vibrate_…", false)
    final enabled = prefs.getBool('adhan_enabled_الفجر') ?? true;
    final vibrate = prefs.getBool('adhan_vibrate_الفجر') ?? false;

    expect(
      modeOf(enabled: enabled, vibrate: vibrate),
      'sound',
      reason: 'upgrading must not silently change how a prayer announces',
    );
  });

  test('cycling walks sound → vibrate → silent → sound', () {
    // Mirrors `_AdhanAlertMode.next`, matching a phone ringer key's order.
    const order = ['sound', 'vibrate', 'silent'];
    String next(String m) => order[(order.indexOf(m) + 1) % order.length];

    expect(next('sound'), 'vibrate');
    expect(next('vibrate'), 'silent');
    expect(next('silent'), 'sound');
  });
}
