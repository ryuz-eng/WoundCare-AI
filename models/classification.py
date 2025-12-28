"""
ConvNeXt-Tiny Classification Model

This architecture is used for pressure injury staging (Stage 1-4).
Extracted from train_cls.py for reusability.
"""
import timm


def create_classification_model(backbone='convnext_tiny', num_classes=4, pretrained=True):
    """
    Create ConvNeXt-Tiny classifier
    
    Args:
        backbone: Model architecture (default: 'convnext_tiny' from your cls.yaml)
        num_classes: Number of output classes (4 for Stage 1-4)
        pretrained: Use ImageNet pretrained weights
    
    Returns:
        ConvNeXt model for 4-class staging
    """
    model = timm.create_model(
        backbone,
        pretrained=pretrained,
        num_classes=num_classes
    )
    return model


if __name__ == "__main__":
    # Test model creation
    model = create_classification_model()
    print(f"   Model created: ConvNeXt-Tiny")
    print(f"   Number of classes: 4 (Stage 1-4)")
    print(f"   Pretrained: ImageNet")
