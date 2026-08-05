import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myadhan/controller/LocationController.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/services/connectivity_service.dart';
import 'package:myadhan/services/prayer_times_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `checkForLocationChange()` is the whole of the app's "the user travelled"
/// detection, and it runs on every resume — so both of its failure modes are
/// expensive. Refetching when nothing moved burns the user's data on every
/// app switch; *not* refetching after a flight leaves the wrong city's prayer
/// times in place indefinitely.
///
/// These tests pin the decision, not the plumbing.
void main() {
  const algiersLat = 36.75;
  const algiersLng = 3.06;

  Position positionAt(double lat, double lng) => Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  /// Seeds a month cache anchored on Algiers that covers today.
  Future<void> seedCacheAtAlgiers() async {
    final today = DateTime.now();
    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    SharedPreferences.setMockInitialValues({
      'prayer_month_cache': json.encode({
        'v': 1,
        'lat': algiersLat,
        'lng': algiersLng,
        'method': 19,
        'school': 0,
        'fetchedAt': today.toIso8601String(),
        'days': {
          for (final d in [today, today.add(const Duration(days: 1))])
            key(d): {
              'fajr': '04:11',
              'dhuhr': '12:55',
              'asr': '16:46',
              'maghrib': '20:00',
              'isha': '21:34',
              'hijri': '16 صَفَر 1448',
            },
        },
      }),
    });
  }

  /// Builds a container whose location controller reports [lastKnown], and
  /// whose HTTP client records how many requests were made.
  ({ProviderContainer container, List<Uri> requests}) harness(
    Position? lastKnown,
  ) {
    final requests = <Uri>[];

    final container = ProviderContainer(
      overrides: [
        locationControllerProvider
            .overrideWithValue(_FakeLocationController(lastKnown)),
        connectivityServiceProvider
            .overrideWithValue(_FakeConnectivityService()),
        prayerTimesApiServiceProvider.overrideWithValue(
          PrayerTimesApiService(
            client: MockClient((request) async {
              requests.add(request.url);
              // The decision to fetch is what's under test; whether the fetch
              // then succeeds is not.
              throw http.ClientException('Failed host lookup');
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, requests: requests);
  }

  setUp(seedCacheAtAlgiers);

  test('a move within the radius does not spend a request', () async {
    // A few km across the same city.
    final h = harness(positionAt(36.76, 3.07));

    await h.container
        .read(prayerTimesProvider.notifier)
        .checkForLocationChange();

    expect(h.requests, isEmpty);
  });

  test('a move beyond the radius triggers a refetch', () async {
    // Algiers → Paris.
    final h = harness(positionAt(48.85, 2.35));

    await h.container
        .read(prayerTimesProvider.notifier)
        .checkForLocationChange();

    expect(h.requests, isNotEmpty);
    expect(
      h.requests.first.path,
      contains('/calendar/'),
      reason: 'a location change should refresh the whole month, not one day',
    );
  });

  test('no cached fix means "unknown", not "unmoved" — and does nothing',
      () async {
    // Permission denied or a device that has never had a fix.
    final h = harness(null);

    await h.container
        .read(prayerTimesProvider.notifier)
        .checkForLocationChange();

    expect(h.requests, isEmpty);
  });

  test('an empty cache is not treated as a location change', () async {
    SharedPreferences.setMockInitialValues({});
    final h = harness(positionAt(48.85, 2.35));

    await h.container
        .read(prayerTimesProvider.notifier)
        .checkForLocationChange();

    // With nothing cached there's no anchor to compare against; the ordinary
    // startup fetch covers this, so resume must not pile a second one on.
    expect(h.requests, isEmpty);
  });

  test('a hand-picked city survives the user physically moving', () async {
    final h = harness(positionAt(48.85, 2.35));
    final notifier = h.container.read(prayerTimesProvider.notifier);

    // The user chose Mecca explicitly; this records the manual coordinates.
    await notifier.fetchPrayerTimes(lat: 21.42, lng: 39.82);
    h.requests.clear();

    await notifier.checkForLocationChange();

    expect(
      h.requests,
      isEmpty,
      reason: 'picking a city is a statement of intent, not a guess at where '
          'the phone is — walking around must not silently override it',
    );
  });
}

class _FakeLocationController implements LocationController {
  final Position? _lastKnown;

  _FakeLocationController(this._lastKnown);

  @override
  Future<Position?> lastKnownPosition() async => _lastKnown;

  @override
  Future<Position> determinePosition() async =>
      _lastKnown ?? (throw 'Location service are disabled.');

  @override
  Future<Map<String, String>> getLocationDetails() async => {};
}

class _FakeConnectivityService implements ConnectivityService {
  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<void> onReconnect() => const Stream.empty();
}
