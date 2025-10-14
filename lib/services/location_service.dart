// lib/services/location_service.dart
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

/// Service to handle location-related operations
class LocationService {
  static const String _tag = 'LocationService';

  /// Check if location services are enabled
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check if location permission is granted
  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Request location permission from the user
  static Future<bool> requestLocationPermission() async {
    // Check if location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('$_tag: Location services are disabled.');
      return false;
    }

    // Check current permission status
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('$_tag: Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('$_tag: Location permissions are permanently denied');
      return false;
    }

    print('$_tag: Location permission granted');
    return true;
  }

  /// Show a dialog to request location permission with explanation
  static Future<bool> showLocationPermissionDialog(BuildContext context) async {
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue),
            SizedBox(width: 8),
            Text('Location Permission'),
          ],
        ),
        content: const Text(
          'This app needs location permission to tag your transactions with location data.\n\n'
          'This helps you track where you spend money and analyze spending patterns by location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (shouldRequest == true) {
      return await requestLocationPermission();
    }
    
    return false;
  }

  /// Show dialog to open app settings when permission is permanently denied
  static Future<void> showOpenSettingsDialog(BuildContext context) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.orange),
            SizedBox(width: 8),
            Text('Permission Required'),
          ],
        ),
        content: const Text(
          'Location permission was permanently denied. '
          'Please enable it in your device settings to use this feature.\n\n'
          'Settings > Apps > Expense Tracker > Permissions > Location',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpen == true) {
      await openLocationSettings();
    }
  }

  /// Get the current position of the device
  /// Returns null if location cannot be obtained
  static Future<Position?> getCurrentPosition() async {
    try {
      // Check if we have permission
      final hasPermission = await LocationService.hasLocationPermission();
      if (!hasPermission) {
        print('$_tag: No location permission');
        return null;
      }

      // Check if location service is enabled
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('$_tag: Location service is disabled');
        return null;
      }

      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      print('$_tag: Got location: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('$_tag: Error getting location: $e');
      return null;
    }
  }

  /// Get a formatted address string from coordinates
  /// Returns a simple coordinate string
  static String formatLocation(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  /// Calculate distance between two coordinates in meters
  static double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  /// Open location settings on the device
  static Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Get location permission status as a user-friendly string
  static Future<String> getPermissionStatusString() async {
    final permission = await Geolocator.checkPermission();
    
    switch (permission) {
      case LocationPermission.always:
        return 'Always allowed';
      case LocationPermission.whileInUse:
        return 'While using app';
      case LocationPermission.denied:
        return 'Denied';
      case LocationPermission.deniedForever:
        return 'Permanently denied';
      default:
        return 'Unknown';
    }
  }

  /// Check if location permission is permanently denied
  static Future<bool> isPermissionDeniedForever() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.deniedForever;
  }

  /// Get detailed location info for debugging
  static Future<Map<String, dynamic>> getLocationInfo() async {
    final serviceEnabled = await isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    final hasPermission = await LocationService.hasLocationPermission();
    final isDeniedForever = await isPermissionDeniedForever();
    
    Position? position;
    try {
      if (hasPermission && serviceEnabled) {
        position = await getCurrentPosition();
      }
    } catch (e) {
      print('$_tag: Error getting position: $e');
    }

    return {
      'service_enabled': serviceEnabled,
      'permission_status': permission.toString(),
      'has_permission': hasPermission,
      'denied_forever': isDeniedForever,
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'accuracy': position?.accuracy,
    };
  }
}