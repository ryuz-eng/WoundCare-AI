import 'dart:typed_data';
import 'package:flutter/material.dart';

class SegmentationOverlay extends StatelessWidget {
  final Uint8List maskData;
  final int maskSize;
  final Color color;

  const SegmentationOverlay({
    super.key,
    required this.maskData,
    required this.maskSize,
    this.color = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SegmentationPainter(
        maskData: maskData,
        maskSize: maskSize,
        color: color,
      ),
      size: Size.infinite,
    );
  }
}

class _SegmentationPainter extends CustomPainter {
  final Uint8List maskData;
  final int maskSize;
  final Color color;

  _SegmentationPainter({
    required this.maskData,
    required this.maskSize,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final scaleX = size.width / maskSize;
    final scaleY = size.height / maskSize;

    // Draw each pixel that is part of the mask
    for (int y = 0; y < maskSize; y++) {
      int startX = -1;
      
      for (int x = 0; x <= maskSize; x++) {
        final isWound = x < maskSize && maskData[y * maskSize + x] > 127;
        
        if (isWound && startX == -1) {
          // Start of a wound segment
          startX = x;
        } else if (!isWound && startX != -1) {
          // End of a wound segment - draw rectangle
          canvas.drawRect(
            Rect.fromLTWH(
              startX * scaleX,
              y * scaleY,
              (x - startX) * scaleX,
              scaleY,
            ),
            paint,
          );
          startX = -1;
        }
      }
    }

    // Draw outline
    final outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Simple edge detection for outline
    for (int y = 1; y < maskSize - 1; y++) {
      for (int x = 1; x < maskSize - 1; x++) {
        final current = maskData[y * maskSize + x] > 127;
        if (!current) continue;

        // Check if this is an edge pixel
        final top = maskData[(y - 1) * maskSize + x] > 127;
        final bottom = maskData[(y + 1) * maskSize + x] > 127;
        final left = maskData[y * maskSize + (x - 1)] > 127;
        final right = maskData[y * maskSize + (x + 1)] > 127;

        if (!top || !bottom || !left || !right) {
          canvas.drawRect(
            Rect.fromLTWH(
              x * scaleX,
              y * scaleY,
              scaleX,
              scaleY,
            ),
            outlinePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentationPainter oldDelegate) {
    return oldDelegate.maskData != maskData ||
        oldDelegate.maskSize != maskSize ||
        oldDelegate.color != color;
  }
}