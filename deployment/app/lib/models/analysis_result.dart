import 'dart:typed_data';

class AnalysisResult {
  final int predictedStage;           // 1-4
  final double confidence;            // 0-1
  final Map<String, double> stageProbabilities;
  final Uint8List? segmentationMask;  // Raw mask data
  final double woundAreaPercent;      // Percentage of image that is wound
  final int woundPixels;              // Number of wound pixels
  final int totalPixels;              // Total image pixels
  final Duration inferenceTime;       // Time taken for inference
  final double? ensembleAgreement;

  AnalysisResult({
    required this.predictedStage,
    required this.confidence,
    required this.stageProbabilities,
    this.segmentationMask,
    required this.woundAreaPercent,
    required this.woundPixels,
    required this.totalPixels,
    required this.inferenceTime,
    this.ensembleAgreement,
  });

  // Get stage name
  String get stageName => 'Stage $predictedStage';

  // Get formatted confidence
  String get formattedConfidence => '${(confidence * 100).toStringAsFixed(1)}%';

  // Get formatted wound area
  String get formattedWoundArea => '${woundAreaPercent.toStringAsFixed(1)}%';

  // Get stage description
  String get stageDescription {
    switch (predictedStage) {
      case 1:
        return 'Non-blanchable erythema of intact skin. Darkly pigmented skin may not have visible blanching.';
      case 2:
        return 'Partial-thickness loss of skin with exposed dermis. Wound bed is viable, pink or red, moist.';
      case 3:
        return 'Full-thickness loss of skin. Adipose (fat) is visible. Granulation tissue and epibole often present.';
      case 4:
        return 'Full-thickness skin and tissue loss. Exposed or directly palpable fascia, muscle, tendon, ligament, cartilage or bone.';
      default:
        return 'Unknown stage';
    }
  }

  // Get severity level (for UI coloring)
  String get severityLevel {
    switch (predictedStage) {
      case 1:
        return 'mild';
      case 2:
        return 'moderate';
      case 3:
        return 'severe';
      case 4:
        return 'critical';
      default:
        return 'unknown';
    }
  }

  // Check if wound is healing (comparing with previous record)
  static String compareWoundArea(double current, double previous) {
    final diff = current - previous;
    if (diff < -5) {
      return 'Significantly Improved';
    } else if (diff < -1) {
      return 'Improving';
    } else if (diff < 1) {
      return 'Stable';
    } else if (diff < 5) {
      return 'Worsening';
    } else {
      return 'Significantly Worse';
    }
  }

  @override
  String toString() {
    return 'AnalysisResult(stage: $predictedStage, confidence: $formattedConfidence, area: $formattedWoundArea)';
  }
}
