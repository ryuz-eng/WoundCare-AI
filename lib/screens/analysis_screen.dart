import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/patient.dart';
import '../models/wound_record.dart';
import '../models/analysis_result.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../services/image_service.dart';
import '../services/notification_service.dart';
import '../services/triage_service.dart';
import '../widgets/inline_tip.dart';
import '../widgets/recommendation_dialog.dart';
import 'tissue_annotation_screen.dart';
import 'wound_history_screen.dart';
import '../utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

class AnalysisScreen extends StatefulWidget {
  final File imageFile;
  final Patient patient;
  final String woundLocation;
  final String capturedBy;
  final String? notes;
  final String s3Key;
  final String encryptedKeyB64;
  final String ivB64;
  final String contentType;
  final Map<String, dynamic> checklistData;

  const AnalysisScreen({
    super.key,
    required this.imageFile,
    required this.patient,
    required this.woundLocation,
    required this.capturedBy,
    this.notes,
    required this.s3Key,
    required this.encryptedKeyB64,
    required this.ivB64,
    required this.contentType,
    required this.checklistData,
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
  bool _showClinicalDetails = false;
  String? _tissueMaskPath;
  Map<String, double>? _tissuePercentages;
  Map<String, dynamic>? _triageData;
  bool _isTriaging = false;

  late AnimationController _animationController;

  int _stageNumberFromKey(String key) {
    final m = RegExp(r'(\d+)').firstMatch(key);
    return m != null ? int.parse(m.group(1)!) : 1;
  }

  void _openRecommendations() {
    if (_result == null) return;

    final stage = _predictedStageNum.clamp(1, 4);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecommendationDialog(stage: stage),
    );
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
      await _waitForServer();
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse(AppConstants.inferUrl),
        headers: headers,
        body: jsonEncode({
          's3Key': widget.s3Key,
          'encryptedKeyB64': widget.encryptedKeyB64,
          'ivB64': widget.ivB64,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Inference failed: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final predictedStage = _parseStage(data['predicted_stage']);
      final confidence = _clampUnit(_asDouble(data['confidence'], fallback: 0));
      final woundAreaPercent =
          _clampPercent(_asDouble(data['wound_area_percent'], fallback: 0));
      final totalPixels =
          _asInt(data['total_pixels'], fallback: 1).clamp(1, 1 << 30).toInt();
      final woundPixelsRaw = _asInt(data['wound_pixels'], fallback: 0);
      final woundPixels = woundPixelsRaw.clamp(0, totalPixels).toInt();
      final inferenceTimeMs = _asInt(data['inference_time_ms'], fallback: 0).clamp(
        0,
        1 << 30,
      ).toInt();
      final stageProbabilitiesRaw =
          (data['stage_probabilities'] as Map?)?.cast<String, dynamic>() ?? const {};
      var stageProbabilities = stageProbabilitiesRaw.map(
        (key, value) => MapEntry(key, _clampUnit(_asDouble(value))),
      );
      if (stageProbabilities.isEmpty) {
        stageProbabilities = {
          'Stage_$predictedStage': confidence,
        };
      }
      final maskBase64 = data['segmentation_mask_base64'] as String?;
      final maskBytes = maskBase64 == null ? null : base64Decode(maskBase64);

      final result = AnalysisResult(
        predictedStage: predictedStage,
        confidence: confidence,
        stageProbabilities: stageProbabilities,
        segmentationMask: maskBytes,
        woundAreaPercent: woundAreaPercent,
        woundPixels: woundPixels,
        totalPixels: totalPixels,
        inferenceTime: Duration(milliseconds: inferenceTimeMs),
      );

      // ✅ Patch 3: prevent setState after leaving screen
      if (!mounted) return;
      setState(() {
        _result = result;
        _isAnalyzing = false;
      });
      final isCaregiver = context.read<AppState>().isCaregiver;
      if (!isCaregiver && widget.checklistData.isNotEmpty) {
        unawaited(_runTriage());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isAnalyzing = false;
      });
    }
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  double _clampUnit(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampPercent(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    return value.clamp(0.0, 100.0).toDouble();
  }

  Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return headers;
    }
    try {
      final token = await user.getIdToken(true);
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}
    return headers;
  }

  Future<void> _waitForServer() async {
    final uri = Uri.parse('${AppConstants.baseUrl}/health');
    const delays = [
      Duration(milliseconds: 300),
      Duration(milliseconds: 600),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2400),
    ];

    for (var i = 0; i < delays.length; i++) {
      try {
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          return;
        }
      } catch (_) {}
      await Future.delayed(delays[i]);
    }
  }

  int _parseStage(dynamic raw) {
    if (raw is num) {
      final stage = raw.toInt();
      return stage.clamp(1, 4).toInt();
    }
    final text = raw?.toString() ?? '';
    final match = RegExp(r'(\d+)').firstMatch(text);
    final parsed = match == null ? 1 : int.parse(match.group(1)!);
    return parsed.clamp(1, 4).toInt();
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
    final isCaregiver = context.watch<AppState>().isCaregiver;

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
                  if (isCaregiver) _buildCaregiverSummary(),
                  if (isCaregiver) const SizedBox(height: 20),
                  _buildStageCard(),
                  const SizedBox(height: 12),
                  const InlineTip(
                    text: 'Tip: If confidence is low, retake the photo with steadier lighting.',
                  ),
                  const SizedBox(height: 12),
                  _buildAnnotateButton(),
                  if (_tissueMaskPath != null) ...[
                    const SizedBox(height: 8),
                    _buildViewTissueOverlayButton(),
                  ],
                  const SizedBox(height: 20),
                  _buildConfidenceCallout(),
                  if (!isCaregiver) ...[
                    const SizedBox(height: 16),
                    _buildTriageCard(),
                  ],
                  const SizedBox(height: 20),
                  if (!isCaregiver || _showClinicalDetails) ...[
                    _buildConfidenceBreakdown(),
                    const SizedBox(height: 20),
                  ],
                  _buildWoundAreaCard(),
                  const SizedBox(height: 20),
                  if (_tissuePercentages != null) ...[
                    _buildTissueSummaryCard(),
                    const SizedBox(height: 20),
                  ],
                  if (isCaregiver) _buildClinicalToggleButton(),
                  if (!isCaregiver || _showClinicalDetails) _buildDetailsCard(),
                  const SizedBox(height: 24),
                  _buildSafetyDisclaimer(),
                  const SizedBox(height: 16),
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

  Widget _buildConfidenceCallout() {
    final confidence = _result!.confidence;
    String label;
    String message;
    Color color;

    if (confidence >= 0.8) {
      label = 'High confidence';
      message = 'Result is consistent. You can proceed.';
      color = AppTheme.success;
    } else if (confidence >= 0.6) {
      label = 'Medium confidence';
      message = 'Review the photo and consider a re-check.';
      color = AppTheme.warning;
    } else {
      label = 'Low confidence';
      message = 'Retake the photo or consult a nurse.';
      color = AppTheme.error;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            _result!.formattedConfidence,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI results are assistive and not a medical diagnosis. '
              'Review the image and patient context before acting.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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

  Widget _buildClinicalToggleButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: () => setState(() => _showClinicalDetails = !_showClinicalDetails),
        child: Text(
          _showClinicalDetails ? 'Hide clinical details' : 'Show clinical details',
        ),
      ),
    );
  }

  _CareSummary _careSummary(int stage, double confidence) {
    final lowConfidence = confidence < 0.6;

    if (stage >= 4) {
      return _CareSummary(
        riskLabel: 'Urgent',
        action: 'Immediate clinical review recommended.',
        color: AppTheme.error,
        note: lowConfidence ? 'Low confidence. Review by a nurse recommended.' : null,
      );
    }
    if (stage == 3) {
      return _CareSummary(
        riskLabel: 'High risk',
        action: 'Notify senior nurse and document changes.',
        color: AppTheme.error,
        note: lowConfidence ? 'Low confidence. Review by a nurse recommended.' : null,
      );
    }
    if (stage == 2) {
      return _CareSummary(
        riskLabel: 'Moderate risk',
        action: 'Monitor closely and notify if worsening.',
        color: AppTheme.warning,
        note: lowConfidence ? 'Low confidence. Review by a nurse recommended.' : null,
      );
    }

    return _CareSummary(
      riskLabel: 'Low risk',
      action: 'Monitor and document.',
      color: AppTheme.success,
      note: lowConfidence ? 'Low confidence. Review by a nurse recommended.' : null,
    );
  }

  Widget _buildCaregiverSummary() {
    final summary = _careSummary(_predictedStageNum, _result!.confidence);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: summary.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: summary.color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.priority_high, color: summary.color),
              const SizedBox(width: 8),
              Text(
                summary.riskLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: summary.color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary.action,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
          ),
          if (summary.note != null) ...[
            const SizedBox(height: 8),
            Text(
              summary.note!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
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
            onPressed: _result == null ? null : _openRecommendations,
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

  Widget _buildTissueSummaryCard() {
    final data = _tissuePercentages ?? {};
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tissue Composition',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.value.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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

  Widget _buildAnnotateButton() {
    return OutlinedButton.icon(
      onPressed: _result?.segmentationMask == null ? null : _openTissueAnnotation,
      icon: const Icon(Icons.edit_outlined),
      label: Text(
        _tissuePercentages == null ? 'Annotate tissues' : 'Edit tissue labels',
      ),
    );
  }

  Widget _buildViewTissueOverlayButton() {
    return TextButton.icon(
      onPressed: _showTissueOverlay,
      icon: const Icon(Icons.visibility_outlined),
      label: const Text('View tissue overlay'),
    );
  }

  Future<void> _runTriage() async {
    if (_result == null) return;
    setState(() => _isTriaging = true);
    final data = await TriageService().generateTriage(
      result: _result!,
      checklist: widget.checklistData,
      patientId: widget.patient.id,
    );
    if (!mounted) return;
    setState(() {
      _triageData = data;
      _isTriaging = false;
    });
  }

  Widget _buildTriageCard() {
    if (_isTriaging) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Generating checklist-guided triage...'),
          ],
        ),
      );
    }
    if (_triageData == null) return const SizedBox.shrink();
    final risk = (_triageData!['risk_level'] ?? 'low').toString();
    final actions = ((_triageData!['top_actions'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final flags = ((_triageData!['flags'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) {
          final f = e.trim().toLowerCase();
          return f.isNotEmpty &&
              !f.startsWith('gemini_') &&
              !f.startsWith('fallback_point=') &&
              !f.startsWith('gemini fallback') &&
              !f.startsWith('gemini blocked');
        })
        .toList();
    final source = (_triageData!['source'] ?? 'rules').toString().toLowerCase();
    final engineLabel = source.contains('gemini')
        ? 'Gemini-assisted'
        : source.contains('bedrock')
            ? 'Bedrock-assisted'
            : 'Rules-only';
    final color = risk == 'urgent'
        ? AppTheme.error
        : risk == 'high'
            ? AppTheme.stage3
            : risk == 'medium'
                ? AppTheme.warning
                : AppTheme.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_folder_outlined, color: color),
              const SizedBox(width: 8),
              Text(
                'Checklist Triage: ${risk.toUpperCase()}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Engine: $engineLabel',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Flags: ${flags.join(' • ')}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...actions.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $a'),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Assistive output only; clinical judgment required.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showTissueOverlay() {
    if (_tissueMaskPath == null) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        double opacity = 0.6;
        return FutureBuilder<ui.Image>(
          future: _buildOverlayFromMask(_tissueMaskPath!),
          builder: (context, snapshot) {
            return StatefulBuilder(
              builder: (context, setState) {
                final overlay = snapshot.data;
                return Dialog(
                  insetPadding: const EdgeInsets.all(16),
                  child: Container(
                    color: Colors.black,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              if (overlay != null)
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: opacity,
                                    child: RawImage(
                                      image: overlay,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  color: Colors.white,
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'Opacity',
                                style: TextStyle(fontSize: 12),
                              ),
                              Expanded(
                                child: Slider(
                                  value: opacity,
                                  min: 0,
                                  max: 1,
                                  onChanged: (value) =>
                                      setState(() => opacity = value),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<ui.Image> _buildOverlayFromMask(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Failed to decode tissue mask');
    }
    final w = decoded.width;
    final h = decoded.height;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pixel = decoded.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final idx = (y * w + x) * 4;
        if (r == 0 && g == 0 && b == 0) {
          rgba[idx + 3] = 0;
          continue;
        }
        rgba[idx] = r;
        rgba[idx + 1] = g;
        rgba[idx + 2] = b;
        rgba[idx + 3] = 200;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<void> _openTissueAnnotation() async {
    if (_result?.segmentationMask == null) return;
    final result = await Navigator.push<TissueAnnotationResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TissueAnnotationScreen(
          imagePath: widget.imageFile.path,
          woundMaskBytes: _result!.segmentationMask!,
          patientId: widget.patient.id,
          existingTissueMaskPath: _tissueMaskPath,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _tissueMaskPath = result.maskPath;
      _tissuePercentages = result.percentages;
    });
  }

  Future<void> _saveRecord() async {
    if (_result == null || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      if (_result!.confidence < 0.6) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Low confidence result'),
            content: const Text(
              'This result has low confidence. Consider retaking the photo. '
              'Do you want to save anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Retake'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        );

        if (proceed != true) {
          setState(() => _isSaving = false);
          return;
        }
      }

      final imageService = ImageService();
      final db = context.read<DatabaseService>();

      final existingPatient = await db.getPatientById(widget.patient.id);
      if (existingPatient == null) {
        await db.insertPatient(widget.patient);
      }

      final imagePath =
          await imageService.saveImage(widget.imageFile, widget.patient.id);
      if (imagePath.trim().isEmpty) {
        throw Exception('Failed to resolve local image path');
      }

      final capturedBy = widget.capturedBy.trim();
      if (widget.patient.id.trim().isEmpty ||
          widget.woundLocation.trim().isEmpty ||
          capturedBy.isEmpty) {
        throw Exception('Missing required record details');
      }

      String? maskPath;
      if (_result?.segmentationMask != null) {
        maskPath = await imageService.saveMask(
          _result!.segmentationMask!,
          AppConstants.maskOutputSize,
          AppConstants.maskOutputSize,
          widget.patient.id,
        );
      }

      final record = WoundRecord(
        patientId: widget.patient.id,
        location: widget.woundLocation,
        notes: widget.notes,
        capturedBy: capturedBy,
        imagePath: imagePath,
        maskPath: maskPath,
        predictedStage: _result!.predictedStage,
        confidence: _result!.confidence,
        stageProbabilities: _result!.stageProbabilities,
        woundAreaPercent: _result!.woundAreaPercent,
        tissueMaskPath: _tissueMaskPath,
        tissuePercentages: _tissuePercentages,
        checklistData: widget.checklistData.isEmpty ? null : widget.checklistData,
        triageData: _triageData,
      );

        await db.insertWoundRecord(record);

        final prefs = await SharedPreferences.getInstance();
        final dueAt = DateTime.now()
            .add(
              const Duration(seconds: AppConstants.retakeReminderSeconds),
            )
            .millisecondsSinceEpoch;
        await prefs.setInt('recheck_due_${widget.patient.id}', dueAt);

        try {
          await NotificationService().scheduleRetakeReminder(
            patientId: widget.patient.id,
            patientName: widget.patient.name,
            location: widget.woundLocation,
            delay: const Duration(
              seconds: AppConstants.retakeReminderSeconds,
            ),
          );
        } catch (_) {}

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _isSaved = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Record saved successfully'),
        ),
      );

      
      WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => WoundHistoryScreen(
            patient: widget.patient,
            location: widget.woundLocation,
          ),
        ),
        (route) => false,
      );
    });
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

class _CareSummary {
  final String riskLabel;
  final String action;
  final Color color;
  final String? note;

  const _CareSummary({
    required this.riskLabel,
    required this.action,
    required this.color,
    this.note,
  });
}
