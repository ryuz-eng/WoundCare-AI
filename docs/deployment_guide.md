# WoundCare AI - Deployment Guide

Complete guide for deploying the WoundCare AI system in different environments.

## 📋 Table of Contents

1. [Deployment Options](#deployment-options)
2. [Local Inference](#local-inference)
3. [API Deployment (Hugging Face Spaces)](#api-deployment-hugging-face-spaces)
4. [Mobile App Deployment](#mobile-app-deployment)
5. [Production Deployment (AWS)](#production-deployment-aws)
6. [On-Device Deployment (TFLite)](#on-device-deployment-tflite)
7. [Monitoring & Logging](#monitoring--logging)
8. [Security Considerations](#security-considerations)

---

## Deployment Options

| Option | Use Case | Complexity | Cost |
|--------|----------|------------|------|
| **Local Inference** | Development, testing | Low | Free |
| **HF Spaces** | Demo, prototyping | Low | Free tier available |
| **Mobile (TFLite)** | Offline, privacy-focused | Medium | Free (user's device) |
| **AWS/GCP** | Production, scalable | High | Pay-per-use |

---

## Local Inference

Run inference on your local machine.

### 1. Setup

```bash
# Clone repo
git clone https://github.com/YOUR_USERNAME/WoundCare-AI.git
cd WoundCare-AI

# Install dependencies
pip install -r requirements.txt
```

### 2. Run Inference

**Single image:**

```bash
python inference/infer_unseen.py \
    --input path/to/wound.jpg \
    --out results/
```

**Batch processing (folder):**

```bash
python inference/infer_unseen.py \
    --input path/to/wound/folder/ \
    --out results/
```

### 3. Output

```
results/
├── masks/              # Binary segmentation masks
├── overlays/           # Mask overlays on original images
├── roi/                # Cropped ROI regions
├── unseen_results.csv  # Tabular results
└── unseen_results.json # Detailed JSON output
```

**Example JSON output:**

```json
{
  "file": "wound_001.jpg",
  "pred_stage": "Stage_2",
  "confidence": 0.87,
  "area_ratio": 0.124,
  "roi_bbox": {"x1": 234, "y1": 156, "x2": 567, "y2": 489},
  "review_needed": false,
  "review_reasons": [],
  "top2": [
    {"stage": "Stage_2", "prob": 0.87},
    {"stage": "Stage_3", "prob": 0.09}
  ]
}
```

### 4. Advanced Options

```bash
python inference/infer_unseen.py \
    --input wound.jpg \
    --conf_thresh 0.70 \          # Review if confidence < 0.70
    --min_area_ratio 0.005 \      # Review if wound too small
    --pad 0.30 \                  # ROI padding (default 0.25)
    --mask_thresh 0.5 \           # Segmentation threshold
    --no_exif                     # Disable EXIF rotation
```

---

## API Deployment (Hugging Face Spaces)

Deploy as a web API using Hugging Face Spaces.

### Current Deployment

**✅ Already deployed at:**
https://YOUR_USERNAME-woundcare-api.hf.space

### Testing the API

**Health check:**

```bash
curl https://YOUR_USERNAME-woundcare-api.hf.space/health
```

**Analyze image:**

```bash
curl -X POST "https://YOUR_USERNAME-woundcare-api.hf.space/analyze" \
  -F "file=@wound.jpg" \
  -o result.json
```

**Python client:**

```python
import requests

url = "https://YOUR_USERNAME-woundcare-api.hf.space/analyze"
files = {"file": open("wound.jpg", "rb")}
response = requests.post(url, files=files)

result = response.json()
print(f"Stage: {result['predicted_stage']}")
print(f"Confidence: {result['confidence']:.2%}")
```

### API Response Format

```json
{
  "success": true,
  "predicted_stage": "Stage_2",
  "stage_name": "Stage 2",
  "confidence": 0.87,
  "stage_probabilities": {
    "Stage_1": 0.05,
    "Stage_2": 0.87,
    "Stage_3": 0.06,
    "Stage_4": 0.02
  },
  "wound_area_percent": 12.4,
  "wound_pixels": 45678,
  "total_pixels": 368640,
  "inference_time_ms": 234.5,
  "segmentation_mask_base64": "iVBORw0KGgoAAAANS...",
  "message": "Analysis completed successfully"
}
```

### Updating the Deployment

1. Make changes to your HF Space repository
2. Commit and push
3. Space automatically rebuilds

**Or clone and update:**

```bash
git clone https://huggingface.co/spaces/YOUR_USERNAME/woundcare-api
cd woundcare-api

# Make changes to app.py or requirements.txt
git add .
git commit -m "Update API"
git push
```

---

## Mobile App Deployment

Deploy the Flutter tablet application.

### Prerequisites

- Flutter SDK 3.0+
- Android Studio / Xcode
- Physical device or emulator

### 1. Setup

```bash
cd mobile
flutter pub get
```

### 2. Configure API Endpoint

Edit `lib/config/api_config.dart`:

```dart
class ApiConfig {
  // Production (HF Space)
  static const String baseUrl = 'https://YOUR_USERNAME-woundcare-api.hf.space';
  
  // Development (local server)
  // static const String baseUrl = 'http://10.0.2.2:8000';  // Android emulator
  // static const String baseUrl = 'http://localhost:8000';   // iOS simulator
}
```

### 3. Run in Development

```bash
# Check connected devices
flutter devices

# Run on device
flutter run

# Run on specific device
flutter run -d <device_id>
```

### 4. Build Release APK (Android)

```bash
flutter build apk --release
```

**Output:** `build/app/outputs/flutter-apk/app-release.apk`

**Install on device:**

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 5. Build iOS (macOS only)

```bash
flutter build ios --release

# Then use Xcode to archive and distribute
open ios/Runner.xcworkspace
```

### 6. Testing

**Manual testing checklist:**

- [ ] Camera capture works
- [ ] Image upload to API succeeds
- [ ] Results display correctly
- [ ] Segmentation overlay renders
- [ ] Confidence indicator accurate
- [ ] Review flag shows when needed
- [ ] Error handling (no internet, API down)
- [ ] Performance acceptable (<3s for analysis)

---

## Production Deployment (AWS)

Deploy a scalable production system using AWS.

### Architecture

```
User → CloudFront (CDN) → ALB → ECS (FastAPI) → S3 (Storage)
                                    ↓
                              ECR (Docker Image)
                              RDS (PostgreSQL - optional)
```

### 1. Containerize Backend

**Create `Dockerfile`:**

```dockerfile
FROM python:3.10-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy code
COPY models/ models/
COPY inference/ inference/
COPY app.py .

# Download models from HF on build (optional - can do at runtime)
RUN python -c "from models.load_checkpoint import download_checkpoint; \
               download_checkpoint('seg_best.pth'); \
               download_checkpoint('cls_pred_ft_best.pth')"

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Build and test:**

```bash
docker build -t woundcare-api .
docker run -p 8000:8000 woundcare-api
```

### 2. Push to AWS ECR

```bash
# Authenticate
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Create repository
aws ecr create-repository --repository-name woundcare-api

# Tag image
docker tag woundcare-api:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/woundcare-api:latest

# Push
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/woundcare-api:latest
```

### 3. Deploy to ECS

**Create ECS cluster:**

```bash
aws ecs create-cluster --cluster-name woundcare-cluster
```

**Create task definition:** `task-definition.json`

```json
{
  "family": "woundcare-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "2048",
  "memory": "4096",
  "containerDefinitions": [
    {
      "name": "woundcare-api",
      "image": "<account-id>.dkr.ecr.us-east-1.amazonaws.com/woundcare-api:latest",
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "HF_HOME",
          "value": "/tmp/.cache/huggingface"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/woundcare-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

**Register task:**

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

**Create service:**

```bash
aws ecs create-service \
  --cluster woundcare-cluster \
  --service-name woundcare-api-service \
  --task-definition woundcare-api \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

### 4. Setup Load Balancer

1. Create Application Load Balancer (ALB)
2. Create target group (port 8000)
3. Register ECS service with target group
4. Configure health check: `/health`

### 5. Setup CloudFront (Optional CDN)

1. Create CloudFront distribution
2. Origin: ALB DNS name
3. Cache policy: Disable caching for `/analyze`
4. Enable HTTPS

### 6. Monitoring with CloudWatch

**View logs:**

```bash
aws logs tail /ecs/woundcare-api --follow
```

**Create alarms:**

- High error rate (>5%)
- High latency (>2s p95)
- Low healthy hosts (<1)

---

## On-Device Deployment (TFLite)

Run models directly on mobile devices (offline).

### 1. Convert Models to TFLite

**Create `scripts/convert_to_tflite.py`:**

```python
import torch
import onnx
from onnx_tf.backend import prepare
import tensorflow as tf
import segmentation_models_pytorch as smp
import timm

def convert_pytorch_to_tflite(pytorch_checkpoint, output_path, model_type='seg'):
    """Convert PyTorch model to TFLite"""
    
    # Load PyTorch model
    if model_type == 'seg':
        model = smp.Unet(encoder_name="resnet34", encoder_weights=None, in_channels=3, classes=1)
        dummy_input = torch.randn(1, 3, 320, 320)
    else:  # classification
        model = timm.create_model("convnext_tiny", pretrained=False, num_classes=4)
        dummy_input = torch.randn(1, 3, 384, 384)
    
    ckpt = torch.load(pytorch_checkpoint, map_location='cpu')
    model.load_state_dict(ckpt['state_dict'])
    model.eval()
    
    # Export to ONNX
    onnx_path = output_path.replace('.tflite', '.onnx')
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        input_names=['input'],
        output_names=['output'],
        opset_version=12
    )
    
    # Convert ONNX to TensorFlow
    onnx_model = onnx.load(onnx_path)
    tf_rep = prepare(onnx_model)
    tf_model_path = output_path.replace('.tflite', '_tf')
    tf_rep.export_graph(tf_model_path)
    
    # Convert TF to TFLite
    converter = tf.lite.TFLiteConverter.from_saved_model(tf_model_path)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    
    with open(output_path, 'wb') as f:
        f.write(tflite_model)
    
    print(f"✅ Converted to {output_path}")
    print(f"   Size: {len(tflite_model) / 1024 / 1024:.1f} MB")

# Convert both models
convert_pytorch_to_tflite(
    'runs/seg/seg_best.pth',
    'mobile/assets/models/wound_segmentation.tflite',
    model_type='seg'
)

convert_pytorch_to_tflite(
    'runs/cls_pred_ft/cls_pred_ft_best.pth',
    'mobile/assets/models/wound_classifier.tflite',
    model_type='cls'
)
```

### 2. Integrate in Flutter

**Add dependency to `pubspec.yaml`:**

```yaml
dependencies:
  tflite_flutter: ^0.10.0
```

**Load and run model:**

```dart
import 'package:tflite_flutter/tflite_flutter.dart';

class WoundAnalyzer {
  late Interpreter segInterpreter;
  late Interpreter clsInterpreter;
  
  Future<void> loadModels() async {
    segInterpreter = await Interpreter.fromAsset('models/wound_segmentation.tflite');
    clsInterpreter = await Interpreter.fromAsset('models/wound_classifier.tflite');
  }
  
  Future<Map<String, dynamic>> analyze(Image image) async {
    // Preprocess image
    var input = preprocessImage(image, 320, 320);
    
    // Run segmentation
    var segOutput = List.filled(1 * 320 * 320 * 1, 0.0).reshape([1, 320, 320, 1]);
    segInterpreter.run(input, segOutput);
    
    // Extract ROI and run classification
    var roi = extractROI(image, segOutput);
    var clsInput = preprocessImage(roi, 384, 384);
    var clsOutput = List.filled(1 * 4, 0.0).reshape([1, 4]);
    clsInterpreter.run(clsInput, clsOutput);
    
    return {
      'stage': getStageFromOutput(clsOutput),
      'confidence': getConfidence(clsOutput),
      'mask': segOutput,
    };
  }
}
```

### 3. Performance Optimization

**Quantization (reduces size, faster inference):**

```python
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]  # FP16 quantization
```

**Delegate to GPU (faster on supported devices):**

```dart
var options = InterpreterOptions()..useNnApiForAndroid = true;
interpreter = await Interpreter.fromAsset('model.tflite', options: options);
```

---

## Monitoring & Logging

### Application Logging

**Add to backend:**

```python
import logging
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('woundcare.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

@app.post("/analyze")
async def analyze(file: UploadFile):
    start_time = datetime.now()
    
    try:
        # ... inference code ...
        
        logger.info(f"Analysis completed: stage={result['predicted_stage']}, "
                   f"confidence={result['confidence']:.2f}, "
                   f"time={(datetime.now() - start_time).total_seconds():.2f}s")
        
        return result
    except Exception as e:
        logger.error(f"Analysis failed: {str(e)}", exc_info=True)
        raise
```

### Metrics Collection

**Track key metrics:**

- Requests per minute
- Average inference time
- Error rate
- Confidence distribution
- Review flag rate

**Example with Prometheus:**

```python
from prometheus_client import Counter, Histogram, generate_latest

REQUEST_COUNT = Counter('woundcare_requests_total', 'Total requests')
INFERENCE_TIME = Histogram('woundcare_inference_seconds', 'Inference time')
CONFIDENCE = Histogram('woundcare_confidence', 'Prediction confidence')

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type="text/plain")
```

---

## Security Considerations

### 1. Data Privacy

**HIPAA Compliance (if handling real patient data):**

- Use encrypted connections (HTTPS)
- Encrypt data at rest
- Implement access controls
- Maintain audit logs
- Sign Business Associate Agreement (BAA)

**De-identification:**

- Remove EXIF metadata from images
- Don't store patient identifiers
- Use session-based identifiers only

### 2. API Security

**Rate limiting:**

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@app.post("/analyze")
@limiter.limit("10/minute")  # Max 10 requests per minute per IP
async def analyze(request: Request, file: UploadFile):
    # ... inference code ...
```

**Authentication (production):**

```python
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

@app.post("/analyze")
async def analyze(
    file: UploadFile,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    # Verify token
    if not verify_token(credentials.credentials):
        raise HTTPException(status_code=401, detail="Invalid token")
    
    # ... inference code ...
```

### 3. Input Validation

```python
from fastapi import HTTPException

ALLOWED_EXTENSIONS = {'.jpg', '.jpeg', '.png'}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB

@app.post("/analyze")
async def analyze(file: UploadFile):
    # Check file extension
    ext = Path(file.filename).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Invalid file type. Allowed: {ALLOWED_EXTENSIONS}")
    
    # Check file size
    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(400, f"File too large. Max: {MAX_FILE_SIZE/1024/1024}MB")
    
    # ... inference code ...
```

---

## Troubleshooting

### Issue: API Returns 500 Error

**Check logs:**
```bash
docker logs <container_id>
# or
aws logs tail /ecs/woundcare-api
```

**Common causes:**
- Model files not downloaded
- Out of memory
- Missing dependencies

### Issue: Slow Inference

**Solutions:**
1. Use GPU instance (AWS P3/P4)
2. Batch multiple requests
3. Reduce image resolution
4. Use model quantization

### Issue: Mobile App Can't Connect

**Check:**
1. API endpoint URL correct
2. Device has internet
3. API is running (`curl <url>/health`)
4. Firewall allows connection

---

## Cost Estimation

### Hugging Face Spaces

- **Free tier:** CPU Basic (limited)
- **Paid:** ~$0.60/hour for CPU, ~$3/hour for GPU

### AWS (Estimated Monthly)

- **ECS Fargate (2 vCPU, 4GB):** 2 instances × $50 = $100
- **ALB:** $20
- **CloudWatch:** $10
- **Data transfer:** $20
- **Total:** ~$150/month for low-medium traffic

### Scaling

For 1,000 requests/day:
- ~$150/month (AWS)
- ~$0/month (HF Spaces free tier)

For 100,000 requests/day:
- ~$500-1000/month (AWS with autoscaling)
- Consider dedicated GPU instances

---

## Next Steps

1. Test deployment locally
2. Deploy to HF Spaces for demo
3. Conduct user testing with mobile app
4. Plan production deployment if validated
5. Implement monitoring and logging
6. Setup CI/CD pipeline

---

**Questions?** Open an issue on GitHub or contact the project author.
