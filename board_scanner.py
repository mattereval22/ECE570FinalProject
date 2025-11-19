from pathlib import Path
import random
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image, ImageDraw
import matplotlib.pyplot as plt
import joblib
import tensorflow as tf

# -------------------------------------------------------------------
# Paths – adjust RAW_PCB_ROOT if your Drive path is different
# -------------------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent

# Your trained patch model + class names (same as dl_classifier.py)
DL_MODEL_PATH = BASE_DIR / "pcb_defect_classifier.keras"
CLASS_NAMES_PATH = BASE_DIR / "pcb_class_names.pkl"

# Full-board split dataset (what you used to create pcb_patches)
BOARD_DATA_ROOT = BASE_DIR / "data" / "pcb_defects"

# Raw Kaggle dataset on Drive – used only to read XML ground truth
RAW_PCB_ROOT = Path(
    "/content/drive/MyDrive/ECE570FinalProject/data/raw_kaggle_pcb/PCB_DATASET"
)
RAW_IMG_DIR = RAW_PCB_ROOT / "Images"
RAW_ANNOT_DIR = RAW_PCB_ROOT / "Annotations"

IMG_SIZE = (224, 224)   # patch model input size


# -------------------------------------------------------------------
# Utility: parse VOC-style XML annotation
# -------------------------------------------------------------------

def parse_xml(xml_path: Path):
    """
    Return:
        filename: str
        objects: list of dicts {class_name, xmin, ymin, xmax, ymax}
    """
    tree = ET.parse(xml_path)
    root = tree.getroot()

    filename = root.find("filename").text.strip()
    objects = []

    for obj in root.findall("object"):
        cls_name = obj.find("name").text.strip()
        bnd = obj.find("bndbox")
        xmin = int(bnd.find("xmin").text)
        ymin = int(bnd.find("ymin").text)
        xmax = int(bnd.find("xmax").text)
        ymax = int(bnd.find("ymax").text)
        objects.append(
            {
                "class_name": cls_name,
                "xmin": xmin,
                "ymin": ymin,
                "xmax": xmax,
                "ymax": ymax,
            }
        )

    return filename, objects


def voc_to_model_class_name(voc_name: str) -> str:
    """
    Map VOC / folder class names to the lowercase names used in pcb_patches.
    E.g. 'Spurious_copper' -> 'spurious_copper'
    """
    return voc_name.lower()


# -------------------------------------------------------------------
# Sliding-window scanner
# -------------------------------------------------------------------

def sliding_window_scan(
    img: Image.Image,
    model: tf.keras.Model,
    class_names,
    patch_size=(224, 224),
    stride=112,
    prob_thresh=0.9,
):
    """
    Slide a window over the full board and classify each patch.

    Returns a list of detections:
        [
          {
            'x': int, 'y': int, 'w': int, 'h': int,
            'class_idx': int, 'class_name': str, 'prob': float
          },
          ...
        ]
    """
    W, H = img.size
    pw, ph = patch_size

    detections = []

    # Collect patches in small batches for efficiency
    batch_images = []
    batch_coords = []

    def flush_batch():
        nonlocal detections, batch_images, batch_coords
        if not batch_images:
            return
        x_batch = np.stack(batch_images, axis=0).astype("float32") / 255.0
        probs = model.predict(x_batch, verbose=0)
        pred_idxs = probs.argmax(axis=1)
        pred_probs = probs.max(axis=1)

        for (x, y), c_idx, p in zip(batch_coords, pred_idxs, pred_probs):
            if p >= prob_thresh:
                detections.append(
                    {
                        "x": x,
                        "y": y,
                        "w": pw,
                        "h": ph,
                        "class_idx": int(c_idx),
                        "class_name": class_names[c_idx],
                        "prob": float(p),
                    }
                )

        batch_images = []
        batch_coords = []

    for y in range(0, H - ph + 1, stride):
        for x in range(0, W - pw + 1, stride):
            patch = img.crop((x, y, x + pw, y + ph)).convert("RGB")
            arr = np.array(patch)
            batch_images.append(arr)
            batch_coords.append((x, y))

            if len(batch_images) >= 64:  # batch size
                flush_batch()

    flush_batch()
    return detections


# -------------------------------------------------------------------
# IoU and simple board-level evaluation
# -------------------------------------------------------------------

def compute_iou(box_a, box_b):
    """
    box = (xmin, ymin, xmax, ymax)
    """
    axmin, aymin, axmax, aymax = box_a
    bxmin, bymin, bxmax, bymax = box_b

    inter_xmin = max(axmin, bxmin)
    inter_ymin = max(aymin, bymin)
    inter_xmax = min(axmax, bxmax)
    inter_ymax = min(aymax, bymax)

    inter_w = max(0, inter_xmax - inter_xmin)
    inter_h = max(0, inter_ymax - inter_ymin)
    inter_area = inter_w * inter_h

    area_a = (axmax - axmin) * (aymax - aymin)
    area_b = (bxmax - bxmin) * (bymax - bymin)

    union = area_a + area_b - inter_area
    if union <= 0:
        return 0.0

    return inter_area / union


def evaluate_board_on_full_image(
    board_img_path: Path,
    model: tf.keras.Model,
    class_names,
    prob_thresh=0.9,
    stride=112,
    iou_thresh=0.3,
    show_plot=True,
):
    """
    Run sliding-window scan on a full board and compare with ground-truth XML.
    """
    # Figure out class folder and filename to locate XML
    cls_folder = board_img_path.parent.name        # e.g. 'Spurious_copper'
    filename = board_img_path.name                 # e.g. '06_spurious_copper_04.jpg'
    xml_name = board_img_path.stem + ".xml"        # same stem

    xml_path = RAW_ANNOT_DIR / cls_folder / xml_name
    if not xml_path.exists():
        print(f"⚠️ XML not found for {board_img_path}, skipping.")
        return

    _, gt_objects = parse_xml(xml_path)
    if not gt_objects:
        print(f"⚠️ No objects in XML for {board_img_path}, skipping.")
        return

    # Load full board image
    img = Image.open(board_img_path).convert("RGB")

    # Run sliding-window scan
    detections = sliding_window_scan(
        img,
        model,
        class_names,
        patch_size=IMG_SIZE,
        stride=stride,
        prob_thresh=prob_thresh,
    )

    # Evaluate simple coverage: for each GT box, do we have any detection
    # of the correct class with IoU >= iou_thresh?
    hits = 0
    gt_boxes = []
    gt_classes = []
    for obj in gt_objects:
        gt_cls_raw = obj["class_name"]          # e.g. 'Spurious_copper'
        gt_cls = voc_to_model_class_name(gt_cls_raw)  # 'spurious_copper'
        gt_box = (obj["xmin"], obj["ymin"], obj["xmax"], obj["ymax"])
        gt_boxes.append(gt_box)
        gt_classes.append(gt_cls)

        matched = False
        for det in detections:
            if det["class_name"] != gt_cls:
                continue
            det_box = (det["x"], det["y"], det["x"] + det["w"], det["y"] + det["h"])
            iou = compute_iou(gt_box, det_box)
            if iou >= iou_thresh:
                matched = True
                break
        if matched:
            hits += 1

    recall = hits / len(gt_boxes)

    print(f"\n=== Board: {board_img_path.name} ({cls_folder}) ===")
    print(f"GT defects: {len(gt_boxes)}  |  detections (≥{prob_thresh:.2f}): {len(detections)}")
    print(f"GT boxes hit (IoU ≥ {iou_thresh:.2f}, correct class): {hits}/{len(gt_boxes)} "
          f"→ recall ~ {recall*100:.1f}%")

    # Visualization: GT (green) and detections (red)
    if show_plot:
        vis = img.copy()
        draw = ImageDraw.Draw(vis)

        # Draw GT in green
        for box, cls in zip(gt_boxes, gt_classes):
            xmin, ymin, xmax, ymax = box
            draw.rectangle([xmin, ymin, xmax, ymax], outline="lime", width=3)
            draw.text((xmin + 3, ymin + 3), cls, fill="lime")

        # Draw detections in red
        for det in detections:
            xmin = det["x"]
            ymin = det["y"]
            xmax = det["x"] + det["w"]
            ymax = det["y"] + det["h"]
            label = f"{det['class_name']} {det['prob']:.2f}"
            draw.rectangle([xmin, ymin, xmax, ymax], outline="red", width=2)
            draw.text((xmin + 3, ymin + 3), label, fill="red")

        plt.figure(figsize=(8, 6))
        plt.imshow(vis)
        plt.axis("off")
        plt.title(f"{board_img_path.name}  | GT green, det red")
        plt.show()

    return {
        "board": board_img_path,
        "gt_count": len(gt_boxes),
        "det_count": len(detections),
        "hits": hits,
        "recall": recall,
    }


# -------------------------------------------------------------------
# High-level demo: sample a few boards from train/val/test
# -------------------------------------------------------------------

def run_demo(
    split="test",
    num_boards=5,
    prob_thresh=0.9,
    stride=112,
    iou_thresh=0.3,
):
    """
    Sample some full boards from pcb_defects/<split>/<class>/ and run the scanner.
    """
    if not DL_MODEL_PATH.exists() or not CLASS_NAMES_PATH.exists():
        raise FileNotFoundError(
            f"Model or class names not found at {DL_MODEL_PATH} / {CLASS_NAMES_PATH}.\n"
            "Train the patch model first using dl_classifier.py."
        )

    print("Loading trained patch model...")
    model = tf.keras.models.load_model(DL_MODEL_PATH)
    class_names = joblib.load(CLASS_NAMES_PATH)
    print("Class names:", class_names)

    split_dir = BOARD_DATA_ROOT / split
    if not split_dir.exists():
        raise FileNotFoundError(f"Board split directory not found: {split_dir}")

    # Collect all board image paths
    all_boards = []
    for cls_dir in split_dir.iterdir():
        if not cls_dir.is_dir():
            continue
        for img_path in cls_dir.glob("*.jpg"):
            all_boards.append(img_path)

    if not all_boards:
        raise RuntimeError(f"No board images found under {split_dir}")

    print(f"Found {len(all_boards)} boards in split '{split}'.")
    sample_boards = random.sample(all_boards, min(num_boards, len(all_boards)))

    recalls = []
    for board_path in sample_boards:
        result = evaluate_board_on_full_image(
            board_path,
            model,
            class_names,
            prob_thresh=prob_thresh,
            stride=stride,
            iou_thresh=iou_thresh,
            show_plot=True,
        )
        if result is not None:
            recalls.append(result["recall"])

    if recalls:
        avg_recall = np.mean(recalls)
        print(f"\nAverage recall over {len(recalls)} boards: {avg_recall*100:.1f}% "
              f"(IoU≥{iou_thresh}, prob≥{prob_thresh})")
    else:
        print("No valid boards evaluated (missing XML or no GT objects).")


if __name__ == "__main__":
    # Default: try a few test boards
    run_demo(split="test", num_boards=5)