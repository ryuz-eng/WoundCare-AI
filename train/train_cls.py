import os
import yaml
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
import pandas as pd
import albumentations as A
import time
from torch.utils.tensorboard import SummaryWriter
from tqdm import tqdm
import timm
from sklearn.metrics import f1_score

from datasets.wound_dataset import WoundClsDataset

def compute_class_weights(train_csv, stage_to_idx):
    df = pd.read_csv(train_csv)
    counts = df["stage"].value_counts().to_dict()
    total = sum(counts.values())

    w = []
    for stage in stage_to_idx.keys():
        c = counts.get(stage, 1)
        w.append(total / c)

    w = torch.tensor(w, dtype=torch.float32)
    w = w / w.mean()
    return w

def main(cfg_path="configs/cls.yaml"):
    cfg = yaml.safe_load(open(cfg_path, "r"))
    device = "cuda" if torch.cuda.is_available() else "cpu"

    run_name = time.strftime("cls_%Y%m%d-%H%M%S")
    log_dir = os.path.join("runs", "cls", "tb", run_name)
    os.makedirs(log_dir, exist_ok=True)

    writer = SummaryWriter(log_dir=log_dir)
    metrics = []
    print("TensorBoard logdir:", log_dir)

    stages = ["Stage_1", "Stage_2", "Stage_3", "Stage_4"]
    stage_to_idx = {s: i for i, s in enumerate(stages)}

    train_tf = A.Compose([
        A.Resize(cfg["img_size"], cfg["img_size"]),
        A.RandomBrightnessContrast(p=0.5),
        A.HueSaturationValue(p=0.4),
        A.GaussianBlur(p=0.2),
        A.Rotate(limit=15, p=0.5),
    ])
    val_tf = A.Compose([A.Resize(cfg["img_size"], cfg["img_size"])])

    train_ds = WoundClsDataset(cfg["train_csv"], cfg["images_dir"], stage_to_idx, transform=train_tf)
    val_ds   = WoundClsDataset(cfg["val_csv"], cfg["images_dir"], stage_to_idx, transform=val_tf)

    train_loader = DataLoader(train_ds, batch_size=cfg["batch_size"], shuffle=True, num_workers=0, pin_memory=True)
    val_loader   = DataLoader(val_ds, batch_size=cfg["batch_size"], shuffle=False, num_workers=0, pin_memory=True)

    model = timm.create_model(cfg["backbone"], pretrained=True, num_classes=len(stages))
    model.to(device)

    class_weights = compute_class_weights(cfg["train_csv"], stage_to_idx).to(device)
    criterion = nn.CrossEntropyLoss(weight=class_weights)
    optimizer = torch.optim.AdamW(model.parameters(), lr=cfg["lr"])

    # optional but recommended
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="max", factor=0.5, patience=5, verbose=True
    )

    best_f1 = 0.0
    os.makedirs(os.path.dirname(cfg["checkpoint_path"]), exist_ok=True)

    for epoch in range(cfg["epochs"]):
        # ---- Train ----
        model.train()
        train_loss = 0.0
        for x, y in tqdm(train_loader, desc=f"Cls Train {epoch+1}/{cfg['epochs']}"):
            x, y = x.to(device), y.to(device)
            logits = model(x)
            loss = criterion(logits, y)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            train_loss += loss.item()

        # ---- Validate ----
        model.eval()
        ys_true, ys_pred = [], []
        val_loss = 0.0

        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                logits = model(x)
                loss = criterion(logits, y)
                val_loss += loss.item()

                pred = logits.argmax(dim=1)
                ys_true.extend(y.cpu().tolist())
                ys_pred.extend(pred.cpu().tolist())

        macro_f1 = f1_score(ys_true, ys_pred, average="macro")
        avg_train_loss = train_loss / max(1, len(train_loader))
        avg_val_loss = val_loss / max(1, len(val_loader))
        lr = optimizer.param_groups[0]["lr"]

        print(f"Epoch {epoch+1}: train_loss={avg_train_loss:.4f} val_loss={avg_val_loss:.4f} val_macro_f1={macro_f1:.4f} lr={lr:.2e}")

        # ---- TensorBoard ----
        writer.add_scalar("cls/train_loss", avg_train_loss, epoch + 1)
        writer.add_scalar("cls/val_loss", avg_val_loss, epoch + 1)
        writer.add_scalar("cls/val_macro_f1", macro_f1, epoch + 1)
        writer.add_scalar("cls/lr", lr, epoch + 1)

        # ---- CSV ----
        metrics.append({
            "epoch": epoch + 1,
            "train_loss": avg_train_loss,
            "val_loss": avg_val_loss,
            "val_macro_f1": macro_f1,
            "lr": lr
        })
        pd.DataFrame(metrics).to_csv(os.path.join(log_dir, "metrics.csv"), index=False)

        scheduler.step(macro_f1)

        # ---- Save best ----
        if macro_f1 > best_f1:
            best_f1 = macro_f1
            torch.save({
                "state_dict": model.state_dict(),
                "stages": stages,
                "cfg": cfg,
                "best_val_macro_f1": best_f1
            }, cfg["checkpoint_path"])
            print("Saved best cls checkpoint.")

    writer.close()

if __name__ == "__main__":
    main()
