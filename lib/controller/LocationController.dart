import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationController {
  Future<Position> determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location service are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are dendied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
  }

  /// The last position the OS already knows about, without asking for a fix.
  ///
  /// This is effectively free — no GPS hardware, no wait — because it returns
  /// whatever the platform cached from any app's recent request. It's what
  /// makes the "did the user travel?" check on every app resume affordable;
  /// [determinePosition] would mean a real GPS acquisition each time the user
  /// switched back to the app.
  ///
  /// Returns null when there's no cached fix or no permission, which callers
  /// must treat as "don't know" rather than "hasn't moved".
  Future<Position?> lastKnownPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, String>> getLocationDetails() async {
    try {
      Position position = await determinePosition();
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      Placemark placemark = placemarks[0];
      return {
        "country": placemark.country ?? "not detected",
        "city": placemark.locality ?? "not detected",
      };
    } catch (e) {
      throw Exception("Location error: $e");
    }
  }
}
