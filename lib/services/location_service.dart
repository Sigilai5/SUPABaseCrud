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

  /// Get the current position of the device
  /// Returns null if location cannot be obtained
  static Future<Position?> getCurrentPosition() async {
    try {
      // Check if we have permission
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        print('$_tag: No location permission, requesting...');
        final granted = await requestLocationPermission();
        if (!granted) {
          print('$_tag: Location permission not granted');
          return null;
        }
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
  /// Note: This requires a geocoding service (not included in geolocator)
  /// Returns a simple coordinate string for now
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
}