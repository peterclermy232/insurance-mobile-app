import 'package:geolocator/geolocator.dart';

class GeoFix {
  const GeoFix({required this.latitude, required this.longitude, this.accuracy, this.time});
  final double latitude;
  final double longitude;

  /// Metres (68% confidence radius).
  final double? accuracy;
  final DateTime? time;

  String get accuracyLabel => accuracy == null ? 'unknown accuracy' : '+/- ${accuracy!.round()} m';
  bool get isPoor => accuracy != null && accuracy! > 50;
}

class LocationFailure implements Exception {
  const LocationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// GPS capture. Works offline (satellite fix, no network needed).
class LocationService {
  const LocationService();

  /// Throws [LocationFailure] with an officer-friendly message.
  Future<GeoFix> current({Duration timeout = const Duration(seconds: 30)}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure('Location is turned off. Turn on GPS and try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure('Location permission is blocked. Allow it in the phone settings.');
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
      return GeoFix(latitude: p.latitude, longitude: p.longitude, accuracy: p.accuracy, time: p.timestamp);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return GeoFix(
            latitude: last.latitude, longitude: last.longitude, accuracy: last.accuracy, time: last.timestamp);
      }
      throw const LocationFailure('Could not get a GPS fix. Move to an open area and retry.');
    }
  }

  /// Best-effort position for photo tagging; never throws.
  Future<GeoFix?> quick() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 5) {
        return GeoFix(latitude: last.latitude, longitude: last.longitude, accuracy: last.accuracy);
      }
      return await current(timeout: const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }
}
