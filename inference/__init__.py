"""
WoundCare AI Inference Module

End-to-end inference pipeline for pressure injury staging.

Usage:
    python inference/infer_unseen.py --input <image> --out <output_dir>

Main script:
    infer_unseen.py - Complete inference pipeline with segmentation + classification
"""

__version__ = "1.0.0"
__all__ = []

# Note: infer_unseen.py is a command-line script, not a library.
# Import it directly if needed:
#   from inference import infer_unseen
#   
# Or run it from command line:
#   python inference/infer_unseen.py --input image.jpg
