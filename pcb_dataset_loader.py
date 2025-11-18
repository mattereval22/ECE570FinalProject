from pathlib import Path
import os
from typing import List, Tuple

from tensorflow.keras.preprocessing.image import ImageDataGenerator

# Adjust if needed based on what you see in `data/pcb_defects`
DATA_ROOT = Path(__file__).resolve().parent / "data" / "pcb_defects"

def get_image_root() -> Path:
    """
    Return the root directory where images are stored.
    If the dataset unzips into a subfolder like 'PCB_DATASET' or similar,
    adjust here once you inspect `data/pcb_defects`.
    """
    # Example: if you see a folder 'PCB_DATASET', use:
    # return DATA_ROOT / "PCB_DATASET"
    return DATA_ROOT  # tweak this after you inspect the structure

def build_generators(
    img_size: Tuple[int, int] = (256, 256),
    batch_size: int = 16,
):
    """
    Build Keras ImageDataGenerators for training/validation.

    This assumes a directory structure like:
        data/pcb_defects/
            train/
                missing_hole/
                mouse_bite/
                ...
            val/
                missing_hole/
                mouse_bite/
                ...
    If the downloaded dataset is not organized that way, you'll
    do a small preprocessing script later to rearrange it.
    """
    train_dir = get_image_root() / "train"
    val_dir   = get_image_root() / "val"

    train_datagen = ImageDataGenerator(
        rescale=1./255,
        horizontal_flip=True,
        vertical_flip=True,
        rotation_range=10,
        width_shift_range=0.05,
        height_shift_range=0.05,
        validation_split=0.0,  # explicit split via paths instead
    )

    val_datagen = ImageDataGenerator(
        rescale=1./255,
    )

    train_gen = train_datagen.flow_from_directory(
        train_dir,
        target_size=img_size,
        batch_size=batch_size,
        class_mode="categorical",
        shuffle=True,
    )

    val_gen = val_datagen.flow_from_directory(
        val_dir,
        target_size=img_size,
        batch_size=batch_size,
        class_mode="categorical",
        shuffle=False,
    )

    return train_gen, val_gen
