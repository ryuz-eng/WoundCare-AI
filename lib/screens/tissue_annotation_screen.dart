import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../config/theme.dart';
import '../services/image_service.dart';

class TissueAnnotationResult {
  final String maskPath;
  final Map<String, double> percentages;

  const TissueAnnotationResult({
    required this.maskPath,
    required this.percentages,
  });
}

class TissueLabel {
  final int id;
  final String name;
  final Color color;

  const TissueLabel(this.id, this.name, this.color);
}

class TissueAnnotationScreen extends StatefulWidget {
  final String imagePath;
  final Uint8List woundMaskBytes;
  final String patientId;
  final String? existingTissueMaskPath;

  const TissueAnnotationScreen({
    super.key,
    required this.imagePath,
    required this.woundMaskBytes,
    required this.patientId,
    this.existingTissueMaskPath,
  });

  @override
  State<TissueAnnotationScreen> createState() => _TissueAnnotationScreenState();
}

class _TissueAnnotationScreenState extends State<TissueAnnotationScreen> {
  static const _labels = [
    TissueLabel(1, 'Granulation', Color(0xFFEF4444)),
    TissueLabel(2, 'Slough', Color(0xFFF59E0B)),
    TissueLabel(3, 'Necrosis', Color(0xFF111827)),
  ];

  late final int _maskWidth;
  late final int _maskHeight;
  late final Uint8List _woundMask;
  late Uint8List _labelMask;
  ui.Image? _overlayImage;
  ui.Image? _outlineImage;
  double _scaleToContain = 1;
  double _displayWidth = 0;
  double _displayHeight = 0;

  int _selectedLabel = 1;
  bool _isErasing = false;
  double _brushSize = 10;
  double _overlayOpacity = 0.6;
  bool _loading = true;

  final List<Uint8List> _history = [];
  Timer? _overlayTimer;
  bool _overlayDirty = false;
  Timer? _strokeTimer;
  bool _strokeDirty = false;
  _Stroke? _activeStroke;

  @override
  void initState() {
    super.initState();
    _initMasks();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _strokeTimer?.cancel();
    super.dispose();
  }

  Future<void> _initMasks() async {
    final imageBytes = await File(widget.imagePath).readAsBytes();
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      setState(() => _loading = false);
      return;
    }

    final decodedMask = img.decodeImage(widget.woundMaskBytes);
    if (decodedMask == null) {
      setState(() => _loading = false);
      return;
    }

    _maskWidth = decodedImage.width;
    _maskHeight = decodedImage.height;
    final resizedMask = img.copyResize(
      decodedMask,
      width: _maskWidth,
      height: _maskHeight,
      interpolation: img.Interpolation.nearest,
    );
    _woundMask = Uint8List(_maskWidth * _maskHeight);
    for (var y = 0; y < _maskHeight; y++) {
      for (var x = 0; x < _maskWidth; x++) {
        final pixel = resizedMask.getPixel(x, y);
        final maxChannel = [
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
        ].reduce((a, b) => a > b ? a : b);
        _woundMask[y * _maskWidth + x] = maxChannel;
      }
    }

    _labelMask = Uint8List(_maskWidth * _maskHeight);
    if (widget.existingTissueMaskPath != null) {
      await _loadExistingTissueMask(widget.existingTissueMaskPath!);
    }

    await _rebuildOverlay();
    await _rebuildOutline();
    setState(() => _loading = false);
  }

  Future<void> _loadExistingTissueMask(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;

    img.Image source = decoded;
    if (decoded.width != _maskWidth || decoded.height != _maskHeight) {
      source = img.copyResize(
        decoded,
        width: _maskWidth,
        height: _maskHeight,
        interpolation: img.Interpolation.nearest,
      );
    }

    for (var y = 0; y < _maskHeight; y++) {
      for (var x = 0; x < _maskWidth; x++) {
        final pixel = source.getPixel(x, y);
        final a = pixel.a;
        if (a == 0) {
          _labelMask[y * _maskWidth + x] = 0;
          continue;
        }
        final color = Color.fromARGB(
          255,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
        );
        _labelMask[y * _maskWidth + x] = _labelFromColor(color);
      }
    }
  }

  int _labelFromColor(Color color) {
    for (final label in _labels) {
      if (label.color.value == color.value) {
        return label.id;
      }
    }
    return 0;
  }

  Future<void> _rebuildOverlay() async {
    final rgba = Uint8List(_maskWidth * _maskHeight * 4);
    for (var i = 0; i < _labelMask.length; i++) {
      final label = _labelMask[i];
      if (label == 0) {
        rgba[i * 4 + 3] = 0;
        continue;
      }
      final color = _labels[label - 1].color;
      rgba[i * 4] = color.red;
      rgba[i * 4 + 1] = color.green;
      rgba[i * 4 + 2] = color.blue;
      rgba[i * 4 + 3] = 200;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      _maskWidth,
      _maskHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    _overlayImage = await completer.future;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _rebuildOutline() async {
    final rgba = Uint8List(_maskWidth * _maskHeight * 4);
    for (var y = 1; y < _maskHeight - 1; y++) {
      for (var x = 1; x < _maskWidth - 1; x++) {
        final idx = y * _maskWidth + x;
        if (_woundMask[idx] <= 127) continue;
        final isEdge = _woundMask[(y - 1) * _maskWidth + x] <= 127 ||
            _woundMask[(y + 1) * _maskWidth + x] <= 127 ||
            _woundMask[y * _maskWidth + (x - 1)] <= 127 ||
            _woundMask[y * _maskWidth + (x + 1)] <= 127;
        if (!isEdge) continue;
        rgba[idx * 4] = 255;
        rgba[idx * 4 + 1] = 255;
        rgba[idx * 4 + 2] = 255;
        rgba[idx * 4 + 3] = 200;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      _maskWidth,
      _maskHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    _outlineImage = await completer.future;
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleOverlayUpdate() {
    if (_overlayDirty) return;
    _overlayDirty = true;
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 60), () async {
      _overlayDirty = false;
      await _rebuildOverlay();
    });
  }

  void _applyPointToMask(Offset localPosition, double brushSize, int label) {
    if (_maskWidth == 0 || _maskHeight == 0) return;
    final scaledBrush = brushSize;
    final dx = localPosition.dx.clamp(0, _maskWidth - 1);
    final dy = localPosition.dy.clamp(0, _maskHeight - 1);
    final r = scaledBrush;
    final minX = (dx - r).floor().clamp(0, _maskWidth - 1);
    final maxX = (dx + r).ceil().clamp(0, _maskWidth - 1);
    final minY = (dy - r).floor().clamp(0, _maskHeight - 1);
    final maxY = (dy + r).ceil().clamp(0, _maskHeight - 1);
    final rr = r * r;

    for (var y = minY; y <= maxY; y++) {
      final dy2 = (y - dy);
      for (var x = minX; x <= maxX; x++) {
        final dx2 = (x - dx);
        if (dx2 * dx2 + dy2 * dy2 > rr) continue;
        final idx = y * _maskWidth + x;
        if (_woundMask[idx] <= 127) continue;
        _labelMask[idx] = label;
      }
    }
  }

  void _startStroke(Offset localPosition) {
    _activeStroke = _Stroke(
      label: _selectedLabel,
      brushSize: _brushSize,
      isErasing: _isErasing,
      points: [localPosition],
    );
    _scheduleStrokeRepaint();
  }

  void _updateStroke(Offset localPosition) {
    if (_activeStroke == null) return;
    _activeStroke!.points.add(localPosition);
    _scheduleStrokeRepaint();
  }

  Future<void> _endStroke() async {
    final stroke = _activeStroke;
    if (stroke == null) return;
    final label = stroke.isErasing ? 0 : stroke.label;
    for (final point in stroke.points) {
      _applyPointToMask(point, stroke.brushSize, label);
    }
    _activeStroke = null;
    await _rebuildOverlay();
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleStrokeRepaint() {
    if (_strokeDirty) return;
    _strokeDirty = true;
    _strokeTimer?.cancel();
    _strokeTimer = Timer(const Duration(milliseconds: 16), () {
      _strokeDirty = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _saveHistory() {
    _history.add(Uint8List.fromList(_labelMask));
    if (_history.length > 20) {
      _history.removeAt(0);
    }
  }

  void _undo() {
    if (_history.isEmpty) return;
    _labelMask = _history.removeLast();
    _scheduleOverlayUpdate();
  }

  void _clear() {
    _saveHistory();
    _labelMask = Uint8List(_maskWidth * _maskHeight);
    _scheduleOverlayUpdate();
  }

  Future<void> _saveAnnotation() async {
    final pngBytes = _buildTissueMaskPng();
    final path = await ImageService().saveTissueMask(
      pngBytes,
      widget.patientId,
    );
    final percentages = _computePercentages();
    if (!mounted) return;
    Navigator.pop(
      context,
      TissueAnnotationResult(maskPath: path, percentages: percentages),
    );
  }

  Uint8List _buildTissueMaskPng() {
    final output = img.Image(width: _maskWidth, height: _maskHeight);
    for (var y = 0; y < _maskHeight; y++) {
      for (var x = 0; x < _maskWidth; x++) {
        final label = _labelMask[y * _maskWidth + x];
        if (label == 0) {
          output.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        final color = _labels[label - 1].color;
        output.setPixelRgba(x, y, color.red, color.green, color.blue, 255);
      }
    }
    return Uint8List.fromList(img.encodePng(output));
  }

  Map<String, double> _computePercentages() {
    var woundPixels = 0;
    final counts = <int, int>{1: 0, 2: 0, 3: 0};
    for (var i = 0; i < _labelMask.length; i++) {
      if (_woundMask[i] > 127) {
        woundPixels += 1;
        final label = _labelMask[i];
        if (label != 0) {
          counts[label] = (counts[label] ?? 0) + 1;
        }
      }
    }
    if (woundPixels == 0) {
      return {
        'Granulation': 0,
        'Slough': 0,
        'Necrosis': 0,
      };
    }
    return {
      'Granulation': (counts[1]! / woundPixels) * 100,
      'Slough': (counts[2]! / woundPixels) * 100,
      'Necrosis': (counts[3]! / woundPixels) * 100,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Tissue Annotation'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _saveAnnotation,
            child: const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildToolbar(),
                _buildQuickTips(),
                const SizedBox(height: 8),
                Expanded(child: _buildCanvas()),
                _buildFooter(),
              ],
            ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (final label in _labels) ...[
            _buildLabelChip(label),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Undo',
            onPressed: _history.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Quick tips',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Granulation: red, bumpy tissue.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            Text(
              'Slough: yellow/white stringy tissue.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            Text(
              'Necrosis: black or brown dead tissue.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelChip(TissueLabel label) {
    final isSelected = !_isErasing && _selectedLabel == label.id;
    return ChoiceChip(
      label: Text(label.name),
      selected: isSelected,
      selectedColor: label.color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? label.color : AppTheme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: label.color,
          shape: BoxShape.circle,
        ),
      ),
      onSelected: (_) {
        setState(() {
          _selectedLabel = label.id;
          _isErasing = false;
        });
      },
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _maskWidth.toDouble(),
                height: _maskHeight.toDouble(),
                child: GestureDetector(
                  onPanStart: (details) {
                    _saveHistory();
                    _startStroke(details.localPosition);
                  },
                  onPanUpdate: (details) => _updateStroke(details.localPosition),
                  onPanEnd: (_) => _endStroke(),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.fill,
                        ),
                      ),
                      if (_overlayImage != null)
                        Positioned.fill(
                          child: Opacity(
                            opacity: _overlayOpacity,
                            child: RawImage(image: _overlayImage),
                          ),
                        ),
                      if (_outlineImage != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RawImage(image: _outlineImage),
                          ),
                        ),
                      if (_activeStroke != null)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _StrokePainter(
                              stroke: _activeStroke!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Brush', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _brushSize,
                  min: 4,
                  max: 30,
                  onChanged: (value) => setState(() => _brushSize = value),
                ),
              ),
              IconButton(
                tooltip: 'Eraser',
                onPressed: () => setState(() => _isErasing = !_isErasing),
                icon: Icon(
                  _isErasing ? Icons.cleaning_services : Icons.cleaning_services_outlined,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Overlay', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _overlayOpacity,
                  min: 0,
                  max: 1,
                  onChanged: (value) => setState(() => _overlayOpacity = value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stroke {
  final int label;
  final double brushSize;
  final bool isErasing;
  final List<Offset> points;

  _Stroke({
    required this.label,
    required this.brushSize,
    required this.isErasing,
    required this.points,
  });
}

class _StrokePainter extends CustomPainter {
  final _Stroke stroke;

  _StrokePainter({required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.brushSize * 2;

    if (stroke.isErasing) {
      paint.color = Colors.white.withOpacity(0.4);
    } else {
      paint.color = _strokeColor(stroke.label).withOpacity(0.7);
    }

    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  Color _strokeColor(int label) {
    switch (label) {
      case 1:
        return const Color(0xFFEF4444);
      case 2:
        return const Color(0xFFF59E0B);
      case 3:
        return const Color(0xFF111827);
      default:
        return Colors.black;
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.stroke != stroke;
  }
}
