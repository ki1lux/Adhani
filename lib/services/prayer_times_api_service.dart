import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:myadhan/services/app_exception.dart';
import 'package:myadhan/services/prayer_times_cache.dart';

/// Response model for the Aladhan API timings
class AladhanApiResponse {
  final String fajr;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;
  final String dateOnHijri;

  const AladhanApiResponse({
    required this.fajr,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    required this.dateOnHijri,
  });

  static String _addMinutes(String timeStr, int minutes) {
    try {
      final cleanTime = timeStr.split(' ').first;
      final parts = cleanTime.split(':');
      var hr = int.parse(parts[0]);
      var min = int.parse(parts[1]);
      
      min += minutes;
      if (min >= 60) {
        hr += (min ~/ 60);
        min = min % 60;
      }
      if (hr >= 24) hr = hr % 24;
      
      return '${hr.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
    } catch (e) {
      return timeStr.split(' ').first;
    }
  }

  factory AladhanApiResponse.fromJson(Map<String, dynamic> json) {
    final timings = json['data']['timings'] as Map<String, dynamic>;
    final date = json['data']['date']['hijri'];
    final hijriStr = '${date['day']} ${date['month']['ar']} ${date['year']}';
    return AladhanApiResponse(
      fajr: _addMinutes(timings['Fajr'] as String, 1),
      dhuhr: _addMinutes(timings['Dhuhr'] as String, 1),
      asr: _addMinutes(timings['Asr'] as String, 2),
      maghrib: _addMinutes(timings['Maghrib'] as String, 4),
      isha: _addMinutes(timings['Isha'] as String, 3),
      dateOnHijri: hijriStr,
    );
  }
}

/// Service for fetching prayer times from the Aladhan API
/// API Docs: https://aladhan.com/prayer-times-api
class PrayerTimesApiService {
  static const _baseUrl = 'https://api.aladhan.com/v1/timings';
  static const _calendarUrl = 'https://api.aladhan.com/v1/calendar';

  /// Short on purpose. Stacked on the 10s GPS timeout in the provider, the old
  /// 20s meant a device with no route sat on a shimmer for half a minute before
  /// admitting anything was wrong. Offline should be obvious in seconds.
  static const _timeout = Duration(seconds: 8);

  /// A month of days is a bigger response than one day's timings, so it gets
  /// proportionally more room before we give up on it.
  static const _monthTimeout = Duration(seconds: 20);

  final http.Client _client;

  PrayerTimesApiService({http.Client? client})
    : _client = client ?? http.Client();

  /// Fetches prayer times for the given coordinates
  /// [method] 19 = Algeria
  /// [school] 0 = Shafi
  Future<AladhanApiResponse> fetchPrayerTimes({
    required double latitude,
    required double longitude,
    int method = 19,
    int school = 0,
    DateTime? targetDate,
  }) async {
    final now = targetDate ?? DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    final uri = Uri.parse(
      '$_baseUrl/$dateStr?latitude=$latitude&longitude=$longitude&method=$method&school=$school',
    );

    final jsonData = await _getJson(uri, _timeout);

    try {
      return AladhanApiResponse.fromJson(jsonData);
    } catch (e) {
      throw AppException(AppErrorKind.server, 'Malformed timings payload: $e');
    }
  }

  /// Fetches a whole month of prayer times in one request.
  ///
  /// This is what makes the app work offline: one call covers ~30 days, so
  /// [PrayerTimesCache] can answer for any of them without a connection. It
  /// deliberately shares [AladhanApiResponse._addMinutes] with the single-day
  /// path above, so a day served from the month cache is identical to the same
  /// day fetched live — otherwise times would shift the moment the network
  /// dropped.
  ///
  /// Returns days keyed `yyyy-MM-dd`, ready for [PrayerTimesCache.merge].
  Future<Map<String, CachedDay>> fetchMonth({
    required double latitude,
    required double longitude,
    required int year,
    required int month,
    int method = 19,
    int school = 0,
  }) async {
    final uri = Uri.parse(
      '$_calendarUrl/$year/$month'
      '?latitude=$latitude&longitude=$longitude&method=$method&school=$school',
    );

    final jsonData = await _getJson(uri, _monthTimeout);

    try {
      final data = jsonData['data'] as List<dynamic>;
      final days = <String, CachedDay>{};

      for (final entry in data) {
        final day = entry as Map<String, dynamic>;
        final timings = day['timings'] as Map<String, dynamic>;
        final date = day['date'] as Map<String, dynamic>;

        // The calendar endpoint dates each entry as "DD-MM-YYYY"; the cache is
        // keyed the sortable way round.
        final gregorian = date['gregorian'] as Map<String, dynamic>;
        final parts = (gregorian['date'] as String).split('-');
        if (parts.length != 3) continue;
        final key = '${parts[2]}-${parts[1]}-${parts[0]}';

        final hijri = date['hijri'] as Map<String, dynamic>;
        final hijriStr =
            '${hijri['day']} ${(hijri['month'] as Map)['ar']} ${hijri['year']}';

        days[key] = CachedDay(
          fajr: AladhanApiResponse._addMinutes(timings['Fajr'] as String, 1),
          dhuhr: AladhanApiResponse._addMinutes(timings['Dhuhr'] as String, 1),
          asr: AladhanApiResponse._addMinutes(timings['Asr'] as String, 2),
          maghrib:
              AladhanApiResponse._addMinutes(timings['Maghrib'] as String, 4),
          isha: AladhanApiResponse._addMinutes(timings['Isha'] as String, 3),
          hijri: hijriStr,
        );
      }

      if (days.isEmpty) {
        throw AppException(
          AppErrorKind.server,
          'Calendar response contained no usable days',
        );
      }

      return days;
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException(AppErrorKind.server, 'Malformed calendar payload: $e');
    }
  }

  /// Performs the request and returns a decoded, status-checked body.
  ///
  /// Transport failures (no DNS, no route, timeout) are a different problem
  /// from the API answering with an error, and the user needs different advice
  /// for each — so they're classified separately here rather than upstream.
  Future<Map<String, dynamic>> _getJson(Uri uri, Duration timeout) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } catch (e) {
      throw AppException.from(e);
    }

    if (response.statusCode != 200) {
      throw AppException(
        AppErrorKind.server,
        'API request failed: ${response.statusCode}',
      );
    }

    // A captive-portal Wi-Fi answers 200 with a login page. Decoding that
    // throws FormatException, which used to escape uncategorised and reach the
    // user as "حدث خطأ غير متوقّع" — the one message that tells them nothing.
    final Map<String, dynamic> jsonData;
    try {
      jsonData = json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw AppException(
        AppErrorKind.server,
        'Response was not the JSON we expected: $e',
      );
    }

    if (jsonData['code'] != 200) {
      throw AppException(
        AppErrorKind.server,
        'API error: ${jsonData['status']}',
      );
    }

    return jsonData;
  }
}

