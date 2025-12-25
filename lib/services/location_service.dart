import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// LocationService handles all GPS and location-related operations
///
/// Features:
/// - Get current GPS position
/// - Check and request permissions
/// - Calculate distances between coordinates
/// - Handle location service errors
/// - Get last known position
class LocationService {
  /// Check if location services are enabled on the device
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check and request location permissions
  /// Returns true if permission is granted, false otherwise
  Future<bool> hasPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get current GPS position with comprehensive error handling
  ///
  /// Parameters:
  /// - accuracy: Desired accuracy level (default: high)
  /// - timeLimit: Maximum time to wait for position (default: 15 seconds)
  ///
  /// Throws Exception if:
  /// - Location services are disabled
  /// - Permissions are denied
  /// - Unable to get position within timeLimit
  Future<Position> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) async {
    // Check if location services are enabled
    bool serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS in your device settings.');
    }

    // Check permissions
    bool hasLocationPermission = await hasPermission();
    if (!hasLocationPermission) {
      throw Exception('Location permissions denied. Please grant location access in app settings.');
    }

    // Get position with timeout
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeLimit ?? const Duration(seconds: 15),
      );
      return position;
    } on TimeoutException {
      throw Exception('Location request timed out. Please ensure you have a clear view of the sky.');
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  /// Get current position with custom settings
  /// This is a wrapper for more control over location settings
  Future<Position> getCurrentPositionWithSettings({
    LocationAccuracy desiredAccuracy = LocationAccuracy.high,
    bool forceAndroidLocationManager = false,
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    bool serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    bool hasLocationPermission = await hasPermission();
    if (!hasLocationPermission) {
      throw Exception('Location permissions denied.');
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: desiredAccuracy,
        forceAndroidLocationManager: forceAndroidLocationManager,
        timeLimit: timeLimit,
      );
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  /// Calculate distance between two GPS coordinates in meters
  ///
  /// Parameters:
  /// - startLatitude: Starting point latitude
  /// - startLongitude: Starting point longitude
  /// - endLatitude: Ending point latitude
  /// - endLongitude: Ending point longitude
  ///
  /// Returns: Distance in meters
  double calculateDistance(
      double startLatitude,
      double startLongitude,
      double endLatitude,
      double endLongitude,
      ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Calculate distance in kilometers
  double calculateDistanceInKm(
      double startLatitude,
      double startLongitude,
      double endLatitude,
      double endLongitude,
      ) {
    double distanceInMeters = calculateDistance(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
    return distanceInMeters / 1000;
  }

  /// Get last known position from device cache
  /// Returns null if no cached position is available
  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      print('Could not get last known position: $e');
      return null;
    }
  }

  /// Open device location settings
  /// Useful when user needs to enable GPS manually
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open app-specific settings
  /// Useful when permissions are permanently denied
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Check permission status without requesting
  /// Returns current permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request permission explicitly
  /// Returns the permission status after request
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Get location accuracy description
  String getAccuracyDescription(double accuracy) {
    if (accuracy <= 5) {
      return 'Excellent (±${accuracy.toStringAsFixed(1)}m)';
    } else if (accuracy <= 10) {
      return 'Good (±${accuracy.toStringAsFixed(1)}m)';
    } else if (accuracy <= 20) {
      return 'Fair (±${accuracy.toStringAsFixed(1)}m)';
    } else {
      return 'Poor (±${accuracy.toStringAsFixed(1)}m)';
    }
  }

  /// Format position as human-readable string
  String formatPosition(Position position) {
    return 'Lat: ${position.latitude.toStringAsFixed(6)}, '
        'Lon: ${position.longitude.toStringAsFixed(6)}, '
        'Accuracy: ±${position.accuracy.toStringAsFixed(1)}m';
  }

  /// Check if two positions are within a certain distance (in meters)
  bool isWithinDistance(
      Position position1,
      Position position2,
      double maxDistanceInMeters,
      ) {
    double distance = calculateDistance(
      position1.latitude,
      position1.longitude,
      position2.latitude,
      position2.longitude,
    );
    return distance <= maxDistanceInMeters;
  }

  /// Validate if GPS coordinates are valid
  bool isValidCoordinate(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    return (latitude >= -90 && latitude <= 90) &&
        (longitude >= -180 && longitude <= 180);
  }

  /// Stream location updates
  /// Useful for tracking movement in real-time
  Stream<Position> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 0, // minimum distance (meters) before update
    Duration? intervalDuration,
  }) {
    LocationSettings locationSettings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );

    if (intervalDuration != null) {
      locationSettings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: intervalDuration,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  /// Get bearing (direction) between two points in degrees
  /// Returns value between 0 and 360
  double calculateBearing(
      double startLatitude,
      double startLongitude,
      double endLatitude,
      double endLongitude,
      ) {
    return Geolocator.bearingBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Get compass direction from bearing
  String getCompassDirection(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) return 'N';
    if (bearing >= 22.5 && bearing < 67.5) return 'NE';
    if (bearing >= 67.5 && bearing < 112.5) return 'E';
    if (bearing >= 112.5 && bearing < 157.5) return 'SE';
    if (bearing >= 157.5 && bearing < 202.5) return 'S';
    if (bearing >= 202.5 && bearing < 247.5) return 'SW';
    if (bearing >= 247.5 && bearing < 292.5) return 'W';
    if (bearing >= 292.5 && bearing < 337.5) return 'NW';
    return 'N';
  }

  /// Create a Position object from latitude and longitude
  /// Useful for testing or manual position creation
  Position createPosition({
    required double latitude,
    required double longitude,
    double accuracy = 0.0,
    double altitude = 0.0,
    double heading = 0.0,
    double speed = 0.0,
    double speedAccuracy = 0.0,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: accuracy,
      altitude: altitude,
      heading: heading,
      speed: speed,
      speedAccuracy: speedAccuracy,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
  }
}

/// Extension to add helpful methods to Position class
extension PositionExtensions on Position {
  /// Convert position to a simple map
  Map<String, dynamic> toSimpleMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'heading': heading,
      'speed': speed,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Get a human-readable description
  String get description {
    return 'Position(${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}) '
        '±${accuracy.toStringAsFixed(1)}m';
  }

  /// Check if position has good accuracy (< 20 meters)
  bool get hasGoodAccuracy => accuracy < 20;

  /// Check if position is recent (within last 5 minutes)
  bool get isRecent {
    return DateTime.now().difference(timestamp).inMinutes < 5;
  }
}