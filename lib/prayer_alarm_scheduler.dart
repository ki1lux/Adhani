import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/services/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// Prayer Alarm Scheduler — uses native Android AlarmManager for persistent
/// alarms. These fire the Adhan even when the app is killed.
class PrayerAlarmScheduler {
  static const MethodChannel _channel = MethodChannel(
    'com.myadhan/notification',
  );
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Status-bar icon. Must be the white-on-transparent silhouette in
  /// `res/drawable/`, not the full-colour launcher icon: Android masks the
  /// small icon to a single colour, so a coloured bitmap renders as a solid
  /// white blob. This file previously disagreed with `main.dart` about which
  /// of the two to use, and whichever initialised last won.
  static const _smallIcon = '@drawable/ic_stat_adhan';

  /// One-time plugin init. This used to run on every call to
  /// [scheduleAllPrayersWithData] — which happens on launch, on every settings
  /// change and on every day rollover — re-registering the plugin's callbacks
  /// each time for no benefit.
  static bool _initialised = false;

  static Future<void> ensureInitialised() async {
    if (_initialised) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings(_smallIcon),
      iOS: DarwinInitializationSettings(),
    );
    await _notificationsPlugin.initialize(settings);
    _initialised = true;
  }

  /// Schedule all prayer alarms from a [PrayerTimeModel].
  static Future<void> scheduleAllPrayersWithData(PrayerTimeModel data) async {
    await ensureInitialised();

    // Cancel any existing alarms first
    await cancelAll();

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    final prayers = [
      {'id': 1, 'name': 'الفجر', 'time': data.fajer},
      {'id': 2, 'name': 'الظهر', 'time': data.dhuhr},
      {'id': 3, 'name': 'العصر', 'time': data.asr},
      {'id': 4, 'name': 'المغرب', 'time': data.maghrib},
      {'id': 5, 'name': 'العشاء', 'time': data.isha},
    ];

    for (final prayer in prayers) {
      final id = prayer['id'] as int;
      final name = prayer['name'] as String;
      final prayerTime = prayer['time'] as DateTime;
      final timeStr = DateFormat('HH:mm').format(prayerTime);

      // Build scheduled DateTime for today
      var scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        prayerTime.hour,
        prayerTime.minute,
      );

      // If prayer time has passed today, schedule for tomorrow
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      // Store prayer info + trigger timestamp (native side + widget read these
      // with the 'flutter.' prefix) for every prayer, even if adhan is
      // disabled — the widget still needs to show and track this prayer.
      await prefs.setString('prayer_${id}_name', name);
      await prefs.setString('prayer_${id}_time', timeStr);
      await prefs.setInt(
        'prayer_${id}_trigger_millis',
        scheduledTime.millisecondsSinceEpoch,
      );

      // Check if adhan is enabled for this prayer
      final isEnabled = prefs.getBool('adhan_enabled_$name') ?? true;
      if (!isEnabled) {
        logDebug('⏭️ Skipping $name sound alarm — adhan disabled');
        continue;
      }

      // Get selected sound for this prayer
      final soundName = prefs.getString('adhan_sound_$name') ?? 'adhan1';
      await prefs.setString('adhan_sound_$name', soundName);

      // Vibrate-only prayers still schedule an alarm — `PrayerAlarmReceiver`
      // is what decides to buzz rather than play, so the alarm has to exist
      // to reach that decision. It only changes the *fallback* below.
      // (Key mirrored in PrayerAlarmReceiver.kt and PrayerTimeScreen.dart's
      // `_AdhanAlertMode` — see CLAUDE.md on this cross-language contract.)
      final vibrateOnly = prefs.getBool('adhan_vibrate_$name') ?? false;

      // Schedule 4-minute reminder notification before each prayer
      final reminderTime = scheduledTime.subtract(const Duration(minutes: 4));
      if (reminderTime.isAfter(now)) {
        await _scheduleReminderNotification(id, name, timeStr, reminderTime);
      }

      // Schedule NATIVE alarm via AlarmManager → PrayerAlarmReceiver →
      // AdhanAlarmService, which plays audio on the ALARM stream.
      try {
        await _channel.invokeMethod('scheduleNativePrayerAlarm', {
          'prayerId': id,
          'triggerAtMillis': scheduledTime.millisecondsSinceEpoch,
        });
      } catch (e) {
        logWarning('Native alarm failed for $name — falling back');
        // Fallback: a Flutter notification. Silent for a vibrate-only prayer
        // — the whole point of that mode is that the recording doesn't play,
        // and a fallback that ignores it would be the one path where a muted
        // prayer suddenly announces itself out loud.
        await _scheduleLocalNotification(
          id,
          name,
          timeStr,
          scheduledTime,
          soundName,
          withSound: !vibrateOnly,
        );
      }
    }

    // Ask the native side to (re)derive alarms from the prefs we just wrote.
    // This also schedules the silent per-prayer widget-refresh alarms.
    try {
      await _channel.invokeMethod('rescheduleFromPrefs');
    } catch (e) {
      logWarning('Failed to reschedule widget refresh alarms', e);
    }

    // Start the persistent countdown notification (a no-op on the native side
    // when the user has switched it off).
    try {
      await _channel.invokeMethod('startCountdownService');
    } catch (e) {
      logWarning('Failed to start countdown service', e);
    }
  }

  /// Converts a wall-clock [DateTime] to the absolute instant the notification
  /// plugin needs.
  ///
  /// `tz.local` is resolved from the device at startup by `LocalTimezone`;
  /// before that fix it was pinned to Africa/Algiers, which silently shifted
  /// every reminder by the difference between the user's offset and UTC+1.
  static tz.TZDateTime _toTz(DateTime local) =>
      tz.TZDateTime.from(local, tz.local);

  /// Schedule a single local notification.
  static Future<void> _scheduleLocalNotification(
    int id,
    String name,
    String timeStr,
    DateTime scheduledTime,
    String soundName, {
    bool withSound = false, // true = fallback when native alarm fails
  }) async {
    await _notificationsPlugin.zonedSchedule(
      id + 100, // Different ID to avoid conflict
      'حان وقت صلاة $name',
      'الوقت: $timeStr',
      _toTz(scheduledTime),
      NotificationDetails(
        android: AndroidNotificationDetails(
          withSound ? 'adhan_sound_channel' : 'prayer_visual_channel',
          withSound ? 'الأذان' : 'تنبيهات الصلاة',
          channelDescription:
              withSound
                  ? 'صوت الأذان عند دخول وقت الصلاة'
                  : 'تنبيه مرئي عند دخول وقت الصلاة',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          playSound: withSound,
          sound:
              withSound ? RawResourceAndroidNotificationSound(soundName) : null,
          actions: const [
            AndroidNotificationAction(
              'stop_audio_id',
              'إلغاء',
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Schedule a 4-minute reminder notification before a prayer.
  static Future<void> _scheduleReminderNotification(
    int id,
    String name,
    String timeStr,
    DateTime reminderTime,
  ) async {
    await _notificationsPlugin.zonedSchedule(
      id + 200, // Unique ID for reminders (201-205)
      'باقي ٤ دقائق على صلاة $name',
      'وقت الصلاة: $timeStr',
      _toTz(reminderTime),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'prayer_reminder_channel',
          'تذكير الصلاة',
          channelDescription: 'تذكير قبل ٤ دقائق من وقت الصلاة',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          playSound: false,
          enableVibration: true,
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Request exact alarm permission (required for Android 12+).
  static Future<bool> requestExactAlarmPermission() async {
    try {
      final result = await _channel.invokeMethod('requestExactAlarmPermission');
      return result == true;
    } catch (e) {
      logWarning('Error requesting exact alarm permission', e);
      return false;
    }
  }

  /// Check if exact alarm permission is granted.
  static Future<bool> checkExactAlarmPermission() async {
    try {
      final result = await _channel.invokeMethod('checkExactAlarmPermission');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Cancel all scheduled alarms (both Flutter notifications and native).
  static Future<void> cancelAll() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      logWarning('Error cancelling notifications', e);
    }
    try {
      await _channel.invokeMethod('cancelAllNativeAlarms');
    } catch (e) {
      logWarning('Error cancelling native alarms', e);
    }
  }
}
