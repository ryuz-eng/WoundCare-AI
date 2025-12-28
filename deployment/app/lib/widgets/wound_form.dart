import 'package:flutter/material.dart';
import '../utils/constants.dart';

class WoundForm extends StatelessWidget {
  final TextEditingController locationController;
  final TextEditingController capturedByController;
  final TextEditingController notesController;
  final String? selectedLocation;
  final ValueChanged<String?> onLocationChanged;

  const WoundForm({
    super.key,
    required this.locationController,
    required this.capturedByController,
    required this.notesController,
    this.selectedLocation,
    required this.onLocationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wound Location
        DropdownButtonFormField<String>(
          value: selectedLocation,
          decoration: const InputDecoration(
            labelText: 'Wound Location *',
            prefixIcon: Icon(Icons.location_on),
          ),
          items: AppConstants.woundLocations.map((location) {
            return DropdownMenuItem(
              value: location,
              child: Text(location),
            );
          }).toList(),
          onChanged: onLocationChanged,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select wound location';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Captured By
        TextFormField(
          controller: capturedByController,
          decoration: const InputDecoration(
            labelText: 'Captured By (Your Name) *',
            prefixIcon: Icon(Icons.badge),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your name';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Notes
        TextFormField(
          controller: notesController,
          decoration: const InputDecoration(
            labelText: 'Notes (Optional)',
            prefixIcon: Icon(Icons.notes),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
      ],
    );
  }
}
