#!/usr/bin/env python3
"""
prepare_dataset.py

Download the Peking University PCB defect dataset from Kaggle and
reorganize it into the directory structure expected by dl_classifier.py:

Requirements:
  - kaggle CLI installed (pip install kaggle)
  - ~/kaggle.json configured with your Kaggle API credentials
"""

import os
import shutil
import subprocess
import sys
import random
from pathlib import Path
from typing import Dict, List, Tuple

from PIL import Image
import xml.etree.ElementTree as ET

# -----------------------
# Paths and configuration
# -----------------------

COLAB_DRIVE_BASE = Path("/content/drive/MyDrive/ECE570FinalProject")
if COLAB_DRIVE_BASE.exists():
    BASE_DIR = COLAB_DRIVE_BASE
else:
    BASE_DIR = Path(__file__).resolve().parent

RAW_DATA_ROOT = BASE_DIR / "data" / "raw_kaggle"
PATCH_ROOT = BASE_DIR / "data" / "pcb_patches"

KAGGLE_DATASET = "akhatova/pcb-defects"

TARGET_CLASSES = [
    "missing_hole",
    "mouse_bite",
    "open_circuit",
    "short",
    "spur",
    "spurious_copper",
]

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp"}

TRAIN_FRACTION = 0.70
VAL_FRACTION = 0.15
TEST_FRACTION = 0.15
RANDOM_SEED = 42


# -----------------
# Utility functions
# -----------------

def check_kaggle_cli() -> None:
    from shutil import which

    if which("kaggle") is None:
        raise RuntimeError(
            "The 'kaggle' CLI is not installed or not on PATH.\n"
            "Install via: pip install kaggle\n"
            "Then ensure it is on your PATH."
        )

    kaggle_json = BASE_DIR / "kaggle.json"
    if not kaggle_json.exists():
        raise RuntimeError(
            "Kaggle credentials not found at ~/.kaggle/kaggle.json\n"
            "Download your API token from Kaggle (Account -> API -> Create New API Token)\n"
            "and place kaggle.json into ~/.kaggle with permissions 600."
        )


def run_kaggle_download() -> None:
    RAW_DATA_ROOT.mkdir(parents=True, exist_ok=True)

    print(f"Downloading Kaggle dataset '{KAGGLE_DATASET}' into {RAW_DATA_ROOT} ...")
    cmd = [
        "kaggle",
        "datasets",
        "download",
        "-d",
        KAGGLE_DATASET,
        "-p",
        str(RAW_DATA_ROOT),
        "--unzip",
    ]
    print("Running:", " ".join(cmd))
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    print(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(
            f"kaggle CLI returned non-zero exit code {result.returncode}. "
            "See output above for details."
        )

    print("✅ Kaggle dataset download and unzip completed.")


def split_indices(n: int) -> Tuple[List[int], List[int], List[int]]:
    indices = list(range(n))
    random.shuffle(indices)

    n_train = int(TRAIN_FRACTION * n)
    n_val = int(VAL_FRACTION * n)
    n_test = n - n_train - n_val

    train_idx = indices[:n_train]
    val_idx = indices[n_train:n_train + n_val]
    test_idx = indices[n_train + n_val:]

    return train_idx, val_idx, test_idx


def find_pcb_root(raw_root: Path) -> Path:
    candidate = raw_root / "PCB_DATASET"
    if candidate.is_dir():
        return candidate

    for dirpath, dirnames, _ in os.walk(raw_root):
        for d in dirnames:
            if d.lower() == "pcb_dataset":
                return Path(dirpath) / d

    raise RuntimeError(
        f"Could not locate a 'PCB_DATASET' folder under {raw_root}. "
        "Check that the Kaggle dataset was downloaded and unzipped correctly."
    )


def find_annotation_dir(pcb_root: Path) -> Path:
    cand_annot_dirs = [
        d for d in pcb_root.iterdir()
        if d.is_dir() and "annot" in d.name.lower()
    ]
    if cand_annot_dirs:
        return cand_annot_dirs[0]
    return pcb_root


def parse_xml_boxes(xml_path: Path) -> List[Dict[str, int]]:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    filename = root.findtext("filename")
    boxes: List[Dict[str, int]] = []
    for obj in root.findall("object"):
        class_name = obj.findtext("name")
        bnd = obj.find("bndbox")
        xmin = int(float(bnd.findtext("xmin")))
        ymin = int(float(bnd.findtext("ymin")))
        xmax = int(float(bnd.findtext("xmax")))
        ymax = int(float(bnd.findtext("ymax")))
        boxes.append(
            {
                "filename": filename,
                "class_name": class_name,
                "xmin": xmin,
                "ymin": ymin,
                "xmax": xmax,
                "ymax": ymax,
            }
        )
    return boxes


def build_xml_index(raw_annot_dir: Path) -> Dict[str, Path]:
    xml_index: Dict[str, Path] = {}
    xml_paths = list(raw_annot_dir.rglob("*.xml"))
    if not xml_paths:
        raise RuntimeError(f"No XML annotation files found under {raw_annot_dir}")
    for xml_path in xml_paths:
        stem = xml_path.stem
        xml_index[stem] = xml_path
    print(f"Indexed {len(xml_index)} XML annotation files from {raw_annot_dir}")
    return xml_index


def collect_boards_by_class(raw_img_dir: Path) -> Dict[str, List[Path]]:
    boards_by_class: Dict[str, List[Path]] = {cls: [] for cls in TARGET_CLASSES}
    if not raw_img_dir.is_dir():
        raise RuntimeError(
            f"Expected directory of board images at {raw_img_dir}, but it does not exist."
        )

    for child in sorted(p for p in raw_img_dir.iterdir() if p.is_dir()):
        cls_canonical = child.name.lower()
        if cls_canonical not in TARGET_CLASSES:
            # Ignore non-defect folders
            continue
        imgs = list(child.glob("*.jpg")) + list(child.glob("*.png"))
        imgs = sorted(imgs)
        if not imgs:
            raise RuntimeError(f"No images found under {child}")
        boards_by_class[cls_canonical] = imgs
        print(f"Found {len(imgs)} board images for class '{cls_canonical}' at {child}")

    missing = [cls for cls, imgs in boards_by_class.items() if not imgs]
    if missing:
        raise RuntimeError(
            f"Did not find any board images for these classes under {raw_img_dir}: {missing}"
        )

    return boards_by_class


def crop_board_to_patches(
    img_path: Path,
    xml_path: Path,
    split: str,
    patch_root: Path,
    pad: int = 10,
    min_size: int = 32,
) -> int:
    """
    Given a board image and its XML, crop one patch per defect box and save under:
        patch_root / split / class_name / <image>_boxK.jpg

    Class directory names are canonicalized to lowercase to match TARGET_CLASSES.
    """
    img = Image.open(img_path).convert("RGB")
    boxes = parse_xml_boxes(xml_path)
    saved = 0

    for i, box in enumerate(boxes):
        x1 = max(0, box["xmin"] - pad)
        y1 = max(0, box["ymin"] - pad)
        x2 = min(img.width, box["xmax"] + pad)
        y2 = min(img.height, box["ymax"] + pad)

        if x2 <= x1 or y2 <= y1:
            continue
        if (x2 - x1) < min_size or (y2 - y1) < min_size:
            continue

        patch = img.crop((x1, y1, x2, y2))

        cls_raw = box["class_name"] or ""
        cls = cls_raw.lower()
        if cls not in TARGET_CLASSES:
            # Ignore any unexpected labels
            continue

        out_dir = patch_root / split / cls
        out_dir.mkdir(parents=True, exist_ok=True)
        out_name = f"{img_path.stem}_box{i}.jpg"
        patch.save(out_dir / out_name, quality=95)
        saved += 1

    return saved


def build_patches_from_xml(raw_root: Path, patch_root: Path) -> None:
    """
    Recreate the Colab XML-based cropping pipeline entirely under the local
    project directory.

    Steps:
      1) Locate PCB_DATASET under raw_root.
      2) Find the images directory and annotation directory.
      3) Build an index of XML files by image stem.
      4) For each class, split board images into train/val/test.
      5) For each board, crop all defect patches and write them to
         patch_root/train|val|test/<class>/...
    """
    pcb_root = find_pcb_root(raw_root)
    raw_img_dir = pcb_root / "images"
    if not raw_img_dir.is_dir():
        raise RuntimeError(
            f"Expected 'images' subdirectory under {pcb_root}, but none was found."
        )

    raw_annot_dir = find_annotation_dir(pcb_root)
    print(f"Using RAW_ANNOT_DIR: {raw_annot_dir} (exists: {raw_annot_dir.exists()})")
    xml_index = build_xml_index(raw_annot_dir)

    boards_by_class = collect_boards_by_class(raw_img_dir)

    # Start from a clean patch directory
    if patch_root.exists():
        print(f"\nRemoving existing {patch_root} to avoid mixing old and new patches...")
        shutil.rmtree(patch_root)

    total_patches = 0
    missing_xml: List[str] = []

    for cls, board_paths in boards_by_class.items():
        n = len(board_paths)
        train_idx, val_idx, test_idx = split_indices(n)

        def process_indices(indices: List[int], split: str) -> int:
            nonlocal total_patches
            count_for_split = 0
            for i in indices:
                img_path = board_paths[i]
                stem = img_path.stem
                xml_path = xml_index.get(stem)
                if not xml_path:
                    missing_xml.append(stem)
                    continue
                n_saved = crop_board_to_patches(img_path, xml_path, split, patch_root)
                total_patches += n_saved
                count_for_split += n_saved
            return count_for_split

        print(f"\nClass '{cls}': {n} board images")
        n_train = process_indices(train_idx, "train")
        n_val = process_indices(val_idx, "val")
        n_test = process_indices(test_idx, "test")
        print(f"  → patches: train={n_train}, val={n_val}, test={n_test}")

    print("\n✅ Finished cropping defect patches.")
    print("   Total defect patches saved:", total_patches)
    if missing_xml:
        uniq_missing = sorted(set(missing_xml))
        print(
            f"⚠️ No XML found for {len(uniq_missing)} board images (first few): {uniq_missing[:10]}"
        )


def is_prepared_dataset(patch_root: Path) -> bool:
    if not patch_root.exists():
        return False

    for split in ["train", "val", "test"]:
        split_dir = patch_root / split
        if not split_dir.is_dir():
            return False
        for cls in TARGET_CLASSES:
            cls_dir = split_dir / cls
            if not cls_dir.is_dir():
                return False
            if not any(cls_dir.iterdir()):
                return False

    return True


# -------------
# Main pipeline
# -------------

def main():
    print("=== PCB Kaggle Dataset Preparation ===")
    print(f"BASE_DIR: {BASE_DIR}")
    print(f"RAW_DATA_ROOT: {RAW_DATA_ROOT}")
    print(f"PATCH_ROOT: {PATCH_ROOT}")

    random.seed(RANDOM_SEED)

    # 0) If the pcb_patches/train|val|test tree is already present (as in your
    # Colab-prepared submission), reuse it exactly as-is so the user does not
    # need Kaggle or internet access.
    if is_prepared_dataset(PATCH_ROOT):
        print("✅ Found existing prepared dataset; leaving it unchanged.")
        print(f"Training data is ready under: {PATCH_ROOT}")
        print("You can now run dl_classifier.py to train the model.")
        return

    # 1) Download dataset if RAW_DATA_ROOT looks empty
    if not RAW_DATA_ROOT.exists() or not any(RAW_DATA_ROOT.iterdir()):
        print("RAW_DATA_ROOT is empty; downloading Kaggle dataset...")
        check_kaggle_cli()
        run_kaggle_download()
    else:
        print("RAW_DATA_ROOT already contains files; skipping Kaggle download.")

    # 2) Build cropped defect patches from XML annotations into PATCH_ROOT
    build_patches_from_xml(RAW_DATA_ROOT, PATCH_ROOT)

    print("\n✅ Dataset preparation complete.")
    print(f"Training data is ready under: {PATCH_ROOT}")
    print("You can now run dl_classifier.py to train the model.")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("\n❌ Error during dataset preparation:")
        print(e)
        sys.exit(1)