import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// The Qibla bearing shown when the compass can't run.
///
/// This is the one part of QiblaScreen that needs no magnetometer — pure
/// spherical trigonometry from the user's cached coordinates — which is
/// exactly why it's what the no-compass state falls back to. It's worth
/// pinning against known values: a sign slip or a swapped argument in
/// `atan2` still produces a plausible-looking number, just pointing somewhere
/// else entirely, and there is no sensor reading to contradict it.
///
/// Mirrors the computation in `_loadDistanceToMecca`.
void main() {
  const kaabaLat = 21.4225;
  const kaabaLon = 39.8262;

  double degToRad(double d) => d * pi / 180.0;

  double bearingTo(double lat, double lon) {
    final phi1 = degToRad(lat);
    final phi2 = degToRad(kaabaLat);
    final deltaLambda = degToRad(kaabaLon - lon);
    final y = sin(deltaLambda) * cos(phi2);
    final x =
        cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda);
    return (atan2(y, x) * 180.0 / pi + 360.0) % 360.0;
  }

  test('Batna, Algeria points east-south-east', () {
    expect(bearingTo(35.556, 6.174), closeTo(106.5, 2));
  });

  test('Algiers points east-south-east', () {
    expect(bearingTo(36.7538, 3.0588), closeTo(105.4, 2));
  });

  test('Cairo points almost due south-east', () {
    expect(bearingTo(30.0444, 31.2357), closeTo(136, 3));
  });

  test('Istanbul points south-south-east', () {
    expect(bearingTo(41.0082, 28.9784), closeTo(152, 3));
  });

  test('London points south-east', () {
    expect(bearingTo(51.5074, -0.1278), closeTo(119, 3));
  });

  test('Jakarta points north-west — not toward the equator-crossing guess', () {
    // Guards the sign of the great-circle term: a naive "head toward the
    // Kaaba's latitude" answer would send Jakarta south, not north-west.
    expect(bearingTo(-6.2088, 106.8456), closeTo(295, 3));
  });

  test('always normalised into 0..360', () {
    for (final lat in [-80.0, -30.0, 0.0, 30.0, 80.0]) {
      for (final lon in [-179.0, -90.0, 0.0, 90.0, 179.0]) {
        final b = bearingTo(lat, lon);
        expect(b, greaterThanOrEqualTo(0));
        expect(b, lessThan(360));
      }
    }
  });
}
