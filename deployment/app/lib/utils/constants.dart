// App Constants

class AppConstants {
  // App Info
  static const String appName = 'WoundCare AI';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'Intelligent Pressure Wound Analysis';
  
  // Model Configuration
  static const String segmentationModelPath = 'assets/models/segmentation_fp32.tflite';
  static const String classificationModelPath = 'assets/models/classification_fp32.tflite';
  static const int segmentationInputSize = 384;
  static const int classificationInputSize = 456;
  
  // ImageNet Normalization
  static const List<double> imagenetMean = [0.485, 0.456, 0.406];
  static const List<double> imagenetStd = [0.229, 0.224, 0.225];

  //static const String baseUrlStable = "https://benhoxton-woundcare-ai.hf.space";
  //static const String baseUrlStaging = "https://benhoxton-woundcare-ai-staging.hf.space";

  static const String baseUrl = "https://benhoxton-woundcare-ai-staging.hf.space";

  
  // Wound Stages
  static const List<String> woundStages = [
    'Stage 1',
    'Stage 2',
    'Stage 3',
    'Stage 4',
  ];
  
  // Wound Locations
  static const List<String> woundLocations = [
    'Sacrum/Coccyx',
    'Heel (Left)',
    'Heel (Right)',
    'Hip (Left)',
    'Hip (Right)',
    'Elbow (Left)',
    'Elbow (Right)',
    'Shoulder (Left)',
    'Shoulder (Right)',
    'Back',
    'Buttock (Left)',
    'Buttock (Right)',
    'Ankle (Left)',
    'Ankle (Right)',
    'Other',
  ];
  
  // Database
  static const String databaseName = 'woundcare.db';
  static const int databaseVersion = 1;
  
  // Date Formats
  static const String dateFormat = 'dd MMM yyyy';
  static const String dateTimeFormat = 'dd MMM yyyy, HH:mm';
  static const String timeFormat = 'HH:mm';
}

// Product Recommendations based on wound stage
class WoundRecommendations {
  // FIXED: Changed return type from Map<...> to List<ProductRecommendation>
  static List<ProductRecommendation> getRecommendations(int stage) {
    return {
      1: [
        ProductRecommendation(
          name: 'Transparent Film Dressing',
          description: 'Protects skin while allowing moisture vapor exchange',
          usage: 'Apply directly over the affected area. Change every 5-7 days or when loose.',
          videoUrl: 'https://www.youtube.com/watch?v=example1',
          imageAsset: 'assets/images/transparent_film.png',
        ),
        ProductRecommendation(
          name: 'Barrier Cream',
          description: 'Protects skin from moisture and friction',
          usage: 'Apply thin layer to clean, dry skin. Reapply after cleaning.',
          videoUrl: 'https://www.youtube.com/watch?v=example2',
          imageAsset: 'assets/images/barrier_cream.png',
        ),
        ProductRecommendation(
          name: 'Pressure Redistribution Cushion',
          description: 'Reduces pressure on bony prominences',
          usage: 'Place under patient to offload pressure from wound area.',
          videoUrl: 'https://www.youtube.com/watch?v=example3',
          imageAsset: 'assets/images/cushion.png',
        ),
      ],
      2: [
        ProductRecommendation(
          name: 'Hydrocolloid Dressing',
          description: 'Maintains moist wound environment and absorbs light exudate',
          usage: 'Clean wound, apply dressing extending 2-3cm beyond wound edges. Change every 3-5 days.',
          videoUrl: 'https://www.youtube.com/watch?v=example4',
          imageAsset: 'assets/images/hydrocolloid.png',
        ),
        ProductRecommendation(
          name: 'Foam Dressing',
          description: 'Absorbs moderate exudate while maintaining moisture balance',
          usage: 'Apply to clean wound. Can be used as primary or secondary dressing.',
          videoUrl: 'https://www.youtube.com/watch?v=example5',
          imageAsset: 'assets/images/foam_dressing.png',
        ),
        ProductRecommendation(
          name: 'Saline Solution',
          description: 'For gentle wound cleansing',
          usage: 'Irrigate wound gently before dressing change. Do not scrub.',
          videoUrl: 'https://www.youtube.com/watch?v=example6',
          imageAsset: 'assets/images/saline.png',
        ),
      ],
      3: [
        ProductRecommendation(
          name: 'Alginate Dressing',
          description: 'Highly absorbent for wounds with heavy exudate',
          usage: 'Fill wound cavity loosely. Cover with secondary dressing. Change daily or when saturated.',
          videoUrl: 'https://www.youtube.com/watch?v=example7',
          imageAsset: 'assets/images/alginate.png',
        ),
        ProductRecommendation(
          name: 'Hydrogel',
          description: 'Provides moisture to dry wounds and promotes autolytic debridement',
          usage: 'Apply to wound bed, cover with secondary dressing. Change every 1-3 days.',
          videoUrl: 'https://www.youtube.com/watch?v=example8',
          imageAsset: 'assets/images/hydrogel.png',
        ),
        ProductRecommendation(
          name: 'Antimicrobial Dressing',
          description: 'Contains silver or other antimicrobial agents to reduce bioburden',
          usage: 'Apply to infected or at-risk wounds. Follow manufacturer guidelines.',
          videoUrl: 'https://www.youtube.com/watch?v=example9',
          imageAsset: 'assets/images/antimicrobial.png',
        ),
      ],
      4: [
        ProductRecommendation(
          name: 'Negative Pressure Wound Therapy (NPWT)',
          description: 'Advanced therapy for complex wounds - requires medical supervision',
          usage: 'Applied by trained healthcare professionals. Continuous or intermittent suction.',
          videoUrl: 'https://www.youtube.com/watch?v=example10',
          imageAsset: 'assets/images/npwt.png',
        ),
        ProductRecommendation(
          name: 'Collagen Dressing',
          description: 'Promotes granulation tissue formation in deep wounds',
          usage: 'Apply to clean wound bed. Cover with appropriate secondary dressing.',
          videoUrl: 'https://www.youtube.com/watch?v=example11',
          imageAsset: 'assets/images/collagen.png',
        ),
        ProductRecommendation(
          name: 'Enzymatic Debriding Agent',
          description: 'Helps remove necrotic tissue - requires medical supervision',
          usage: 'Apply thin layer to necrotic areas only. Cover with moist dressing.',
          videoUrl: 'https://www.youtube.com/watch?v=example12',
          imageAsset: 'assets/images/enzymatic.png',
        ),
      ],
    }[stage] ?? [];
  }
}

class ProductRecommendation {
  final String name;
  final String description;
  final String usage;
  final String videoUrl;
  final String imageAsset;

  ProductRecommendation({
    required this.name,
    required this.description,
    required this.usage,
    required this.videoUrl,
    required this.imageAsset,
  });
}

