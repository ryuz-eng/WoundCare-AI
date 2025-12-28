"""
U-Net Segmentation Model with ResNet34 Encoder

This architecture is used for wound region segmentation.
Extracted from train_seg.py for reusability.
"""
import segmentation_models_pytorch as smp


def create_segmentation_model(encoder='resnet34', encoder_weights='imagenet'):
    """
    Create U-Net segmentation model
    
    Args:
        encoder: Encoder backbone (default: 'resnet34' from your seg.yaml)
        encoder_weights: Pretrained weights ('imagenet' or None)
    
    Returns:
        U-Net model for binary wound segmentation
    """
    model = smp.Unet(
        encoder_name=encoder,
        encoder_weights=encoder_weights,
        in_channels=3,
        classes=1  # Binary segmentation: wound vs background
    )
    return model


if __name__ == "__main__":
    # Test model creation
    model = create_segmentation_model()
    print(f"   Model created: {model.__class__.__name__}")
    print(f"   Encoder: resnet34")
    print(f"   Output classes: 1 (binary)")
