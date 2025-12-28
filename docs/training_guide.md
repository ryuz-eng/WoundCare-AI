# WoundCare AI - Training Guide

Complete guide for training the pressure injury staging models from scratch.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Dataset Preparation](#dataset-preparation)
3. [Environment Setup](#environment-setup)
4. [Training Pipeline 2 (Recommended)](#training-pipeline-2-recommended)
5. [Hyperparameter Tuning](#hyperparameter-tuning)
6. [Monitoring Training](#monitoring-training)
7. [Model Evaluation](#model-evaluation)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Hardware Requirements

**Minimum:**
- GPU: NVIDIA GPU with 8GB VRAM (GTX 1070 or better)
- RAM: 16GB
- Storage: 50GB free space

**Recommended:**
- GPU: NVIDIA RTX 3090 (24GB VRAM) or better
- RAM: 32GB+
- Storage: 100GB+ SSD

### Software Requirements

- Python 3.8+
- CUDA 11.8+ (for GPU training)
- Git
- (Optional) TensorBoard for monitoring

### Expected Training Time

On NVIDIA RTX 3090:
- Segmentation training: ~3 hours (100 epochs)
- Base classifier: ~2 hours (120 epochs)
- Fine-tuning: ~45 minutes (30 epochs)

**Total:** ~6 hours for complete Pipeline 2

---

## Dataset Preparation

### 1. Dataset Structure

Organize your data as follows:

```
data/
├── raw/
│   ├── images/              # Original wound photos
│   │   ├── Stage_1/
│   │   ├── Stage_2/
│   │   ├── Stage_3/
│   │   └── Stage_4/
│   └── masks/               # Binary segmentation masks
│       ├── Stage_1/
│       ├── Stage_2/
│       ├── Stage_3/
│       └── Stage_4/
└── processed/
    ├── images/              # Processed images
    ├── masks/               # Processed masks
    ├── roi_gt/              # ROI crops from ground-truth masks
    │   └── images/
    └── roi_pred/            # ROI crops from predicted masks
        └── images/
```

### 2. Image Requirements

**Format:** `.jpg`, `.jpeg`, or `.png`

**Recommendations:**
- Resolution: 1024×1024 to 2048×2048 (will be resized during training)
- Good lighting (avoid heavy shadows)
- Perpendicular camera angle
- Include peri-wound skin (5-10cm margin)
- Remove patient identifiers (EXIF data, faces, etc.)

### 3. Mask Annotation

Use [CVAT](https://cvat.org) or similar tools:

**Guidelines:**
1. Include all visibly damaged tissue
2. Exclude intact peri-wound skin
3. Exclude dressings, bandages, medical equipment
4. For Stage 1: Include only non-blanchable erythema
5. For Stage 2+: Follow visible tissue loss edge

**Quality Control:**
- Have 2 annotators per image
- Resolve discrepancies through discussion
- Re-annotate images with <80% agreement

### 4. Create Train/Val Splits

**Recommended splits:**
- Segmentation: 70% train / 30% val
- Classification: 70% train / 30% val
- Hold out 10-15% for final test set

**Create split CSVs:**

```python
import pandas as pd
from pathlib import Path
from sklearn.model_selection import train_test_split

# Segmentation splits
images = list(Path("data/raw/images").rglob("*.jpg"))
train_imgs, val_imgs = train_test_split(images, test_size=0.3, random_state=42)

# Create CSV
pd.DataFrame({"image": [str(p) for p in train_imgs]}).to_csv("data/splits/seg_train.csv", index=False)
pd.DataFrame({"image": [str(p) for p in val_imgs]}).to_csv("data/splits/seg_val.csv", index=False)

# Classification splits (include stage labels)
data = []
for stage_dir in Path("data/processed/roi_gt/images").iterdir():
    stage = stage_dir.name  # e.g., "Stage_1"
    for img in stage_dir.glob("*.jpg"):
        data.append({"image": str(img), "stage": stage})

df = pd.DataFrame(data)
train_df, val_df = train_test_split(df, test_size=0.3, stratify=df["stage"], random_state=42)

train_df.to_csv("data/splits/cls_train.csv", index=False)
val_df.to_csv("data/splits/cls_val.csv", index=False)
```

---

## Environment Setup

### 1. Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/WoundCare-AI.git
cd WoundCare-AI
```

### 2. Create Virtual Environment

```bash
# Using venv
python -m venv venv
source venv/bin/activate  # Linux/Mac
# or
venv\Scripts\activate  # Windows

# Using conda
conda create -n woundcare python=3.10
conda activate woundcare
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Verify GPU

```bash
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU: {torch.cuda.get_device_name(0)}')"
```

Expected output:
```
CUDA available: True
GPU: NVIDIA GeForce RTX 3090
```

---

## Training Pipeline 2 (Recommended)

Pipeline 2 is the deployment-ready approach that trains on realistic ROI crops.

### Step 1: Train Segmentation Model

**Purpose:** Localize wound regions for ROI extraction

**Config:** `configs/seg.yaml`

```yaml
seed: 42

images_dir: data/processed/images
masks_dir: data/processed/masks
train_csv: data/splits/seg_train.csv
val_csv: data/splits/seg_val.csv

img_size: 320
batch_size: 8
epochs: 100
lr: 0.0003

encoder: resnet34
checkpoint_path: runs/seg/seg_best.pth
```

**Train:**

```bash
python train/train_seg.py --config configs/seg.yaml
```

**Expected Output:**
```
Epoch 1: train_loss=0.3421 val_dice=0.7234 lr=3.00e-04
Epoch 2: train_loss=0.2156 val_dice=0.8012 lr=3.00e-04
...
Epoch 73: train_loss=0.0523 val_dice=0.9003 lr=1.50e-05
Saved best seg checkpoint.
```

**Best validation Dice:** ~0.90

**Output:** `runs/seg/seg_best.pth`

---

### Step 2: Generate ROI Crops

After segmentation training, generate ROI crops from both ground-truth and predicted masks.

**Create script:** `scripts/generate_rois.py`

```python
import os
import cv2
import torch
import numpy as np
from pathlib import Path
from tqdm import tqdm
import segmentation_models_pytorch as smp

def keep_largest_component(mask):
    num, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    if num <= 1:
        return mask
    areas = stats[1:, cv2.CC_STAT_AREA]
    largest = 1 + int(np.argmax(areas))
    return (labels == largest).astype(np.uint8)

def bbox_from_mask(mask):
    ys, xs = np.where(mask > 0)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())

def expand_bbox(bbox, W, H, pad_ratio=0.25):
    x1, y1, x2, y2 = bbox
    bw = x2 - x1 + 1
    bh = y2 - y1 + 1
    pad_w = int(bw * pad_ratio)
    pad_h = int(bh * pad_ratio)
    x1 = max(0, x1 - pad_w)
    y1 = max(0, y1 - pad_h)
    x2 = min(W - 1, x2 + pad_w)
    y2 = min(H - 1, y2 + pad_h)
    return x1, y1, x2, y2

def generate_rois(seg_checkpoint, images_dir, masks_dir, output_dir, use_pred=False):
    """
    Generate ROI crops from masks
    
    Args:
        seg_checkpoint: Path to trained segmentation model
        images_dir: Directory containing images
        masks_dir: Directory containing ground-truth masks
        output_dir: Where to save ROI crops
        use_pred: If True, use predicted masks; if False, use ground-truth
    """
    device = "cuda" if torch.cuda.is_available() else "cpu"
    
    # Load segmentation model if using predictions
    if use_pred:
        ckpt = torch.load(seg_checkpoint, map_location=device)
        model = smp.Unet(
            encoder_name=ckpt["cfg"]["encoder"],
            encoder_weights=None,
            in_channels=3,
            classes=1
        )
        model.load_state_dict(ckpt["state_dict"])
        model.to(device).eval()
    
    # Process each image
    image_paths = list(Path(images_dir).rglob("*.jpg"))
    
    for img_path in tqdm(image_paths, desc="Generating ROIs"):
        # Read image
        img = cv2.imread(str(img_path))
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        H, W = img.shape[:2]
        
        # Get mask
        if use_pred:
            # Predict mask
            img_rs = cv2.resize(img, (320, 320))
            x = torch.from_numpy(img_rs).permute(2,0,1).float().unsqueeze(0) / 255.0
            x = x.to(device)
            
            with torch.no_grad():
                logits = model(x)
                prob = torch.sigmoid(logits)[0,0].cpu().numpy()
            
            prob = cv2.resize(prob, (W, H))
            mask = (prob > 0.5).astype(np.uint8)
        else:
            # Use ground-truth mask
            mask_path = str(img_path).replace("images", "masks")
            mask = cv2.imread(mask_path, cv2.IMREAD_GRAYSCALE)
            mask = (mask > 127).astype(np.uint8)
        
        # Clean mask
        mask = keep_largest_component(mask)
        
        # Get ROI
        bbox = bbox_from_mask(mask)
        if bbox is None:
            continue
        
        bbox = expand_bbox(bbox, W, H, pad_ratio=0.25)
        x1, y1, x2, y2 = bbox
        roi = img[y1:y2+1, x1:x2+1]
        
        # Save ROI (preserve directory structure)
        rel_path = img_path.relative_to(images_dir)
        out_path = Path(output_dir) / rel_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        
        cv2.imwrite(str(out_path), cv2.cvtColor(roi, cv2.COLOR_RGB2BGR))

# Generate both ROI_gt and ROI_pred
print("Generating ROI_gt (from ground-truth masks)...")
generate_rois(
    seg_checkpoint="runs/seg/seg_best.pth",
    images_dir="data/processed/images",
    masks_dir="data/processed/masks",
    output_dir="data/processed/roi_gt/images",
    use_pred=False
)

print("Generating ROI_pred (from predicted masks)...")
generate_rois(
    seg_checkpoint="runs/seg/seg_best.pth",
    images_dir="data/processed/images",
    masks_dir="data/processed/masks",
    output_dir="data/processed/roi_pred/images",
    use_pred=True
)

print("Done!")
```

**Run:**

```bash
python scripts/generate_rois.py
```

---

### Step 3: Train Base Classifier (ROI_gt)

**Purpose:** Learn strong staging features from clean ROI crops

**Config:** `configs/cls.yaml`

```yaml
seed: 42

images_dir: data/processed/roi_gt/images
train_csv: data/splits/cls_train.csv
val_csv: data/splits/cls_val.csv

img_size: 384
batch_size: 8
epochs: 120
lr: 0.0001

backbone: convnext_tiny
checkpoint_path: runs/cls/cls_best.pth
```

**Train:**

```bash
python train/train_cls.py --config configs/cls.yaml
```

**Expected Output:**
```
Epoch 1: train_loss=1.2341 val_loss=0.9876 val_macro_f1=0.4521 lr=1.00e-04
Epoch 2: train_loss=0.8234 val_loss=0.7123 val_macro_f1=0.6234 lr=1.00e-04
...
Epoch 52: train_loss=0.1234 val_loss=0.3456 val_macro_f1=0.8116 lr=2.50e-06
Saved best cls checkpoint.
```

**Best validation macro-F1:** ~0.81

**Output:** `runs/cls/cls_best.pth`

---

### Step 4: Fine-tune on ROI_pred (Deployment-Aligned)

**Purpose:** Adapt to realistic ROI crops for better deployment performance

**Config:** `configs/cls_pred_ft.yaml`

```yaml
seed: 42

images_dir: data/processed/roi_pred/images
train_csv: data/splits/cls_pred_train.csv
val_csv: data/splits/cls_pred_val.csv

img_size: 384
batch_size: 8
epochs: 30
lr: 0.00001  # Lower LR for fine-tuning

backbone: convnext_tiny
checkpoint_path: runs/cls_pred_ft/cls_pred_ft_best.pth
init_checkpoint: runs/cls/cls_best.pth  # Start from ROI_gt model
```

**Train:**

```bash
python train/train_cls_finetune.py --config configs/cls_pred_ft.yaml
```

**Expected Output:**
```
Epoch 1: train_loss=0.4123 val_loss=0.3987 val_macro_f1=0.7923 lr=1.00e-05
Epoch 2: train_loss=0.3456 val_loss=0.3654 val_macro_f1=0.7987 lr=1.00e-05
...
Epoch 30: train_loss=0.2134 val_loss=0.3234 val_macro_f1=0.8037 lr=1.00e-05
Saved best cls_pred_ft checkpoint.
```

**Best validation macro-F1:** ~0.80

**Output:** `runs/cls_pred_ft/cls_pred_ft_best.pth`

---

## Hyperparameter Tuning

### Segmentation Hyperparameters

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `img_size` | 320 | 256-512 | Higher = better detail, slower |
| `batch_size` | 8 | 4-16 | Depends on GPU memory |
| `lr` | 0.0003 | 1e-4 to 5e-4 | Too high = unstable |
| `encoder` | resnet34 | resnet34/50, efficientnet-b3 | Bigger = better but slower |

**To tune:**
1. Start with defaults
2. If underfitting: Increase model size (resnet50)
3. If overfitting: Add more augmentation
4. Monitor val_dice - should reach >0.85

### Classification Hyperparameters

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| `img_size` | 384 | 224-512 | Match model requirements |
| `batch_size` | 8 | 4-16 | Depends on GPU memory |
| `lr` | 0.0001 | 5e-5 to 2e-4 | Too low = slow convergence |
| `backbone` | convnext_tiny | convnext_tiny/small, efficientnet-b4/5 | Bigger = better but slower |

**To tune:**
1. Start with defaults
2. Monitor class-wise F1 - identify weak classes
3. If Stage 1 weak: Collect more Stage 1 data
4. If Stage 3/4 confused: Check if visually ambiguous

---

## Monitoring Training

### TensorBoard

Training scripts automatically log to TensorBoard.

**Launch:**

```bash
tensorboard --logdir runs/
```

**Open:** http://localhost:6006

**Metrics to watch:**

**Segmentation:**
- `seg/train_loss` - Should decrease steadily
- `seg/val_dice` - Should increase to >0.85
- `seg/lr` - Should decay over time

**Classification:**
- `cls/train_loss` - Should decrease steadily
- `cls/val_macro_f1` - Should increase to >0.75
- `cls/val_loss` - Should decrease (if increasing = overfitting)

### CSV Logs

Metrics are also saved as CSV for offline analysis:

```
runs/seg/tb/<timestamp>/metrics.csv
runs/cls/tb/<timestamp>/metrics.csv
runs/cls_pred_ft/tb/<timestamp>/metrics.csv
```

**Load and plot:**

```python
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv("runs/seg/tb/seg_20241229-143022/metrics.csv")

plt.plot(df["epoch"], df["val_dice"])
plt.xlabel("Epoch")
plt.ylabel("Validation Dice")
plt.title("Segmentation Training")
plt.show()
```

---

## Model Evaluation

### Segmentation Evaluation

```python
import torch
import cv2
import numpy as np
from tqdm import tqdm
import pandas as pd
import segmentation_models_pytorch as smp

def dice_score(pred, target):
    pred = (pred > 0.5).astype(np.float32)
    inter = (pred * target).sum()
    union = pred.sum() + target.sum()
    return (2 * inter + 1e-6) / (union + 1e-6)

# Load model
device = "cuda"
ckpt = torch.load("runs/seg/seg_best.pth")
model = smp.Unet(encoder_name="resnet34", encoder_weights=None, in_channels=3, classes=1)
model.load_state_dict(ckpt["state_dict"])
model.to(device).eval()

# Evaluate
val_csv = pd.read_csv("data/splits/seg_val.csv")
scores = []

for _, row in tqdm(val_csv.iterrows(), total=len(val_csv)):
    img = cv2.imread(row["image"])
    mask = cv2.imread(row["image"].replace("images", "masks"), 0)
    
    img_rs = cv2.resize(img, (320, 320))
    mask_rs = cv2.resize(mask, (320, 320)) / 255.0
    
    x = torch.from_numpy(img_rs).permute(2,0,1).float().unsqueeze(0) / 255.0
    x = x.to(device)
    
    with torch.no_grad():
        logits = model(x)
        pred = torch.sigmoid(logits)[0,0].cpu().numpy()
    
    dice = dice_score(pred, mask_rs)
    scores.append(dice)

print(f"Mean Dice: {np.mean(scores):.4f} ± {np.std(scores):.4f}")
```

### Classification Evaluation

```python
import torch
import timm
import cv2
import numpy as np
from sklearn.metrics import classification_report, confusion_matrix
import pandas as pd
from tqdm import tqdm

# Load model
device = "cuda"
ckpt = torch.load("runs/cls_pred_ft/cls_pred_ft_best.pth")
model = timm.create_model("convnext_tiny", pretrained=False, num_classes=4)
model.load_state_dict(ckpt["state_dict"])
model.to(device).eval()

stages = ckpt["stages"]

# Evaluate
val_csv = pd.read_csv("data/splits/cls_pred_val.csv")
y_true, y_pred = [], []

for _, row in tqdm(val_csv.iterrows(), total=len(val_csv)):
    img = cv2.imread(row["image"])
    img = cv2.resize(img, (384, 384))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB) / 255.0
    
    # ImageNet normalize
    mean = np.array([0.485, 0.456, 0.406])
    std = np.array([0.229, 0.224, 0.225])
    img = (img - mean) / std
    
    x = torch.from_numpy(img).permute(2,0,1).float().unsqueeze(0).to(device)
    
    with torch.no_grad():
        logits = model(x)
        pred = logits.argmax(dim=1).item()
    
    y_true.append(stages.index(row["stage"]))
    y_pred.append(pred)

# Report
print(classification_report(y_true, y_pred, target_names=stages))
print("\nConfusion Matrix:")
print(confusion_matrix(y_true, y_pred))
```

---

## Troubleshooting

### Issue: Out of Memory (OOM)

**Error:** `RuntimeError: CUDA out of memory`

**Solutions:**
1. Reduce `batch_size` (e.g., 8 → 4)
2. Reduce `img_size` (e.g., 384 → 320)
3. Use smaller encoder (e.g., resnet34 instead of resnet50)
4. Enable gradient checkpointing (advanced)

### Issue: Training Not Converging

**Symptoms:** Loss stays high, metrics don't improve

**Solutions:**
1. Check data loading (visualize batches)
2. Reduce learning rate (e.g., 1e-4 → 5e-5)
3. Increase epochs
4. Check for bugs in loss function

### Issue: Overfitting

**Symptoms:** Training metric high, validation low

**Solutions:**
1. Add more data augmentation
2. Reduce model size
3. Add dropout (modify model)
4. Use early stopping

### Issue: Class Imbalance

**Symptoms:** Model always predicts majority class

**Solutions:**
1. Use weighted loss (already implemented)
2. Oversample minority classes
3. Use focal loss
4. Collect more minority class data

### Issue: Segmentation Mask Quality

**Symptoms:** Low Dice score, poor boundaries

**Solutions:**
1. Check annotation quality
2. Increase `img_size`
3. Use stronger encoder (efficientnet-b3)
4. Train longer

---

## Next Steps

After training:

1. **Upload to Hugging Face:**
   ```bash
   python scripts/upload_to_hf.py
   ```

2. **Run end-to-end inference:**
   ```bash
   python inference/infer_unseen.py --input test_image.jpg
   ```

3. **Evaluate on held-out test set:**
   ```bash
   python scripts/evaluate.py --test_csv data/splits/test.csv
   ```

4. **Deploy:**
   - See `docs/deployment_guide.md`

---

## Additional Resources

- [Segmentation Models PyTorch Docs](https://smp.readthedocs.io/)
- [Timm Documentation](https://huggingface.co/docs/timm)
- [Albumentations](https://albumentations.ai/docs/)
- [TensorBoard Tutorial](https://pytorch.org/tutorials/recipes/recipes/tensorboard_with_pytorch.html)

---

**Questions?** Open an issue on GitHub or contact the project author.
