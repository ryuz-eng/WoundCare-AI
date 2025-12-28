import os, yaml
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
import albumentations as A
import segmentation_models_pytorch as smp
import time
import pandas as pd
from torch.utils.tensorboard import SummaryWriter
from tqdm import tqdm

from datasets.wound_dataset import WoundSegDataset

def dice_score(pred, target, eps=1e-6):
    pred = (pred > 0.5).float()
    inter = (pred * target).sum()
    union = pred.sum() + target.sum()
    return (2 * inter + eps) / (union + eps)

def main(cfg_path="configs/seg.yaml"):
    cfg = yaml.safe_load(open(cfg_path, "r"))
    device = "cuda" if torch.cuda.is_available() else "cpu"

    run_name = time.strftime("seg_%Y%m%d-%H%M%S")
    log_dir = os.path.join("runs", "seg", "tb", run_name)
    os.makedirs(log_dir, exist_ok=True)

    writer = SummaryWriter(log_dir=log_dir)
    metrics = []
    print("TensorBoard logdir:", log_dir)

    train_tf = A.Compose([
        A.Resize(cfg["img_size"], cfg["img_size"]),
        A.RandomBrightnessContrast(p=0.5),
        A.HueSaturationValue(p=0.3),
        A.GaussianBlur(p=0.2),
        A.Rotate(limit=15, p=0.5),
    ])
    val_tf = A.Compose([A.Resize(cfg["img_size"], cfg["img_size"])])

    train_ds = WoundSegDataset(cfg["train_csv"], cfg["images_dir"], cfg["masks_dir"], transform=train_tf)
    val_ds   = WoundSegDataset(cfg["val_csv"], cfg["images_dir"], cfg["masks_dir"], transform=val_tf)

    train_loader = DataLoader(train_ds, batch_size=cfg["batch_size"], shuffle=True, num_workers=0, pin_memory=True)
    val_loader   = DataLoader(val_ds, batch_size=cfg["batch_size"], shuffle=False, num_workers=0, pin_memory=True)

    model = smp.Unet(encoder_name=cfg["encoder"], encoder_weights="imagenet", in_channels=3, classes=1)
    model.to(device)

    bce = nn.BCEWithLogitsLoss()
    dice_loss = smp.losses.DiceLoss(mode="binary")
    optimizer = torch.optim.AdamW(model.parameters(), lr=cfg["lr"])
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="max", factor=0.5, patience=5, verbose=True
    )

    best_dice = 0.0
    os.makedirs(os.path.dirname(cfg["checkpoint_path"]), exist_ok=True)

    for epoch in range(cfg["epochs"]):
        # ---- Train ----
        model.train()
        train_loss = 0.0
        for x, y in tqdm(train_loader, desc=f"Seg Train {epoch+1}/{cfg['epochs']}"):
            x, y = x.to(device), y.to(device)
            logits = model(x)
            loss = 0.5*bce(logits, y) + 0.5*dice_loss(logits, y)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            train_loss += loss.item()

        # ---- Validate ----
        model.eval()
        val_d = 0.0
        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                logits = model(x)
                probs = torch.sigmoid(logits)
                val_d += dice_score(probs, y).item()

        val_d /= max(1, len(val_loader))
        avg_train_loss = train_loss / max(1, len(train_loader))
        lr = optimizer.param_groups[0]["lr"]

        print(f"Epoch {epoch+1}: train_loss={avg_train_loss:.4f} val_dice={val_d:.4f} lr={lr:.2e}")

        # ---- TensorBoard ----
        writer.add_scalar("seg/train_loss", avg_train_loss, epoch + 1)
        writer.add_scalar("seg/val_dice", val_d, epoch + 1)
        writer.add_scalar("seg/lr", lr, epoch + 1)

        # ---- CSV ----
        metrics.append({"epoch": epoch + 1, "train_loss": avg_train_loss, "val_dice": val_d, "lr": lr})
        pd.DataFrame(metrics).to_csv(os.path.join(log_dir, "metrics.csv"), index=False)

        # ---- Scheduler ----
        scheduler.step(val_d)

        # ---- Save best ----
        if val_d > best_dice:
            best_dice = val_d
            torch.save({
                "state_dict": model.state_dict(),
                "cfg": cfg,
                "best_val_dice": best_dice
            }, cfg["checkpoint_path"])
            print("Saved best seg checkpoint.")

    writer.close()

if __name__ == "__main__":
    main()
