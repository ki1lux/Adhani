import 'dart:async';
import 'dart:io';

/// What actually went wrong, in terms the UI can turn into a sentence.
///
/// The layers below used to throw bare `Exception('API request failed: 500')`,
/// which `PrayerTimeScreen` rendered straight to the user via `'$error'` —
/// so people saw `Exception: API request failed: 500`. Classifying at the
/// throw site means the UI never has to pattern-match English exception text
/// to guess what to say.
enum AppErrorKind {
  /// No usable connection — DNS failure, no route, request timed out.
  network,

  /// We reached the API and it refused or malfunctioned.
  server,

  /// No coordinates available: GPS off, no fix, and nothing cached.
  location,

  /// The OS denied us location access.
  locationPermission,

  /// Genuinely unclassified. The UI stays vague here rather than inventing
  /// a cause it can't stand behind.
  unknown,
}

/// An error that already knows what category it belongs to.
///
/// [debugMessage] is for logs and bug reports only — never render it. The
/// user-facing wording lives in the UI layer so it stays translatable and
/// consistent, rather than being baked into whichever layer threw.
class AppException implements Exception {
  final AppErrorKind kind;
  final String debugMessage;

  const AppException(this.kind, this.debugMessage);

  /// Classifies anything that reaches us already thrown — `http`'s socket
  /// errors, `Geolocator`'s failures, or an [AppException] that a lower
  /// layer already labelled (returned unchanged).
  factory AppException.from(Object error) {
    if (error is AppException) return error;

    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return AppException(AppErrorKind.network, error.toString());
    }

    // `http` wraps most transport failures in ClientException, and
    // geolocator/geocoding surface their own types. Matching on the text is
    // a deliberate last resort for packages that don't expose typed errors.
    final text = error.toString().toLowerCase();

    // Permission first: it's the more specific claim, and it's the one whose
    // fix (open system settings) is useless advice if we guess wrong. The
    // network patterns below are checked second precisely because a permission
    // failure can mention a connection in passing.
    if (text.contains('permission') && text.contains('denied')) {
      return AppException(AppErrorKind.locationPermission, error.toString());
    }
    // Deliberately not a bare 'connection' match — geolocator and geocoding
    // both emit messages containing that word for failures that have nothing
    // to do with the network, and telling someone their internet is down when
    // it isn't sends them to fix the wrong thing.
    if (text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('connection refused') ||
        text.contains('connection failed') ||
        text.contains('connection closed') ||
        text.contains('connection timed out') ||
        text.contains('connection reset') ||
        text.contains('no address associated') ||
        text.contains('network is unreachable') ||
        text.contains('unable to resolve host')) {
      return AppException(AppErrorKind.network, error.toString());
    }
    if (text.contains('location')) {
      return AppException(AppErrorKind.location, error.toString());
    }

    return AppException(AppErrorKind.unknown, error.toString());
  }

  @override
  String toString() => 'AppException($kind): $debugMessage';
}
