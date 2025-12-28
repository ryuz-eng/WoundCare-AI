# WoundCare AI: Automated Pressure Injury Staging System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.0+-red.svg)](https://pytorch.org/)

An AI-powered clinical decision support system for automated pressure ulcer staging (NPIAP Stage 1-4) using deep learning-based segmentation and classification.

## Overview

WoundCare AI is a mobile-integrated system that combines:
- **U-Net segmentation** for wound localization
- **ConvNeXt-Tiny classifier** for stage prediction (Stage 1-4)
- **Deployment-aligned training** (ROI_pred strategy)
- **Clinical transparency** (confidence scores, review flags)

**Performance:** 76.7% accuracy (macro-F1 0.768) on held-out test set (n=103)

## Key Features

- Segmentation-guided ROI extraction
- Confidence-based uncertainty quantification
- Mobile deployment (Flutter + FastAPI)
- On-device inference option (TFLite)
- Clinical workflow integration

## Architecture

### Pipeline 2 (Final Selected Model)
```
Input Image → U-Net Segmentation → ROI Extraction (+ padding) 
           → ConvNeXt-Tiny Classifier → Stage Prediction + Confidence
```

**Why Pipeline 2?**
- Trains on deployment-realistic ROI crops (ROI_pred)
- Reduces train-deployment mismatch
- Better calibration than validation-optimized models

## Project Structure
```
WoundCare-AI/
├── models/          # Model architectures
├── train/           # Training scripts
├── inference/       # Inference pipeline
├── deployment/      # Backend API + Mobile app
├── configs/         # Training configurations
└── docs/            # Documentation
```

## Quick Start

### Installation
```bash
git clone https://github.com/yourusername/WoundCare-AI.git
cd WoundCare-AI
pip install -r requirements.txt
```

### Training
```bash
# 1. Train segmentation model
python train/train_seg.py --config configs/seg.yaml

# 2. Train base classifier on ROI_gt
python train/train_cls.py --config configs/cls.yaml

# 3. Fine-tune on ROI_pred (deployment-aligned)
python train/train_cls_finetune.py --config configs/cls_finetune.yaml
```

### Inference
```bash
# Run end-to-end inference
python inference/infer_unseen.py --image path/to/wound.jpg
```

**Output:**
```json
{
  "predicted_stage": "Stage_2",
  "confidence": 0.87,
  "stage_probabilities": {
    "Stage_1": 0.05,
    "Stage_2": 0.87,
    "Stage_3": 0.06,
    "Stage_4": 0.02
  },
  "review_needed": false,
  "wound_area_percent": 12.4
}
```

### Deployment

#### Option 1: FastAPI Backend
```bash
cd deployment/backend
uvicorn app:app --host 0.0.0.0 --port 8000
```

#### Option 2: Mobile App (Flutter)
```bash
cd deployment/mobile
flutter run
```

## 📈 Results

### Performance Comparison

| Pipeline | Architecture | Test Acc | Macro-F1 | Status |
|----------|-------------|----------|----------|--------|
| Pipeline 1 | U-Net + EfficientNet-B5 | Not tested | - | Rejected (deployment gap) |
| **Pipeline 2** | **U-Net + ConvNeXt-Tiny** | **76.7%** | **0.768** | **✅ Final** |
| Pipeline 3 | YOLOv11-seg | - | mAP@0.5: 0.742 | Rejected (inconsistent) |

### Per-Stage Performance

| Stage | F1-Score | Support | Clinical Notes |
|-------|----------|---------|----------------|
| Stage 1 | 0.79 | 16 | Early erythema detection |
| Stage 2 | 0.82 | 33 | **Best performance** |
| Stage 3 | 0.70 | 27 | Most challenging |
| Stage 4 | 0.76 | 27 | Deep tissue loss |

## Technical Highlights

### 1. ROI_pred Training Strategy
Most systems train on ground-truth ROIs but deploy on predicted ROIs. We explicitly fine-tune on ROI_pred crops to reduce this mismatch.

### 2. Confidence Calibration
Returns top-2 probabilities and review flags for uncertain cases (confidence < 60%).

### 3. Clinical Transparency
- Segmentation mask overlay
- Confidence scores
- Top-2 alternatives
- Review needed flag

## Citation

If you use this work, please cite:
```bibtex
@mastersthesis{lee2024woundcare,
  title={WoundCare AI: Mobile-Assisted Pressure Injury Staging Using Segmentation-Guided Classification},
  author={Lee, Ben Wen Hon},
  year={2024},
  school={Singapore Polytechnic},
  type={Final Year Project}
}
```

## 🔗 Related Work

- Chino et al. (2021): 77.9% accuracy on PI staging (DenseNet-121, n=430)
- Anisuzzaman et al. (2022): Systematic review of AI wound assessment

## Limitations

- Small test set (n=103) → wide confidence intervals
- Single-institution data
- No clinical validation with practitioners
- Research prototype (not clinically deployed)

## Future Work

1. **Clinical validation study** (5-7 nurses, 50 cases)
2. **Dataset expansion** (3,000+ images, multi-site)
3. **Confidence calibration** (temperature scaling)
4. **Production deployment** (AWS + Firebase)

## License

MIT License - see [LICENSE](LICENSE) file

## Contributors

- **Ben Lee Wen Hon** - Primary Developer
- **Supervisors:** Chua Kuang Chua, Ang Hui Chen

## Acknowledgments

- National Pressure Injury Advisory Panel (NPIAP) for staging guidelines
- Hugging Face for model hosting infrastructure
- PyTorch and timm communities



**Important:** This is a research prototype for educational purposes. Not intended for clinical use without proper validation and regulatory approval.
