import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:http/http.dart' as http;

import '../models/analysis_result.dart';
import '../utils/constants.dart';

class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  final String _baseUrl = AppConstants.baseUrl;
  http.Client _client = http.Client();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ---------- parsers ----------
  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  double _asDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  int _parseStage(dynamic v) {
    // accepts: 2, "2", "Stage_2", "Stage 2", "Stage_2 (something)"
    if (v == null) return 1;
    if (v is int) return v;

    final s = v.toString();
    final m = RegExp(r'(\d+)').firstMatch(s);
    return m != null ? int.parse(m.group(1)!) : 1;
  }

  void _logJsonResponse(String rawBody, dynamic decoded) {
    // Raw (exact response)
    debugPrint("==== /analyze RAW BODY ====");
    debugPrint(rawBody);

    // Pretty (easier to read)
    try {
      final pretty = const JsonEncoder.withIndent("  ").convert(decoded);
      debugPrint("==== /analyze PRETTY JSON ====");
      debugPrint(pretty);
    } catch (_) {
      // ignore
    }
  }

  Future<void> initialize() async {
    final resp = await _client
        .get(
          Uri.parse("$_baseUrl/health"),
          headers: {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      _isInitialized = true;
    } else {
      throw Exception("Health check failed: ${resp.statusCode} ${resp.body}");
    }

    debugPrint("Using API: $_baseUrl");
  }

  Future<AnalysisResult> analyzeWound(Uint8List imageBytes) async {
    if (!_isInitialized) throw Exception('API not initialized');

    final req = http.MultipartRequest('POST', Uri.parse("$_baseUrl/analyze"));
    req.headers['Accept'] = 'application/json';
    req.files.add(
      http.MultipartFile.fromBytes('file', imageBytes, filename: 'wound.jpg'),
    );

    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception("API error ${resp.statusCode}: ${resp.body}");
    }

    // 1) Decode JSON
    final data = jsonDecode(resp.body);

    // 2) Print exact JSON response (raw + pretty)
    _logJsonResponse(resp.body, data);

    // --- Mask decode ---
    Uint8List? mask;
    final maskB64 = data['segmentation_mask_base64'];
    if (maskB64 is String && maskB64.isNotEmpty) {
      mask = base64Decode(maskB64);
    }

    // --- Stage probabilities ---
    final probs = <String, double>{};
    final rawProbs = data['stage_probabilities'];
    if (rawProbs is Map) {
      rawProbs.forEach((k, v) {
        probs[k.toString()] = _asDouble(v);
      });
    }

    // --- Agreement  ---
    final agreement = data['ensemble_agreement'];
    final double? ensembleAgreement =
        agreement == null ? null : _asDouble(agreement);

    final stageRaw = data['predicted_stage'] ?? data['pred_stage'];
    final predictedStage = _parseStage(stageRaw);

    final confidence = _asDouble(data['confidence']);

    final woundAreaPercent = _asDouble(data['wound_area_percent']);
    final woundPixels = _asInt(data['wound_pixels']);
    final totalPixels = _asInt(data['total_pixels']);

    final inferenceMs = _asInt(data['inference_time_ms'] ?? 0);

    return AnalysisResult(
      predictedStage: predictedStage,
      confidence: confidence,
      stageProbabilities: probs,
      segmentationMask: mask,
      woundAreaPercent: woundAreaPercent,
      woundPixels: woundPixels,
      totalPixels: totalPixels,
      inferenceTime: Duration(milliseconds: inferenceMs),
      ensembleAgreement: ensembleAgreement,
    );
  }

  void dispose() {
    _isInitialized = false;
    _client.close();
    _client = http.Client();
  }
}
