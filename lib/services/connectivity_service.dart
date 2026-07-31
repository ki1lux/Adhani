import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device currently has *a* network interface up.
///
/// This is deliberately a coarse signal. `connectivity_plus` reports what the
/// OS is attached to, not whether packets actually reach the internet — a
/// captive-portal Wi-Fi reads as connected. So this is used only to decide
/// *when it's worth trying again*, never to decide whether a fetch will
/// succeed; the fetch itself remains the source of truth for that.
class ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<bool> isOnline() async {
    try {
      return _isOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      // If we can't tell, assume we're online: a wasted request is a much
      // cheaper mistake than refusing to ever retry.
      return true;
    }
  }

  /// Emits only on the offline → online edge.
  ///
  /// The platform fires several events for one reconnection (interface up,
  /// then address assigned, …), and every one of them used to be a reason to
  /// refetch. Tracking the previous value means one reconnection is one retry.
  Stream<void> onReconnect() {
    var wasOnline = true;
    return _connectivity.onConnectivityChanged
        .map(_isOnline)
        .where((online) {
          final isEdge = online && !wasOnline;
          wasOnline = online;
          return isEdge;
        })
        .map((_) {});
  }
}
