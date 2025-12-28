import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../models/wound_record.dart';
import '../models/analysis_result.dart';
import '../services/tflite_service.dart';
import '../services/database_service.dart';
import '../services/image_service.dart';
import '../utils/constants.dart';

class AnalysisScreen extends StatefulWidget {
  final File imageFile;
  final Patient patient;
  final String woundLocation;
  final String capturedBy;
  final String? notes;

  const AnalysisScreen({
    super.key,
    required this.imageFile,
    required this.patient,
    required this.woundLocation,
    required this.capturedBy,
    this.notes,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  bool _isAnalyzing = true;
  AnalysisResult? _result;
  String? _error;

  double _overlayOpacity = 0.5;
  Uint8List? _imageBytes;

  bool _isSaving = false;
  bool _isSaved = false;

  late AnimationController _animationController;

  // ✅ Patch 2 helper: robust stage parsing ("Stage_1", "Stage 1", "Stage_1 (x)")
  int _stageNumberFromKey(String key) {
    final m = RegExp(r'(\d+)').firstMatch(key);
    return m != null ? int.parse(m.group(1)!) : 1;
  }

  int get _predictedStageNum =>
      _result == null ? 1 : _stageNumberFromKey(_result!.predictedStage.toString());

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _runAnalysis();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    try {
      setState(() {
        _isAnalyzing = true;
        _error = null;
      });

      _imageBytes = await widget.imageFile.readAsBytes();
      final tfliteService = context.read<TFLiteService>();

      // ✅ Ensure API is ready
      if (!tfliteService.isInitialized) {
        await tfliteService.initialize();
      }

      final result = await tfliteService.analyzeWound(_imageBytes!);

      // ✅ Patch 3: prevent setState after leaving screen
      if (!mounted) return;
      setState(() {
        _result = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isAnalyzing
          ? _buildLoadingState()
          : _error != null
              ? _buildErrorState()
              : _buildResultsView(),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated image preview
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.file(widget.imageFile, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 48),

              // Animated loader
              RotationTransition(
                turns: _animationController,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 3,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.white, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Analyzing Wound',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Running AI segmentation & classification',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
            ),
            const SizedBox(height: 24),
            const Text(
              'Analysis Failed',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _runAnalysis,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsView() {
    return CustomScrollView(
      slivers: [
        // Image Header
        SliverToBoxAdapter(child: _buildImageHeader()),

        // Results Content
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStageCard(),
                const SizedBox(height: 20),
                _buildConfidenceBreakdown(),
                const SizedBox(height: 20),
                _buildWoundAreaCard(),
                const SizedBox(height: 20),
                _buildDetailsCard(),
                const SizedBox(height: 24),
                _buildActionButtons(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageWithMaskOverlay({
    required double height,
  }) {
    final maskBytes = _result?.segmentationMask; // Uint8List? from API

    return Container(
      width: double.infinity,
      height: height,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Base wound image
          Image.file(
            widget.imageFile,
            fit: BoxFit.contain,
          ),

          // Mask overlay (if available)
          if (maskBytes != null)
            Opacity(
              opacity: _overlayOpacity,
              child: ColorFiltered(
                // Turn grayscale mask into a RED overlay with transparency based on mask intensity.
                colorFilter: const ColorFilter.matrix([
                  0, 0, 0, 0, 255, // R = 255
                  0, 0, 0, 0, 0,   // G = 0
                  0, 0, 0, 0, 0,   // B = 0
                  1, 0, 0, 0, 0,   // A = input R (mask intensity)
                ]),
                child: Image.memory(
                  maskBytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ Patch 1: Use overlay widget + opacity slider
  Widget _buildImageHeader() {
    final hasMask = _result?.segmentationMask != null;

    return Stack(
      children: [
        // Image + overlay
        SizedBox(
          width: double.infinity,
          height: 350,
          child: _buildImageWithMaskOverlay(height: 350),
        ),

        // Gradient overlay at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppTheme.background,
                ],
              ),
            ),
          ),
        ),

        // Back button
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        ),

        // Stage Badge
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.getStageColor(_predictedStageNum),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.getStageColor(_predictedStageNum).withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              _result!.stageName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),

        // Overlay opacity slider (only if mask exists)
        if (hasMask)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    "Mask",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: _overlayOpacity,
                      min: 0,
                      max: 1,
                      onChanged: (v) => setState(() => _overlayOpacity = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStageCard() {
    final stageColor = AppTheme.getStageColor(_predictedStageNum);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: stageColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.medical_information_rounded,
                  color: stageColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Predicted Stage',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _result!.stageName,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: stageColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _result!.formattedConfidence,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _result!.stageDescription,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBreakdown() {
    final predictedStageNum = _predictedStageNum;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confidence Breakdown',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // ✅ Patch 2: correct parsing + correct isSelected logic
          ..._result!.stageProbabilities.entries.map((entry) {
            final stageNum = _stageNumberFromKey(entry.key);
            final isSelected = stageNum == predictedStageNum;
            final percentage = entry.value * 100;

            final niceLabel = entry.key.replaceAll('_', ' '); // "Stage_1" -> "Stage 1"

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        niceLabel,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppTheme.getStageColor(stageNum)
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: entry.value,
                      minHeight: 10,
                      backgroundColor: AppTheme.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation(
                        isSelected
                            ? AppTheme.getStageColor(stageNum)
                            : AppTheme.getStageColor(stageNum).withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildWoundAreaCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.tealGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.square_foot_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimated Wound Area',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  _result!.formattedWoundArea,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'of image area (${_result!.woundPixels} pixels)',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Record Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(Icons.person_outline, 'Patient', widget.patient.name),
          _buildDetailRow(Icons.location_on_outlined, 'Location', widget.woundLocation),
          _buildDetailRow(Icons.badge_outlined, 'Captured By', widget.capturedBy),
          _buildDetailRow(Icons.timer_outlined, 'Analysis Time',
              '${_result!.inferenceTime.inMilliseconds}ms'),
          if (widget.notes != null && widget.notes!.isNotEmpty)
            _buildDetailRow(Icons.notes_outlined, 'Notes', widget.notes!),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text('$label:', style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {}, // TODO: View recommendations
            icon: const Icon(Icons.recommend_outlined),
            label: const Text('Recommendations'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSaved ? null : _saveRecord,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(_isSaved ? Icons.check : Icons.save_rounded),
            label: Text(_isSaved ? 'Saved' : 'Save Record'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: _isSaved ? AppTheme.success : null,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveRecord() async {
    if (_result == null || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final imageService = ImageService();
      final db = context.read<DatabaseService>();

      final imagePath =
          await imageService.saveImage(widget.imageFile, widget.patient.id);

      final record = WoundRecord(
        patientId: widget.patient.id,
        location: widget.woundLocation,
        notes: widget.notes,
        capturedBy: widget.capturedBy,
        imagePath: imagePath,
        maskPath: null,
        predictedStage: _result!.predictedStage,
        confidence: _result!.confidence,
        stageProbabilities: _result!.stageProbabilities,
        woundAreaPercent: _result!.woundAreaPercent,
      );

      await db.insertWoundRecord(record);

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isSaved = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Record saved successfully'),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}
