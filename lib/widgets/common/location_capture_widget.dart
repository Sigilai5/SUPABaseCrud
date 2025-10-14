// lib/widgets/common/location_capture_widget.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';

class LocationCaptureWidget extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final Function(double?, double?) onLocationChanged;

  const LocationCaptureWidget({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    required this.onLocationChanged,
  });

  @override
  State<LocationCaptureWidget> createState() => _LocationCaptureWidgetState();
}

class _LocationCaptureWidgetState extends State<LocationCaptureWidget> {
  double? _latitude;
  double? _longitude;
  bool _isLoading = false;
  bool _autoCapture = true; // Default to auto-capture

  @override
  void initState() {
    super.initState();
    _latitude = widget.initialLatitude;
    _longitude = widget.initialLongitude;
    
    // Auto-capture location if not already set
    if (_latitude == null && _longitude == null && _autoCapture) {
      _captureLocation();
    }
  }

  Future<void> _captureLocation() async {
    setState(() => _isLoading = true);

    try {
      // Check if permission is permanently denied
      final isDeniedForever = await LocationService.isPermissionDeniedForever();
      if (isDeniedForever && mounted) {
        await _showOpenSettingsDialog();
        setState(() => _isLoading = false);
        return;
      }

      // Check if we have permission
      final hasPermission = await LocationService.hasLocationPermission();
      if (!hasPermission && mounted) {
        // Show permission dialog
        final granted = await _showPermissionDialog();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      // Check if location service is enabled
      final serviceEnabled = await LocationService.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enable location services'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                LocationService.openLocationSettings();
              },
            ),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Get current position
      final position = await LocationService.getCurrentPosition();
      
      if (position != null) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _isLoading = false;
        });
        
        widget.onLocationChanged(_latitude, _longitude);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Location captured'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get location'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showPermissionDialog() async {
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
      return await LocationService.requestLocationPermission();
    }
    
    return false;
  }

  Future<void> _showOpenSettingsDialog() async {
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
      await LocationService.openLocationSettings();
    }
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
    });
    widget.onLocationChanged(null, null);
  }

  bool get _hasLocation => _latitude != null && _longitude != null;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 20,
                  color: _hasLocation ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Location',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const Spacer(),
                if (_hasLocation && !_isLoading)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _clearLocation,
                    tooltip: 'Remove location',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            if (_isLoading)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Getting location...',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              )
            else if (_hasLocation)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, 
                      size: 16, 
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Location captured',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            LocationService.formatLocation(_latitude!, _longitude!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _captureLocation,
                icon: const Icon(Icons.my_location, size: 16),
                label: const Text('Capture Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: BorderSide(color: Colors.blue.shade300),
                ),
              ),
            
            const SizedBox(height: 8),
            Text(
              _hasLocation 
                ? 'This transaction is tagged with your location'
                : 'Add location to track where you spend',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}