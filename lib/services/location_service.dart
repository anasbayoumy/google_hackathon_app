import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

/// A service that provides location functionality.
/// Uses real GPS coordinates from the device through platform channels
class LocationService {
  static bool _hasLocationPermission = false;
  static const MethodChannel _channel = MethodChannel('location_service');

  /// Check if location permission is granted
  static Future<bool> hasLocationPermission() async {
    if (kIsWeb) return false;

    try {
      final status = await Permission.location.status;
      final whenInUseStatus = await Permission.locationWhenInUse.status;
      _hasLocationPermission = status.isGranted || whenInUseStatus.isGranted;
      return _hasLocationPermission;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      return false;
    }
  }

  /// Request location permission
  static Future<bool> requestLocationPermission() async {
    if (kIsWeb) return false;

    try {
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.locationWhenInUse,
      ].request();

      final locationStatus = statuses[Permission.location];
      final whenInUseStatus = statuses[Permission.locationWhenInUse];

      _hasLocationPermission = (locationStatus?.isGranted ?? false) ||
          (whenInUseStatus?.isGranted ?? false);

      debugPrint(
          'Location permission status: location=$locationStatus, whenInUse=$whenInUseStatus');
      return _hasLocationPermission;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return false;
    }
  }

  /// Get the current location
  /// Uses real GPS coordinates from the device
  static Future<LocationData?> getCurrentLocation() async {
    if (kIsWeb) {
      debugPrint('Location services not supported on web');
      return null;
    }

    try {
      // Check if we have permission
      if (!_hasLocationPermission) {
        final hasPermission = await requestLocationPermission();
        if (!hasPermission) {
          debugPrint('Location permission denied');
          return null;
        }
      }

      debugPrint('Getting current location (real GPS)...');

      // Call native Android location service
      final dynamic result = await _channel.invokeMethod('getCurrentLocation');

      if (result is Map && result['success'] == true) {
        final realLocation = LocationData(
          latitude: (result['latitude'] as num).toDouble(),
          longitude: (result['longitude'] as num).toDouble(),
          accuracy: (result['accuracy'] as num?)?.toDouble() ?? 10.0,
          timestamp: DateTime.now(),
        );

        debugPrint(
            'Location obtained (real GPS): ${realLocation.latitude}, ${realLocation.longitude}');
        return realLocation;
      } else {
        debugPrint(
            'Failed to get location from native service: ${result is Map ? result['error'] : result}');
        return null;
      }
    } catch (e) {
      debugPrint('Failed to get location: $e');
      return null;
    }
  }

  /// Check if location services are enabled on the device
  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return false;

    try {
      final bool? result =
          await _channel.invokeMethod('isLocationServiceEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking location service status: $e');
      return false;
    }
  }
}

/// A data class to represent location information
class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'LocationData(lat: $latitude, lng: $longitude, accuracy: $accuracy, time: $timestamp)';
  }
}
