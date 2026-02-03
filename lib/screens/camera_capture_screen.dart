import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../services/inference_service.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  bool _isInitialized = false;

  // Tap-to-scan detection
  bool _isScanning = false;
  bool _scanInProgress = false;
  bool _showGrid = false;
  bool? _woundDetected; // null = not yet decided
  double? _lastAreaPercent;
  String? _qualityHint;

  // Tune these
  static const int _modelSize = 320; // your model input
  // Stricter live thresholds to reduce false positives.
  static const double _minAreaPercentToCountAsWound = 4.0; // 4.0% as "present"
  static const double _minConfidenceToCountAsWound = 0.85;
  static const double _minSkinPercent = 8.0;
  static const double _minMeanLuma = 35;
  static const double _maxMeanLuma = 220;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);

    _controller = CameraController(
      camera,
      // If live inference feels laggy, change to medium.
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();

    if (!mounted) return;
    setState(() => _isInitialized = true);

  }

  Future<void> _stopLiveDetection() async {
    if (_controller == null) return;
    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  @override
  void dispose() {
    _stopLiveDetection();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureImage() async {
    if (_controller == null) return;
    if (!_controller!.value.isInitialized) return;

    // Stop stream first (camera plugin requirement)
    await _stopLiveDetection();

    final file = await _controller!.takePicture();
    if (!mounted) return;

    Navigator.pop(context, File(file.path));
  }

  Future<void> _scanOnce() async {
    if (_controller == null) return;
    if (!_controller!.value.isInitialized) return;
    if (_scanInProgress) return;

    setState(() {
      _isScanning = true;
      _scanInProgress = true;
      _woundDetected = null;
      _lastAreaPercent = null;
      _qualityHint = null;
    });

    if (_controller!.value.isStreamingImages) {
      await _stopLiveDetection();
    }

    await _controller!.startImageStream((CameraImage frame) async {
      if (!_scanInProgress) return;
      _scanInProgress = false;
      await _runDetection(frame);
    });
  }

  Future<void> _runDetection(CameraImage frame) async {
    try {
      final lightingIssue = _checkLighting(frame);
      if (lightingIssue != null) {
        if (!mounted) return;
        setState(() {
          _qualityHint = lightingIssue;
          _woundDetected = false;
          _lastAreaPercent = null;
        });
        return;
      }

      final skinIssue = _checkSkinPresence(frame);
      if (skinIssue != null) {
        if (!mounted) return;
        setState(() {
          _qualityHint = skinIssue;
          _woundDetected = false;
          _lastAreaPercent = null;
        });
        return;
      }

      final bytes = _frameToModelJpeg(frame);
      final tflite = context.read<TFLiteService>();
      final result = await tflite.analyzeWound(bytes);

      final detected = (result.woundAreaPercent >= _minAreaPercentToCountAsWound) &&
          (result.confidence >= _minConfidenceToCountAsWound);

      if (!mounted) return;
      setState(() {
        _woundDetected = detected;
        _lastAreaPercent = result.woundAreaPercent;
        _qualityHint = null;
      });
    } catch (_) {
      // Ignore occasional stream/inference failures
    } finally {
      await _stopLiveDetection();
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final boxColor = _getBoxColor();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_controller!),

                  // Square boundary + overlay
                  CustomPaint(
                    painter: WoundFramePainter(
                      boxColor: boxColor,
                      showCorners: true,
                      squareScale: 0.72,
                      showGrid: _showGrid,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top left close
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Top right Scan button
          Positioned(
            top: 52,
            right: 16,
            child: GestureDetector(
              onTap: _isScanning ? null : _scanOnce,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 12,
                      color: _isScanning ? Colors.white54 : Colors.greenAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isScanning ? 'SCANNING' : 'SCAN',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: 104,
            right: 16,
            child: GestureDetector(
              onTap: () => setState(() => _showGrid = !_showGrid),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.grid_on, size: 12, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      _showGrid ? 'GRID ON' : 'GRID',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Instruction + detection status
          Positioned(
            top: 105,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'Align wound within square',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Keep 20-30 cm away for consistency',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                _buildDetectionPill(),
              ],
            ),
          ),

          // Capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _captureImage,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getBoxColor() {
    if (_qualityHint != null) return Colors.amberAccent;

    // During detection / not decided yet
    if (_woundDetected == null) return Colors.white;

    return _woundDetected! ? Colors.greenAccent : Colors.redAccent;
  }

  Widget _buildDetectionPill() {
    if (_isScanning) {
      return _pill('Scanning...', Colors.white70);
    }
    if (_qualityHint != null) {
      return _pill(_qualityHint!, Colors.amberAccent);
    }
    if (_woundDetected == null) {
      return _pill('Tap Scan to analyze', Colors.white70);
    }

    final text = _woundDetected! ? 'Wound detected' : 'No wound detected';
    final color = _woundDetected! ? Colors.greenAccent : Colors.redAccent;

    final extra = (_lastAreaPercent == null) ? '' : ' • ${_lastAreaPercent!.toStringAsFixed(2)}% area';
    return _pill('$text$extra', color);
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }

  String? _checkLighting(CameraImage frame) {
    final yPlane = frame.planes[0].bytes;
    final yRowStride = frame.planes[0].bytesPerRow;
    final width = frame.width;
    final height = frame.height;

    const stride = 12;
    int total = 0;
    int count = 0;

    for (int y = 0; y < height; y += stride) {
      final row = yRowStride * y;
      for (int x = 0; x < width; x += stride) {
        total += yPlane[row + x];
        count++;
      }
    }

    final avg = count == 0 ? 0 : total / count;
    if (avg < _minMeanLuma) {
      return 'Too dark - increase lighting';
    }
    if (avg > _maxMeanLuma) {
      return 'Too bright - reduce glare';
    }
    return null;
  }

  String? _checkSkinPresence(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;

    final yPlane = frame.planes[0].bytes;
    final uPlane = frame.planes[1].bytes;
    final vPlane = frame.planes[2].bytes;

    final yRowStride = frame.planes[0].bytesPerRow;
    final uvRowStride = frame.planes[1].bytesPerRow;
    final uvPixelStride = frame.planes[1].bytesPerPixel ?? 1;

    const stride = 12;
    int skinCount = 0;
    int count = 0;

    for (int y = 0; y < height; y += stride) {
      final yRow = yRowStride * y;
      final uvRow = uvRowStride * (y >> 1);

      for (int x = 0; x < width; x += stride) {
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;
        final u = uPlane[uvIndex];
        final v = vPlane[uvIndex];

        // Basic YUV skin range heuristic.
        if (u >= 77 && u <= 127 && v >= 133 && v <= 173) {
          skinCount++;
        }
        count++;
      }
    }

    if (count == 0) return null;
    final percent = (skinCount / count) * 100.0;
    if (percent < _minSkinPercent) {
      return 'Move closer to skin/wound area';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Frame -> JPEG(320x320) pipeline (center square crop like your guide box)
  // ---------------------------------------------------------------------------

  Uint8List _frameToModelJpeg(CameraImage frame) {
    // Convert YUV420 -> RGB image
    final rgb = _yuv420ToImage(frame);

    // Rotate if needed (most devices output landscape frames)
    final rotated = _rotateToPortraitIfNeeded(rgb);

    // Center-crop square
    final side = math.min(rotated.width, rotated.height);
    final x = (rotated.width - side) ~/ 2;
    final y = (rotated.height - side) ~/ 2;
    final cropped = img.copyCrop(rotated, x: x, y: y, width: side, height: side);

    // Resize to model input
    final resized = img.copyResize(cropped, width: _modelSize, height: _modelSize);

    // Encode jpeg
    return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
  }

  img.Image _rotateToPortraitIfNeeded(img.Image input) {
    // Simple portrait assumption: if width > height, rotate 90
    if (input.width > input.height) {
      return img.copyRotate(input, angle: 90);
    }
    return input;
  }

  img.Image _yuv420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final yRowStride = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final out = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final yRow = yRowStride * y;
      final uvRow = uvRowStride * (y >> 1);

      for (int x = 0; x < width; x++) {
        final yIndex = yRow + x;

        final uvIndex = uvRow + (x >> 1) * uvPixelStride;

        final yp = yPlane[yIndex];
        final up = uPlane[uvIndex];
        final vp = vPlane[uvIndex];

        // YUV420 to RGB
        int r = (yp + (1.370705 * (vp - 128))).round();
        int g = (yp - (0.337633 * (up - 128)) - (0.698001 * (vp - 128))).round();
        int b = (yp + (1.732446 * (up - 128))).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }
}

class WoundFramePainter extends CustomPainter {
  final Color boxColor;
  final bool showCorners;
  final double squareScale; // 0..1 of the shortest side
  final bool showGrid;

  WoundFramePainter({
    required this.boxColor,
    this.showCorners = true,
    this.squareScale = 0.72,
    this.showGrid = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.50);

    final borderPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final shortest = size.shortestSide;
    final side = shortest * squareScale;

    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );

    // Overlay cutout
    final bg = Path()..addRect(Offset.zero & size);
    final cutout = Path()..addRRect(RRect.fromRectXY(rect, 14, 14));
    final overlay = Path.combine(PathOperation.difference, bg, cutout);
    canvas.drawPath(overlay, overlayPaint);

    // Border
    canvas.drawRRect(RRect.fromRectXY(rect, 14, 14), borderPaint);

    if (showGrid) {
      final gridPaint = Paint()
        ..color = boxColor.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      final thirdW = rect.width / 3;
      final thirdH = rect.height / 3;
      final left = rect.left;
      final top = rect.top;

      // Vertical grid lines
      canvas.drawLine(
        Offset(left + thirdW, top),
        Offset(left + thirdW, rect.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(left + 2 * thirdW, top),
        Offset(left + 2 * thirdW, rect.bottom),
        gridPaint,
      );

      // Horizontal grid lines
      canvas.drawLine(
        Offset(left, top + thirdH),
        Offset(rect.right, top + thirdH),
        gridPaint,
      );
      canvas.drawLine(
        Offset(left, top + 2 * thirdH),
        Offset(rect.right, top + 2 * thirdH),
        gridPaint,
      );
    }

    // Corner brackets (more “face detection” vibe)
    if (showCorners) {
      final cornerPaint = Paint()
        ..color = boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;

      const cornerLen = 22.0;

      // TL
      canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(cornerLen, 0), cornerPaint);
      canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, cornerLen), cornerPaint);

      // TR
      canvas.drawLine(rect.topRight, rect.topRight + const Offset(-cornerLen, 0), cornerPaint);
      canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, cornerLen), cornerPaint);

      // BL
      canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(cornerLen, 0), cornerPaint);
      canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -cornerLen), cornerPaint);

      // BR
      canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-cornerLen, 0), cornerPaint);
      canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -cornerLen), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WoundFramePainter oldDelegate) {
    return oldDelegate.boxColor != boxColor ||
        oldDelegate.squareScale != squareScale ||
        oldDelegate.showCorners != showCorners ||
        oldDelegate.showGrid != showGrid;
  }
}
