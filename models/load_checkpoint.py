"""
Download and load model checkpoints from Hugging Face Hub

This utility automatically downloads trained model weights from Hugging Face
on first run, then caches them locally for future use.
"""
import os
import torch
from huggingface_hub import hf_hub_download
from pathlib import Path
from .segmentation import create_segmentation_model
from .classification import create_classification_model

#  CHANGE THIS TO YOUR HUGGING FACE USERNAME
HF_REPO = "benhoxton/woundcare-ai"

# Local cache directory
CACHE_DIR = Path.home() / ".cache" / "woundcare"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# Stage labels (consistent with your training code)
STAGES = ["Stage_1", "Stage_2", "Stage_3", "Stage_4"]
STAGE_TO_IDX = {s: i for i, s in enumerate(STAGES)}


def download_checkpoint(checkpoint_name: str, force_download: bool = False):
    """
    Download model checkpoint from Hugging Face Hub
    
    Args:
        checkpoint_name: Name of checkpoint file (e.g., 'seg_best.pth')
        force_download: If True, re-download even if cached
        
    Returns:
        Path to downloaded checkpoint
    """
    print(f" Downloading {checkpoint_name} from Hugging Face Hub...")
    print(f"   Repository: {HF_REPO}")
    
    try:
        local_path = hf_hub_download(
            repo_id=HF_REPO,
            filename=f"weights/{checkpoint_name}",
            cache_dir=CACHE_DIR,
            force_download=force_download,
        )
        print(f" Downloaded to: {local_path}")
        return local_path
        
    except Exception as e:
        print(f" Error downloading {checkpoint_name}: {e}")
        print(f"\nMake sure:")
        print(f"1. The model exists at: https://huggingface.co/{HF_REPO}")
        print(f"2. The file is in the 'weights/' folder")
        print(f"3. The repository is public or you're logged in with `huggingface-cli login`")
        raise


def load_checkpoint_dict(checkpoint_name: str, device='cpu'):
    """
    Download and load checkpoint dictionary
    
    Args:
        checkpoint_name: Name of checkpoint file
        device: Device to load to ('cpu' or 'cuda')
        
    Returns:
        Checkpoint dictionary containing state_dict, cfg, etc.
    """
    checkpoint_path = download_checkpoint(checkpoint_name)
    
    print(f" Loading checkpoint from {checkpoint_path}...")
    checkpoint = torch.load(checkpoint_path, map_location=device)
    
    return checkpoint


def load_segmentation_model(checkpoint_name='seg_best.pth', device='cpu', encoder='resnet34'):
    """
    Load segmentation model with weights from Hugging Face
    
    This creates the U-Net architecture and loads trained weights.
    
    Args:
        checkpoint_name: Name of checkpoint (default: 'seg_best.pth')
        device: Device to load to ('cpu' or 'cuda')
        encoder: Encoder backbone (default: 'resnet34' from seg.yaml)
        
    Returns:
        Loaded segmentation model ready for inference
    """
    print("  Creating segmentation model architecture...")
    
    # Create model architecture
    model = create_segmentation_model(encoder=encoder, encoder_weights=None)
    
    # Download and load weights
    checkpoint = load_checkpoint_dict(checkpoint_name, device=device)
    
    # Load state dict
    model.load_state_dict(checkpoint['state_dict'])
    
    # Move to device and set to eval mode
    model.to(device)
    model.eval()
    
    # Print info
    if 'best_val_dice' in checkpoint:
        print(f"   Best validation Dice: {checkpoint['best_val_dice']:.4f}")
    
    print(" Segmentation model loaded successfully!")
    return model


def load_classification_model(checkpoint_name='cls_best.pth', device='cpu', backbone='convnext_tiny'):
    """
    Load base classifier (trained on ROI_gt) with weights from Hugging Face
    
    Args:
        checkpoint_name: Name of checkpoint (default: 'cls_best.pth')
        device: Device to load to ('cpu' or 'cuda')
        backbone: Model backbone (default: 'convnext_tiny' from cls.yaml)
        
    Returns:
        Loaded classification model ready for inference
    """
    print("  Creating classification model architecture...")
    
    # Create model architecture
    model = create_classification_model(backbone=backbone, num_classes=4, pretrained=False)
    
    # Download and load weights
    checkpoint = load_checkpoint_dict(checkpoint_name, device=device)
    
    # Load state dict
    model.load_state_dict(checkpoint['state_dict'])
    
    # Move to device and set to eval mode
    model.to(device)
    model.eval()
    
    # Print info
    if 'best_val_macro_f1' in checkpoint:
        print(f"   Best validation macro-F1: {checkpoint['best_val_macro_f1']:.4f}")
    
    print(" Classification model loaded successfully!")
    return model


def load_finetuned_classifier(checkpoint_name='cls_pred_ft_best.pth', device='cpu', backbone='convnext_tiny'):
    """
    Load fine-tuned classifier (trained on ROI_pred) - RECOMMENDED FOR DEPLOYMENT
    
    This is the deployment-ready model that was fine-tuned on ROI_pred crops
    to match real inference conditions.
    
    Args:
        checkpoint_name: Name of checkpoint (default: 'cls_pred_ft_best.pth')
        device: Device to load to ('cpu' or 'cuda')
        backbone: Model backbone (default: 'convnext_tiny')
        
    Returns:
        Loaded fine-tuned classification model ready for inference
    """
    print("  Creating fine-tuned classification model architecture...")
    
    # Create model architecture (same as base classifier)
    model = create_classification_model(backbone=backbone, num_classes=4, pretrained=False)
    
    # Download and load weights
    checkpoint = load_checkpoint_dict(checkpoint_name, device=device)
    
    # Load state dict
    model.load_state_dict(checkpoint['state_dict'])
    
    # Move to device and set to eval mode
    model.to(device)
    model.eval()
    
    # Print info
    if 'best_val_macro_f1' in checkpoint:
        print(f"   Best validation macro-F1: {checkpoint['best_val_macro_f1']:.4f}")
    if 'init_checkpoint' in checkpoint:
        print(f"   Initialized from: {checkpoint['init_checkpoint']}")
    
    print("   Fine-tuned classifier loaded successfully!")
    print("   This model is trained on ROI_pred for deployment realism.")
    return model


if __name__ == "__main__":
    # Test download and loading
    print("=" * 60)
    print("Testing model loading from Hugging Face Hub...")
    print("=" * 60)
    
    try:
        # Test segmentation model
        print("\n1. Testing segmentation model download...")
        seg_model = load_segmentation_model(device='cpu')
        print(f"   Model type: {type(seg_model)}")
        
        # Test classification model
        print("\n2. Testing base classification model download...")
        cls_model = load_classification_model(device='cpu')
        print(f"   Model type: {type(cls_model)}")
        
        # Test fine-tuned model
        print("\n3. Testing fine-tuned classification model download...")
        ft_model = load_finetuned_classifier(device='cpu')
        print(f"   Model type: {type(ft_model)}")
        
        print("\n" + "=" * 60)
        print(" All models loaded successfully!")
        print("=" * 60)
        
    except Exception as e:
        print(f"\n Test failed: {e}")
        print("\nMake sure you:")
        print("1. Updated HF_REPO to your username")
        print("2. Uploaded models to Hugging Face")
        print("3. Made the repository public or logged in")
