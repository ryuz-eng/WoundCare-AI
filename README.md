# WoundCare AI: Automated Pressure Injury Staging System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.0+-red.svg)](https://pytorch.org/)
[![HuggingFace](https://img.shields.io/badge/🤗-Models-yellow.svg)](https://huggingface.co/benhoxton/woundcare-ai)

Deep learning system for automated pressure ulcer staging (NPUAP Stage 1-4) using segmentation-guided classification.

##  Overview

**Final Year Project** - Singapore Polytechnic, School of ECE  
**Student:** Ben Lee Wen Hon  
**Supervisors:** Chua Kuang Chua, Ang Hui Chen

### Performance
- **Test Accuracy:** 76.7% (n=103 held-out images)
- **Macro-F1:** 0.768
- **Architecture:** U-Net segmentation → ConvNeXt-Tiny classification

### Key Features
-  Segmentation-guided ROI extraction
-  Deployment-realistic training (ROI_pred strategy)
-  Confidence-based uncertainty quantification
-  Mobile deployment (Flutter + FastAPI)
-  Clinical transparency (confidence scores, review flags)

---

##  Model Weights

**🤗 Hugging Face Hub:** https://huggingface.co/benhoxton/woundcare-ai

Trained models are hosted on Hugging Face (too large for GitHub):
- `seg_best.pth` (49 MB) - U-Net segmentation, Dice: 0.9003
- `cls_best.pth` (115 MB) - Base classifier, F1: 0.8116  
- `cls_pred_ft_best.pth` (115 MB) - Fine-tuned classifier, F1: 0.8037 

Models are **automatically downloaded** on first run.

---

##  Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/ryuz-eng/WoundCare-AI.git
cd WoundCare-AI

# Install dependencies
pip install -r requirements.txt
```

### Inference

```bash
# Run on a single wound image (models auto-download from HF)
python inference/infer_unseen.py --input path/to/wound.jpg --out results/

# Batch processing (entire folder)
python inference/infer_unseen.py --input path/to/folder/ --out results/
```

**Output:**
```json
{
  "pred_stage": "Stage_2",
  "confidence": 0.87,
  "area_ratio": 0.124,
  "review_needed": false,
  "top2": [
    {"stage": "Stage_2", "prob": 0.87},
    {"stage": "Stage_3", "prob": 0.09}
  ]
}
```

Results saved to:
- `results/masks/` - Binary segmentation masks
- `results/overlays/` - Mask overlays on images
- `results/roi/` - Cropped ROI regions
- `results/unseen_results.csv` - Tabular results
- `results/unseen_results.json` - Detailed JSON

---
##  Try It Now (No Installation Required!)

**Live API Demo:** https://benhoxton-woundcare-ai-staging.hf.space/docs

Want to test the system without installing anything? Use our live API!

### Interactive Web Interface

 **[Open Swagger UI](https://benhoxton-woundcare-ai-staging.hf.space/docs)** 

**Steps:**
1. Click the link above
2. Navigate to `POST /analyze` endpoint
3. Click **"Try it out"**
4. Click **"Choose File"** and upload a wound image
5. Click **"Execute"**
6. View instant AI staging results!

### Command Line (curl)
```bash
curl -X POST "https://benhoxton-woundcare-ai-staging.hf.space/analyze" \
  -H "accept: application/json" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@your_wound_image.jpg"
```

### Python Script
```python
import requests

# Upload image to API
url = "https://benhoxton-woundcare-ai-staging.hf.space/analyze"
files = {"file": open("wound.jpg", "rb")}
response = requests.post(url, files=files)

# Parse results
result = response.json()
print(f"Predicted Stage: {result['predicted_stage']}")
print(f"Confidence: {result['confidence']:.2%}")
print(f"Wound Area: {result['wound_area_percent']:.1f}%")
```

**API Response Example:**
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

---

##  Project Structure

```
WoundCare-AI/
├── models/              # Model architectures + HF loading
│   ├── __init__.py
│   ├── segmentation.py
│   ├── classification.py
│   └── load_checkpoint.py
├── train/               # Training scripts
│   ├── train_seg.py
│   ├── train_cls.py
│   └── train_cls_finetune.py
├── inference/           # Inference pipeline
│   ├── __init__.py
│   └── infer_unseen.py
├── configs/             # Training configurations
│   ├── seg.yaml
│   ├── cls.yaml
│   └── cls_pred_ft.yaml
├── deployment/          # Mobile app
│   └── app/
│       └── lib/         # Flutter application
└── docs/                # Documentation
    ├── training_guide.md
    └── deployment_guide.md
```

---

## Training (Reproduce Results)

### Step 1: Prepare Dataset
```bash
# Organize your data according to docs/training_guide.md
# Create train/val splits as CSV files
```

### Step 2: Train Segmentation
```bash
python train/train_seg.py --config configs/seg.yaml
```

**Expected:** Validation Dice ~0.90

### Step 3: Train Classifier
```bash
# Base classifier (ROI_gt)
python train/train_cls.py --config configs/cls.yaml

# Fine-tune on ROI_pred (deployment-aligned)
python train/train_cls_finetune.py --config configs/cls_pred_ft.yaml
```

**Expected:** Validation macro-F1 ~0.80

### Step 4: Upload to Hugging Face
```bash
# Upload trained models to your HF account
# See docs/training_guide.md for details
```

**Full training guide:** See `docs/training_guide.md`

---

## Deployment

### Option 1: Local Inference

Already covered in Quick Start.

### Option 2: Web API

** Live API:** https://benhoxton-woundcare-ai-staging.hf.space

** Interactive Docs:** https://benhoxton-woundcare-ai-staging.hf.space/docs

**Test the API:**
```bash
# Health check
curl https://benhoxton-woundcare-ai-staging.hf.space/health

# Analyze wound image
curl -X POST "https://benhoxton-woundcare-ai-staging.hf.space/analyze" \
  -F "file=@wound.jpg" \
  -o result.json
```

**Python client:**
```python
import requests

url = "https://benhoxton-woundcare-ai-staging.hf.space/analyze"
files = {"file": open("wound.jpg", "rb")}
response = requests.post(url, files=files)

result = response.json()
print(f"Stage: {result['predicted_stage']}")
print(f"Confidence: {result['confidence']:.2%}")
```

**Try it in browser:** Visit the [Swagger UI](https://benhoxton-woundcare-ai-staging.hf.space/docs) to test the API interactively.

### Option 3: Mobile App (Flutter)
```bash
cd deployment/app
flutter pub get
flutter run
```

**Configure API endpoint:** Edit `lib/config/api_config.dart` to point to:
```dart
static const String baseUrl = 'https://benhoxton-woundcare-ai-staging.hf.space';
```

**Full deployment guide:** See `docs/deployment_guide.md`

---

##  Results

### Pipeline Comparison

| Pipeline | Architecture | Test Acc | Macro-F1 | Status |
|----------|-------------|----------|----------|--------|
| Pipeline 1 | U-Net + EfficientNet-B5 | - | - |  Deployment gap |
| **Pipeline 2** | **U-Net + ConvNeXt** | **76.7%** | **0.768** |  **Selected** |
| Pipeline 3 | YOLOv11-seg | - | 0.742* |  Inconsistent |

*mAP@0.5, not directly comparable

### Per-Stage Performance (n=103 test images)

| Stage | Precision | Recall | F1 | Support | Clinical Notes |
|-------|-----------|--------|-----|---------|----------------|
| Stage 1 | 0.81 | 0.77 | **0.79** | 16 | Early erythema detection |
| Stage 2 | 0.85 | 0.79 | **0.82** | 33 | **Best performance** - clear visual markers |
| Stage 3 | 0.68 | 0.74 | **0.70** | 27 | **Most challenging** - depth ambiguity |
| Stage 4 | 0.78 | 0.74 | **0.76** | 27 | Deep tissue loss more distinctive |

### Key Observations

1. **Stage 2 Excellence (F1=0.82):** Clear blisters and tissue breakdown are easily identifiable
2. **Stage 3 Challenge (F1=0.70):** Overlaps visually with Stage 2/4 depending on slough coverage and angle
3. **No Extreme Errors:** Zero Stage 1↔4 misclassifications, indicating learned clinical hierarchies
4. **Adjacent-Stage Errors:** 89% of errors occur between adjacent stages (clinically expected)

---

##  Technical Highlights

### 1. ROI_pred Training Strategy

Unlike typical approaches that train on ground-truth ROIs but deploy on predicted ROIs, Pipeline 2:
- Trains base classifier on **ROI_gt** (clean crops from GT masks)
- Fine-tunes on **ROI_pred** (realistic crops from predicted masks)
- Reduces validation-deployment gap by 8-12% in informal testing

### 2. Confidence Calibration

Returns structured uncertainty information:
```json
{
  "confidence": 0.87,
  "top2": [{"stage": "Stage_2", "prob": 0.87}, {"stage": "Stage_3", "prob": 0.09}],
  "review_needed": false
}
```

**Review flags trigger when:**
- Confidence < 60%
- Wound area < 0.2% of image
- Segmentation fails

### 3. Clinical Transparency

- **Segmentation overlay** - Shows which region was analyzed
- **Confidence scores** - Enables appropriate trust calibration
- **Top-2 alternatives** - Highlights uncertainty between adjacent stages
- **Review flags** - Prompts manual verification for borderline cases

---

##  Important Disclaimers

### NOT for Clinical Use

This is a **research prototype** for educational purposes.

** Not approved for clinical deployment**
- No FDA/CE approval
- No clinical validation with practitioners
- No IRB approval for patient use

**Clinical deployment requires:**
- Institutional review board approval
- Multi-site clinical validation study
- Regulatory compliance
- Professional medical supervision

**Use at your own risk.** Always consult qualified healthcare professionals for wound assessment.

---

##  Documentation

- **Training Guide:** `docs/training_guide.md` - Complete training instructions
- **Deployment Guide:** `docs/deployment_guide.md` - Deployment options and setup
- **Research Paper:** [Link to FYP report when available]

---

##  Links

| Component | Link | Description |
|-----------|------|-------------|
| **Model Weights** | [🤗 Hub](https://huggingface.co/benhoxton/woundcare-ai) | Trained PyTorch models |
| **API Demo** | [🤗 Space](https://benhoxton-woundcare-ai-staging.hf.space) | Live inference API |
| **API Docs** | [Swagger](https://benhoxton-woundcare-ai-staging.hf.space/docs) | Interactive API documentation |
| **GitHub Repo** | [Code](https://github.com/ryuz-eng/WoundCare-AI) | Training + Inference code |


##  System Requirements

### Training
- **GPU:** NVIDIA GPU with 8GB+ VRAM
- **RAM:** 16GB+ (32GB recommended)
- **Storage:** 50GB free space
- **Time:** ~6 hours on RTX 3090

### Inference
- **CPU:** Any modern CPU
- **RAM:** 4GB+
- **GPU:** Optional (3x faster with GPU)
- **Inference time:** ~300ms per image (CPU), ~75ms (GPU)

---

##  Known Limitations

1. **Small test set (n=103)** → Wide confidence intervals (±6.5% at 95% CI)
2. **Single-institution data** → May not generalize to other clinical settings
3. **No clinical validation** → Performance vs human raters unknown
4. **Photo-based constraints** → Depth assessment limited without palpation
5. **Class imbalance** → Stage 2 over-represented (39.5% vs Stage 1 15.1%)

See full limitations in the research paper.

---

##  Future Work

1. **Clinical validation study** - 5-7 nurses, 50 matched cases
2. **Dataset expansion** - 3,000+ images, multi-site, diverse skin tones
3. **Confidence calibration** - Temperature scaling for better uncertainty
4. **Production deployment** - AWS + Firebase with audit logging
5. **Wound tracking** - Temporal analysis for healing progression

---

##  License

MIT License - see [LICENSE](LICENSE) file

Copyright (c) 2024 Ben Lee Wen Hon

---

## Contributors

- **Ben Lee Wen Hon** - Primary Developer
- **Supervisors:** Chua Kuang Chua, Ang Hui Chen

** Medical Disclaimer!:** This software is provided "as-is" without warranty of any kind. Not intended for clinical decision-making. For wound assessment, consult qualified healthcare professionals.
