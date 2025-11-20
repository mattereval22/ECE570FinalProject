# debug_image.py
from pathlib import Path
import argparse
import numpy as np
from PIL import Image
import tensorflow as tf

import board_scanner
from board_scanner import _load_patch_model_and_classes, IMG_SIZE


def preprocess_raw_for_model(img: Image.Image) -> np.ndarray:
    """
    Minimal preprocessing to match training:

    - convert to RGB
    - resize to IMG_SIZE
    - DO NOT divide by 255.0 here, because the model
      already has a Rescaling(1/255) layer.
    - add batch dimension
    """
    img = img.convert("RGB")
    img_resized = img.resize(IMG_SIZE, Image.BILINEAR)

    arr = np.array(img_resized).astype("float32")  # [H, W, 3]
    print(">>> Preprocessed patch stats:")
    print("    shape:", arr.shape)
    print("    dtype:", arr.dtype)
    print("    min / max / mean:", arr.min(), arr.max(), arr.mean())

    # Save what the model *actually* sees, for visual sanity
    debug_path = Path("debug_resized_patch.png")
    img_resized.save(debug_path)
    print(f"    Saved resized patch to: {debug_path.resolve()}")

    # Add batch dimension: [1, H, W, 3]
    batch = np.expand_dims(arr, axis=0)
    return batch


def main():
    parser = argparse.ArgumentParser(
        description="Debug how a single image is preprocessed and classified."
    )
    parser.add_argument(
        "image_path",
        type=str,
        help="Path to a test image (e.g. a 224x224 patch or microscope crop).",
    )
    args = parser.parse_args()

    img_path = Path(args.image_path)
    if not img_path.exists():
        raise FileNotFoundError(f"Image not found: {img_path}")

    print("Using board_scanner.DL_MODEL_PATH:", board_scanner.DL_MODEL_PATH)
    print("Using board_scanner.CLASS_NAMES_PATH:", board_scanner.CLASS_NAMES_PATH)

    # Load the same model & classes that Streamlit uses
    model, class_names, centroids = _load_patch_model_and_classes()
    print("Loaded classes:", class_names)
    print("IMG_SIZE (model input size):", IMG_SIZE)

    # Load the raw image
    img = Image.open(img_path)
    print("Original image size:", img.size)

    # Minimal preprocessing
    batch = preprocess_raw_for_model(img)

    # Forward pass
    logits = model.predict(batch, verbose=0)[0]  # shape [num_classes]
    print("\n>>> Raw model output (logits):")
    print(logits)

    # If the last layer doesn’t already apply softmax, you can uncomment this:
    # probs = tf.nn.softmax(logits).numpy()
    probs = logits  # your model already uses softmax in the last Dense

    probs = np.asarray(probs, dtype="float32")
    top_idx = int(np.argmax(probs))
    top_prob = float(probs[top_idx])
    top_class = class_names[top_idx]

    print("\n>>> Probabilities per class:")
    for cls, p in zip(class_names, probs):
        print(f"  {cls:15s}: {p:.4f}")

    print(f"\n>>> PREDICTION: {top_class} (p = {top_prob:.4f})")


if __name__ == "__main__":
    main()