import os
import json
import argparse
import time
from pathlib import Path

import numpy as np
import cv2
import torch
import torch.nn.functional as F
import pandas as pd
import segmentation_models_pytorch as smp
import timm
from PIL import Image, ImageOps


# -------------------------
# Helpers
# -------------------------
def read_rgb(path: str, use_exif: bool = True) -> np.ndarray:
    """
    Read an RGB image.
    - use_exif=True: uses PIL + EXIF transpose (phone-accurate)
    - use_exif=False: uses OpenCV (no EXIF rotation), matches many training pipelines
    """
    if use_exif:
        img = Image.open(path)
        img = ImageOps.exif_transpose(img).convert("RGB")
        return np.array(img)
    else:
        bgr = cv2.imread(path)
        if bgr is None:
            raise FileNotFoundError(path)
        return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)


def keep_largest_component(mask01: np.ndarray) -> np.ndarray:
    mask01 = mask01.astype(np.uint8)
    num, labels, stats, _ = cv2.connectedComponentsWithStats(mask01, connectivity=8)
    if num <= 1:
        return mask01
    areas = stats[1:, cv2.CC_STAT_AREA]
    largest = 1 + int(np.argmax(areas))
    return (labels == largest).astype(np.uint8)

def bbox_from_mask(mask01: np.ndarray):
    ys, xs = np.where(mask01 > 0)
    if len(xs) == 0 or len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())

def expand_bbox(bbox, W, H, pad_ratio=0.25):
    x1, y1, x2, y2 = bbox
    bw = x2 - x1 + 1
    bh = y2 - y1 + 1
    pad_w = int(bw * pad_ratio)
    pad_h = int(bh * pad_ratio)
    x1 = max(0, x1 - pad_w); y1 = max(0, y1 - pad_h)
    x2 = min(W - 1, x2 + pad_w); y2 = min(H - 1, y2 + pad_h)
    return x1, y1, x2, y2

def overlay_mask(rgb: np.ndarray, mask01: np.ndarray, alpha=0.4) -> np.ndarray:
    out = rgb.copy()
    red = out.copy()
    red[mask01 > 0] = (255, 0, 0)
    out = (rgb.astype(np.float32) * (1 - alpha) + red.astype(np.float32) * alpha).astype(np.uint8)
    return out

def imagenet_normalize(chw_float01: torch.Tensor) -> torch.Tensor:
    mean = torch.tensor([0.485, 0.456, 0.406], device=chw_float01.device).view(3,1,1)
    std  = torch.tensor([0.229, 0.224, 0.225], device=chw_float01.device).view(3,1,1)
    return (chw_float01 - mean) / std


# -------------------------
# Main
# -------------------------
@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Input image file or folder")
    ap.add_argument("--out", default="", help="Output folder (default: runs/unseen_<timestamp>)")
    ap.add_argument("--seg_ckpt", default="runs/seg/seg_best.pth")
    ap.add_argument("--cls_ckpt", default="runs/cls/cls_best.pth")
    ap.add_argument("--mask_thresh", type=float, default=0.5)
    ap.add_argument("--pad", type=float, default=0.25, help="ROI padding ratio around bbox")
    ap.add_argument("--conf_thresh", type=float, default=0.60, help="Below this => review_needed")
    ap.add_argument("--min_area_ratio", type=float, default=0.002, help="Below this => review_needed")
    ap.add_argument("--no_exif", action="store_true", help="Disable EXIF transpose (for debugging)")
    args = ap.parse_args()

    print("[USING] seg_ckpt:", args.seg_ckpt)
    print("[USING] cls_ckpt:", args.cls_ckpt)
    print("[USING] no_exif:", args.no_exif)


    device = "cuda" if torch.cuda.is_available() else "cpu"

    # ---- Output dir ----
    if args.out.strip() == "":
        run_name = time.strftime("unseen_%Y%m%d-%H%M%S")
        out_dir = Path("runs") / run_name
    else:
        out_dir = Path(args.out)
    (out_dir / "masks").mkdir(parents=True, exist_ok=True)
    (out_dir / "overlays").mkdir(parents=True, exist_ok=True)
    (out_dir / "roi").mkdir(parents=True, exist_ok=True)

    # ---- Load segmentation checkpoint ----
    seg_ckpt = torch.load(args.seg_ckpt, map_location=device)
    seg_cfg = seg_ckpt.get("cfg", {})
    seg_img_size = int(seg_cfg.get("img_size", 320))
    seg_encoder = seg_cfg.get("encoder", "resnet34")

    seg_model = smp.Unet(
        encoder_name=seg_encoder,
        encoder_weights=None,
        in_channels=3,
        classes=1
    )
    seg_model.load_state_dict(seg_ckpt["state_dict"])
    seg_model.to(device).eval()

    # ---- Load classification checkpoint ----
    cls_ckpt = torch.load(args.cls_ckpt, map_location=device)
    stages = cls_ckpt["stages"]
    cls_cfg = cls_ckpt.get("cfg", {})
    cls_img_size = int(cls_cfg.get("img_size", 384))
    backbone = cls_cfg.get("backbone", "convnext_tiny")

    cls_model = timm.create_model(backbone, pretrained=False, num_classes=len(stages))
    cls_model.load_state_dict(cls_ckpt["state_dict"])
    cls_model.to(device).eval()

    # ---- Collect inputs ----
    inp = Path(args.input)
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    if inp.is_file():
        files = [inp]
    else:
        files = [p for p in inp.rglob("*") if p.suffix.lower() in exts]

    if len(files) == 0:
        print("No images found in:", inp.resolve())
        return

    results = []

    for p in files:
        rgb = read_rgb(str(p), use_exif=not args.no_exif)
        H, W = rgb.shape[:2]

        # -------- Segmentation --------
        rgb_rs = cv2.resize(rgb, (seg_img_size, seg_img_size), interpolation=cv2.INTER_AREA)
        x = torch.from_numpy(rgb_rs).permute(2,0,1).float().unsqueeze(0) / 255.0
        x = x.to(device)

        logits = seg_model(x)
        prob = torch.sigmoid(logits)[0,0].detach().cpu().numpy()  # (seg,seg)

        prob_big = cv2.resize(prob, (W, H), interpolation=cv2.INTER_LINEAR)
        mask01 = (prob_big > args.mask_thresh).astype(np.uint8)
        mask01 = keep_largest_component(mask01)

        area_ratio = float(mask01.sum()) / float(mask01.size)
        bbox = bbox_from_mask(mask01)

        # Save mask + overlay
        stem = p.stem
        mask_path = out_dir / "masks" / f"{stem}.png"
        cv2.imwrite(str(mask_path), (mask01 * 255).astype(np.uint8))

        overlay = overlay_mask(rgb, mask01, alpha=0.4)
        ov_path = out_dir / "overlays" / f"{stem}_overlay.jpg"
        cv2.imwrite(str(ov_path), cv2.cvtColor(overlay, cv2.COLOR_RGB2BGR))

        # -------- ROI crop --------
        review_needed = False
        review_reasons = []

        if bbox is None:
            review_needed = True
            review_reasons.append("no_mask_detected")
            # fallback: use full image as ROI
            roi = rgb
            roi_bbox = (0,0,W-1,H-1)
        else:
            roi_bbox = expand_bbox(bbox, W, H, pad_ratio=args.pad)
            x1,y1,x2,y2 = roi_bbox
            roi = rgb[y1:y2+1, x1:x2+1]

        if area_ratio < args.min_area_ratio:
            review_needed = True
            review_reasons.append("mask_too_small")

        roi_path = out_dir / "roi" / f"{stem}_roi.jpg"
        cv2.imwrite(str(roi_path), cv2.cvtColor(roi, cv2.COLOR_RGB2BGR))

        # -------- Classification --------
        roi_rs = cv2.resize(roi, (cls_img_size, cls_img_size), interpolation=cv2.INTER_AREA)
        cx = torch.from_numpy(roi_rs).permute(2,0,1).float() / 255.0
        cx = cx.to(device)
        cx = imagenet_normalize(cx).unsqueeze(0)

        clogits = cls_model(cx)
        probs = F.softmax(clogits, dim=1)[0].detach().cpu().numpy()

        top2_idx = probs.argsort()[-2:][::-1]
        top2 = [{"stage": stages[i], "prob": float(probs[i])} for i in top2_idx]

        pred_idx = int(top2_idx[0])
        pred_stage = stages[pred_idx]
        conf = float(probs[pred_idx])

        if conf < args.conf_thresh:
            review_needed = True
            review_reasons.append("low_confidence")

        results.append({
            "file": str(p),
            "pred_stage": pred_stage,
            "confidence": conf,
            "area_ratio": area_ratio,  # ratio of pixels in mask / total pixels
            "roi_bbox": {"x1": roi_bbox[0], "y1": roi_bbox[1], "x2": roi_bbox[2], "y2": roi_bbox[3]},
            "review_needed": review_needed,
            "review_reasons": review_reasons,
            "mask_path": str(mask_path),
            "overlay_path": str(ov_path),
            "roi_path": str(roi_path),
            "top2": top2,
        })

    # Save outputs
    out_csv = out_dir / "unseen_results.csv"
    pd.DataFrame(results).to_csv(out_csv, index=False)

    out_json = out_dir / "unseen_results.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    print("Done.")
    print("Saved to:", out_dir.resolve())
    print("CSV:", out_csv.resolve())
    print("JSON:", out_json.resolve())


if __name__ == "__main__":
    main()
