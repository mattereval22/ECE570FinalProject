"""
AI_Analyzer package initialization
----------------------------------
This package contains the core modules for AI-driven HDL bug detection.

Modules:
- bug_injector: Generates labeled HDL bug examples
- bug_classifier: Classical ML bug detection
- models: PyTorch models (MLP, TextCNN)
- torch_dataset: Data preparation utilities
- train_torch: Training and evaluation script
- ablation: Feature ablation and experiment analysis
"""

import sys
from pathlib import Path

# Automatically add Checkpoint2 parent folder to sys.path
# so imports work whether you run scripts as modules or standalone
pkg_root = Path(__file__).resolve().parents[1]
if str(pkg_root) not in sys.path:
    sys.path.append(str(pkg_root))

print(f"✅ AI_Analyzer package initialized from: {pkg_root}")