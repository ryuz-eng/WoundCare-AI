import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  final ImagePicker _picker = ImagePicker();

  // Pick image from camera
  Future<File?> pickFromCamera() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile == null) return null;
      return File(pickedFile.path);
    } catch (e) {
      print('Error picking image from camera: $e');
      return null;
    }
  }

  // Pick image from gallery
  Future<File?> pickFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile == null) return null;
      return File(pickedFile.path);
    } catch (e) {
      print('Error picking image from gallery: $e');
      return null;
    }
  }

  // Show picker dialog
  Future<File?> showPickerDialog(BuildContext context) async {
    return await showModalBottomSheet<File?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select Image Source',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPickerOption(
                  context,
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () async {
                    Navigator.pop(context);
                    final file = await pickFromCamera();
                    if (context.mounted && file != null) {
                      Navigator.pop(context, file);
                    }
                  },
                ),
                _buildPickerOption(
                  context,
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () async {
                    Navigator.pop(context);
                    final file = await pickFromGallery();
                    if (context.mounted && file != null) {
                      Navigator.pop(context, file);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Save image to app directory
  Future<String> saveImage(File imageFile, String patientId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(path.join(appDir.path, 'wound_images', patientId));
    
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'wound_$timestamp.jpg';
    final savedPath = path.join(imagesDir.path, fileName);

    await imageFile.copy(savedPath);
    return savedPath;
  }

  // Save segmentation mask
    Future<String> saveMask(
    Uint8List maskData,
    int width,
    int height,
    String patientId,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'mask_${patientId}_$timestamp.png';
    final filePath = '${directory.path}/wounds/$patientId/$fileName';

    // Create directory if it doesn't exist
    final dir = Directory('${directory.path}/wounds/$patientId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // maskData is already a PNG from the API, save directly
    final file = File(filePath);
    await file.writeAsBytes(maskData);

    return filePath;
  }

  // Load image bytes
  Future<Uint8List> loadImageBytes(String imagePath) async {
    final file = File(imagePath);
    return await file.readAsBytes();
  }

  // Delete image file
  Future<void> deleteImage(String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Get image dimensions
  Future<Size> getImageDimensions(String imagePath) async {
    final bytes = await loadImageBytes(imagePath);
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image');
    }
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  // Crop image to wound region based on mask
  Future<Uint8List?> cropToWound(Uint8List imageBytes, Uint8List maskData, int maskSize) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    // Find bounding box of wound region in mask
    int minX = maskSize, minY = maskSize, maxX = 0, maxY = 0;
    bool foundWound = false;

    for (int y = 0; y < maskSize; y++) {
      for (int x = 0; x < maskSize; x++) {
        if (maskData[y * maskSize + x] > 127) {
          foundWound = true;
          minX = minX < x ? minX : x;
          minY = minY < y ? minY : y;
          maxX = maxX > x ? maxX : x;
          maxY = maxY > y ? maxY : y;
        }
      }
    }

    if (!foundWound) return null;

    // Add padding
    const padding = 20;
    minX = (minX - padding).clamp(0, maskSize);
    minY = (minY - padding).clamp(0, maskSize);
    maxX = (maxX + padding).clamp(0, maskSize);
    maxY = (maxY + padding).clamp(0, maskSize);

    // Scale coordinates to original image size
    final scaleX = image.width / maskSize;
    final scaleY = image.height / maskSize;

    final cropX = (minX * scaleX).round();
    final cropY = (minY * scaleY).round();
    final cropW = ((maxX - minX) * scaleX).round();
    final cropH = ((maxY - minY) * scaleY).round();

    // Crop image
    final cropped = img.copyCrop(
      image,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    return img.encodeJpg(cropped, quality: 90);
  }
}
