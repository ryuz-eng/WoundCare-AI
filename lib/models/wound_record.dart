import 'package:uuid/uuid.dart';
import 'dart:convert';

class WoundRecord {
  final String id;
  final String patientId;
  final String location;          // Wound location on body
  final String? notes;            // Additional notes
  final String capturedBy;        // Who took the photo
  final String imagePath;         // Local path to wound image
  final String? maskPath;         // Local path to segmentation mask
  final int predictedStage;       // 1-4
  final double confidence;        // 0-1
  final Map<String, double> stageProbabilities; // All class probabilities
  final double woundAreaPercent;  // Percentage of image that is wound
  final double? woundAreaCm2;     // Actual wound area (if scale provided)
  final String? tissueMaskPath;   // Local path to tissue mask (multi-class)
  final Map<String, double>? tissuePercentages; // Tissue composition percentages
  final Map<String, dynamic>? checklistData; // De-identified checklist payload
  final Map<String, dynamic>? triageData; // Rule/LLM triage output
  final DateTime capturedAt;
  final DateTime analyzedAt;

  WoundRecord({
    String? id,
    required this.patientId,
    required this.location,
    this.notes,
    required this.capturedBy,
    required this.imagePath,
    this.maskPath,
    required this.predictedStage,
    required this.confidence,
    required this.stageProbabilities,
    required this.woundAreaPercent,
    this.woundAreaCm2,
    this.tissueMaskPath,
    this.tissuePercentages,
    this.checklistData,
    this.triageData,
    DateTime? capturedAt,
    DateTime? analyzedAt,
  })  : id = id ?? const Uuid().v4(),
        capturedAt = capturedAt ?? DateTime.now(),
        analyzedAt = analyzedAt ?? DateTime.now();

  // Create from database map
  factory WoundRecord.fromMap(Map<String, dynamic> map) {
    return WoundRecord(
      id: map['id'] as String,
      patientId: map['patient_id'] as String,
      location: map['location'] as String,
      notes: map['notes'] as String?,
      capturedBy: map['captured_by'] as String,
      imagePath: map['image_path'] as String,
      maskPath: map['mask_path'] as String?,
      predictedStage: map['predicted_stage'] as int,
      confidence: map['confidence'] as double,
      stageProbabilities: Map<String, double>.from(
        jsonDecode(map['stage_probabilities'] as String),
      ),
      woundAreaPercent: map['wound_area_percent'] as double,
      woundAreaCm2: map['wound_area_cm2'] as double?,
      tissueMaskPath: map['tissue_mask_path'] as String?,
      tissuePercentages: map['tissue_percentages'] == null
          ? null
          : Map<String, double>.from(
              jsonDecode(map['tissue_percentages'] as String),
            ),
      checklistData: map['checklist_json'] == null
          ? null
          : Map<String, dynamic>.from(
              jsonDecode(map['checklist_json'] as String),
            ),
      triageData: map['triage_json'] == null
          ? null
          : Map<String, dynamic>.from(
              jsonDecode(map['triage_json'] as String),
            ),
      capturedAt: DateTime.parse(map['captured_at'] as String),
      analyzedAt: DateTime.parse(map['analyzed_at'] as String),
    );
  }

  // Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'location': location,
      'notes': notes,
      'captured_by': capturedBy,
      'image_path': imagePath,
      'mask_path': maskPath,
      'predicted_stage': predictedStage,
      'confidence': confidence,
      'stage_probabilities': jsonEncode(stageProbabilities),
      'wound_area_percent': woundAreaPercent,
      'wound_area_cm2': woundAreaCm2,
      'tissue_mask_path': tissueMaskPath,
      'tissue_percentages': tissuePercentages == null
          ? null
          : jsonEncode(tissuePercentages),
      'checklist_json': checklistData == null ? null : jsonEncode(checklistData),
      'triage_json': triageData == null ? null : jsonEncode(triageData),
      'captured_at': capturedAt.toIso8601String(),
      'analyzed_at': analyzedAt.toIso8601String(),
    };
  }

  // Get stage name
  String get stageName => 'Stage $predictedStage';

  // Get formatted confidence
  String get formattedConfidence => '${(confidence * 100).toStringAsFixed(1)}%';

  // Get confidence label
  String get confidenceLabel {
    if (confidence >= 0.8) return 'High';
    if (confidence >= 0.6) return 'Medium';
    return 'Low';
  }

  // Get formatted wound area
  String get formattedWoundArea => '${woundAreaPercent.toStringAsFixed(1)}%';

  @override
  String toString() {
    return 'WoundRecord(id: $id, patientId: $patientId, location: $location, stage: $predictedStage)';
  }

  WoundRecord copyWith({
    String? tissueMaskPath,
    Map<String, double>? tissuePercentages,
    Map<String, dynamic>? checklistData,
    Map<String, dynamic>? triageData,
  }) {
    return WoundRecord(
      id: id,
      patientId: patientId,
      location: location,
      notes: notes,
      capturedBy: capturedBy,
      imagePath: imagePath,
      maskPath: maskPath,
      predictedStage: predictedStage,
      confidence: confidence,
      stageProbabilities: stageProbabilities,
      woundAreaPercent: woundAreaPercent,
      woundAreaCm2: woundAreaCm2,
      tissueMaskPath: tissueMaskPath ?? this.tissueMaskPath,
      tissuePercentages: tissuePercentages ?? this.tissuePercentages,
      checklistData: checklistData ?? this.checklistData,
      triageData: triageData ?? this.triageData,
      capturedAt: capturedAt,
      analyzedAt: analyzedAt,
    );
  }
}
