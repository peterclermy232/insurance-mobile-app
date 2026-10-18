import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks whether the device has a network connection and announces when it
/// comes back (used to trigger an automatic sync).
class ConnectivityService extends ChangeNotifier {
  ConnectivityService([Connectivity? connectivity]) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;
  final _restored = StreamController<void>.broadcast();

  bool get isOnline => _online;

  /// Fires each time the device goes from offline to online.
  Stream<void> get onRestored => _restored.stream;

  Future<void> start() async {
    try {
      _set(await _connectivity.checkConnectivity());
    } catch (_) {
      // Plugin unavailable (tests/desktop): assume online and let requests fail.
    }
    _sub = _connectivity.onConnectivityChanged.listen(_set, onError: (_) {});
  }

  void _set(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online == _online) return;
    _online = online;
    notifyListeners();
    if (online) _restored.add(null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _restored.close();
    super.dispose();
  }
}
