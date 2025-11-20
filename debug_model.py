from pathlib import Path
import os
import numpy as np
import hashlib

import board_scanner  # your file
from board_scanner import _load_patch_model_and_classes, IMG_SIZE

print("DL_MODEL_PATH in board_scanner:", board_scanner.DL_MODEL_PATH)
print("Exists?:", board_scanner.DL_MODEL_PATH.exists())

print("CLASS_NAMES_PATH:", board_scanner.CLASS_NAMES_PATH)
print("Exists?:", board_scanner.CLASS_NAMES_PATH.exists())

# Load model + classes directly (bypass Streamlit caching)
model, class_names, centroids = _load_patch_model_and_classes()
print("\nLoaded classes:", class_names)

# Compute signature to compare with Colab
w = model.get_weights()
flat = np.concatenate([x.ravel()[:1000] for x in w])
sig = hashlib.sha1(flat.tobytes()).hexdigest()
print("LOCAL MODEL_SIGNATURE:", sig)

print("Local model mtime:", os.path.getmtime(board_scanner.DL_MODEL_PATH))