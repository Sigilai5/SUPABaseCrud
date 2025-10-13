// lib/widgets/common/location_display_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/location_service.dart';

/// Widget to display transaction location
class LocationDisplayWidget extends StatelessWidget {
  final double latitude;
  final double longitude;
  final bool showCopyButton;

  const LocationDisplayWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.showCopyButton = true,
  });

  void _copyToClipboard(BuildContext context) {
    final locationString = LocationService.formatLocation(latitude, longitude);
    Clipboard.setData(ClipboardData(text: locationString));
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check, color: Colors.white),
            SizedBox(width: 8),
            Text('Location copied to clipboard'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _openInMaps(BuildContext context) {
    // Open in Google Maps or Apple Maps
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening maps: $mapsUrl'),
        action: SnackBarAction(
          label: 'Copy URL',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: mapsUrl));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: () => _openInMaps(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.location_on,
                  color: Colors.blue.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      LocationService.formatLocation(latitude, longitude),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (showCopyButton) ...[
                IconButton(
                  icon: Icon(
                    Icons.copy,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                  onPressed: () => _copyToClipboard(context),
                  tooltip: 'Copy location',
                ),
                Icon(
                  Icons.map,
                  size: 18,
                  color: Colors.grey[600],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact location chip for list items
class LocationChip extends StatelessWidget {
  final double latitude;
  final double longitude;

  const LocationChip({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on,
            size: 12,
            color: Colors.blue.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            'Location saved',
            style: TextStyle(
              fontSize: 10,
              color: Colors.blue.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}