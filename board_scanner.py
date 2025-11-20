from pathlib import Path
import random
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image, ImageDraw
import matplotlib.pyplot as plt
import joblib
import tensorflow as tf

# Streamlit/IO helpers for optional UI
import io

try:
    import streamlit as st  # type: ignore
except ImportError:  # streamlit not required when using this as a library
    st = None

# -------------------------------------------------------------------
# Paths – adjust RAW_PCB_ROOT if your Drive path is different
# -------------------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent

# Your trained patch model + class names (same as dl_classifier.py)
DL_MODEL_PATH = BASE_DIR / "pcb_defect_classifier.keras"
CLASS_NAMES_PATH = BASE_DIR / "pcb_class_names.pkl"
CENTROIDS_PATH = BASE_DIR / "pcb_class_centroids.npy"

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
    stride=28,
    prob_thresh=0.5,
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
    prob_thresh=0.5,
    stride=28,
    iou_thresh=0.25,
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


def evaluate_board_gt_crops(
    board_img_path: Path,
    model: tf.keras.Model,
    class_names,
    show_plot=True,
):
    """
    For each GT object, crop a padded square patch around it, resize to model input,
    and classify it. Print results and optionally show a grid of crops with predictions.
    """
    # Figure out class folder and filename to locate XML
    cls_folder = board_img_path.parent.name        # e.g. 'Spurious_copper'
    filename = board_img_path.name                 # e.g. '06_spurious_copper_04.jpg'
    xml_name = board_img_path.stem + ".xml"        # same stem

    xml_path = RAW_ANNOT_DIR / cls_folder / xml_name
    if not xml_path.exists():
        print(f"⚠️ XML not found for {board_img_path}, skipping.")
        return []

    _, gt_objects = parse_xml(xml_path)
    if not gt_objects:
        print(f"⚠️ No objects in XML for {board_img_path}, skipping.")
        return []

    # Load full board image
    img = Image.open(board_img_path).convert("RGB")

    crops = []
    gt_classes = []

    for obj in gt_objects:
        gxmin, gymin, gxmax, gymax = obj["xmin"], obj["ymin"], obj["xmax"], obj["ymax"]
        gw = gxmax - gxmin
        gh = gymax - gymin
        side = int(max(gw, gh) * 1.5)
        cx = (gxmin + gxmax) / 2
        cy = (gymin + gymax) / 2

        xmin = max(0, int(cx - side / 2))
        ymin = max(0, int(cy - side / 2))
        xmax = min(img.width, int(cx + side / 2))
        ymax = min(img.height, int(cy + side / 2))

        crop = img.crop((xmin, ymin, xmax, ymax)).resize(IMG_SIZE, Image.BILINEAR)
        crops.append(np.array(crop))
        gt_classes.append(voc_to_model_class_name(obj["class_name"]))

    if not crops:
        print("No GT crops to evaluate.")
        return []

    x_batch = np.stack(crops, axis=0).astype("float32") / 255.0
    probs = model.predict(x_batch, verbose=0)
    pred_idxs = probs.argmax(axis=1)
    pred_probs = probs.max(axis=1)

    results = []
    for gt_cls, c_idx, p in zip(gt_classes, pred_idxs, pred_probs):
        pred_cls = class_names[c_idx]
        correct = (pred_cls == gt_cls)
        print(f"GT: {gt_cls}  →  Pred: {pred_cls} (p={p:.2f})")
        results.append({
            "gt_class": gt_cls,
            "pred_class": pred_cls,
            "prob": float(p),
            "correct": correct,
        })

    if show_plot:
        n = len(crops)
        cols = min(5, n)
        rows = (n + cols - 1) // cols
        plt.figure(figsize=(cols * 3, rows * 3))
        for i, (crop_arr, gt_cls, c_idx, p) in enumerate(zip(crops, gt_classes, pred_idxs, pred_probs)):
            pred_cls = class_names[c_idx]
            plt.subplot(rows, cols, i + 1)
            plt.imshow(crop_arr)
            plt.axis('off')
            plt.title(f"{gt_cls} / {pred_cls}\n(p={p:.2f})")
        plt.tight_layout()
        plt.show()

    return results


# -------------------------------------------------------------------
# Streamlit helpers: model loading + single-patch prediction
# -------------------------------------------------------------------

def _load_patch_model_and_classes():
    """Load the trained patch model and class names from disk.

    This is used both by Streamlit and by any other code that wants to
    reuse the patch classifier.
    """
    if not DL_MODEL_PATH.exists() or not CLASS_NAMES_PATH.exists():
        raise FileNotFoundError(
            f"Model or class names not found at {DL_MODEL_PATH} / {CLASS_NAMES_PATH}. "
            "Make sure you have copied the trained .keras file and the class-name pickle "
            "into this project directory."
        )

    model = tf.keras.models.load_model(DL_MODEL_PATH)
    class_names = joblib.load(CLASS_NAMES_PATH)

    centroids = None
    if CENTROIDS_PATH.exists():
        try:
            centroids = np.load(CENTROIDS_PATH)
        except Exception:
            centroids = None

    return model, class_names, centroids


if st is not None:
    # Cache model in Streamlit so we don't reload on every interaction
    @st.cache_resource
    def get_model_and_classes():
        return _load_patch_model_and_classes()
else:
    # Non-Streamlit environment: simple loader
    def get_model_and_classes():
        return _load_patch_model_and_classes()


def _preprocess_patch(img: Image.Image) -> np.ndarray:
    """Resize a PIL image to the CNN input size and turn it into a batch array.

    Note: we do NOT divide by 255 here because the Keras model already includes
    a `Rescaling(1./255)` layer as the first step in its graph. This keeps the
    Streamlit preprocessing consistent with how the model was trained.
    """
    resized = img.resize(IMG_SIZE, Image.BILINEAR)
    arr = np.array(resized).astype("float32")  # keep in 0..255 range
    return np.expand_dims(arr, axis=0)  # (1, H, W, 3)


def _crop_square(img: Image.Image, center_x: int, center_y: int, side: int) -> Image.Image:
    """Crop a square region from `img`, clamped to image bounds.

    Args:
        img: PIL.Image
        center_x, center_y: crop center in pixel coordinates
        side: side length of the square in pixels
    """
    W, H = img.size
    half = side / 2
    xmin = int(max(0, center_x - half))
    ymin = int(max(0, center_y - half))
    xmax = int(min(W, center_x + half))
    ymax = int(min(H, center_y + half))
    return img.crop((xmin, ymin, xmax, ymax))


def run_streamlit_app():
    """Streamlit UI for classifying a single cropped patch from a user image.

    Usage from the terminal:

        streamlit run board_scanner.py
    """
    if st is None:
        raise RuntimeError(
            "Streamlit is not installed. Install it with `pip install streamlit` "
            "and then run `streamlit run board_scanner.py`."
        )

    st.set_page_config(page_title="PCB Defect Classifier", layout="wide")
    st.title("PCB Defect Classifier (Patch Model)")
    st.write(
        "Upload a microscope image of a PCB, adjust the square region of interest using the sliders below, "
        "and the model will classify that patch as one of the 6 defect types. "
        "If no class is very confident, the app will report the patch as likely healthy/unknown."
    )

    # Load model, classes, and optional centroids (cached)
    try:
        model, class_names, centroids = get_model_and_classes()
    except FileNotFoundError as e:
        st.error(str(e))
        return

    healthy_thresh = 0.7  # softmax-based "no strong defect" threshold

    uploaded_file = st.file_uploader(
        "Upload a PCB image (JPG/PNG)", type=["jpg", "jpeg", "png"]
    )

    if uploaded_file is None:
        st.info("Upload an image to begin.")
        return

    # Read the uploaded image
    try:
        img = Image.open(uploaded_file).convert("RGB")
    except Exception as exc:  # pragma: no cover - defensive
        st.error(f"Could not open image: {exc}")
        return

    W, H = img.size
    st.write(f"**Original image size:** {W}×{H} pixels")

    st.image(img, caption="Original uploaded image", use_container_width=True)

    st.subheader("Select region of interest (square)")

    st.markdown(
        "- Use the **position sliders** to move the crop box over the image.\n"
        "- Use the **crop size slider** to choose how zoomed-in you want the patch to be:\n"
        "  - Smaller size → more zoomed-in on a small area.\n"
        "  - Larger size → more zoomed-out context.\n"
        "- The selected square will always be resized to the model's input size."
    )

    anomaly_thresh = None
    if centroids is not None:
        st.markdown("### Optional: anomaly / 'clean board' check")
        st.write(
            "When the model's internal feature vector is far from all class centroids, "
            "the patch may be out-of-distribution (e.g., a truly clean/unknown region)."
        )
        anomaly_thresh = st.slider(
            "Feature-space distance threshold",
            min_value=0.0,
            max_value=50.0,
            value=20.0,
            step=0.5,
            help=(
                "If the distance from the patch features to the nearest training centroid "
                "is greater than this value, the app will treat it as 'no defect detected'."
            ),
        )

    # Relative crop size: fraction of the smaller image dimension
    side_frac = st.slider(
        "Crop size (relative to min image dimension)",
        min_value=0.1,
        max_value=1.0,
        value=0.3,
        step=0.05,
        help="Move this left for a tight, zoomed-in crop; right for a larger, zoomed-out crop.",
    )
    max_side = min(W, H)
    side = int(max_side * side_frac)

    # Position sliders: expressed as fraction of image width/height
    col_pos1, col_pos2 = st.columns(2)
    with col_pos1:
        cx_frac = st.slider(
            "Horizontal position",
            min_value=0.0,
            max_value=1.0,
            value=0.5,
            step=0.01,
        )
    with col_pos2:
        cy_frac = st.slider(
            "Vertical position",
            min_value=0.0,
            max_value=1.0,
            value=0.5,
            step=0.01,
        )

    cx = W * cx_frac
    cy = H * cy_frac
    half = side / 2.0

    xmin = int(max(0, cx - half))
    ymin = int(max(0, cy - half))
    xmax = int(min(W, cx + half))
    ymax = int(min(H, cy + half))

    # Adjust if we hit borders so the crop remains square with desired side length
    crop_w = xmax - xmin
    crop_h = ymax - ymin
    if crop_w < side:
        shift = side - crop_w
        if xmin - shift >= 0:
            xmin -= shift
        elif xmax + shift <= W:
            xmax += shift
        crop_w = xmax - xmin
    if crop_h < side:
        shift = side - crop_h
        if ymin - shift >= 0:
            ymin -= shift
        elif ymax + shift <= H:
            ymax += shift
        crop_h = ymax - ymin

    # Final safety clamp
    xmin = max(0, xmin)
    ymin = max(0, ymin)
    xmax = min(W, xmin + min(side, W - xmin))
    ymax = min(H, ymin + min(side, H - ymin))

    crop = img.crop((xmin, ymin, xmax, ymax))

    st.subheader("Crop preview")
    col1, col2 = st.columns(2)
    with col1:
        vis = img.copy()
        draw = ImageDraw.Draw(vis)
        draw.rectangle([xmin, ymin, xmax, ymax], outline="red", width=3)
        st.image(vis, caption="Selected region (red box)", use_container_width=True)
    with col2:
        st.image(
            crop.resize(IMG_SIZE, Image.BILINEAR),
            caption=f"Patch to be classified ({IMG_SIZE[0]}×{IMG_SIZE[1]})",
            width=IMG_SIZE[0],
        )

    run_btn = st.button("Run prediction on selected region")
    if not run_btn:
        return

    # Prepare batch for model
    patch_batch = _preprocess_patch(crop)

    # Run classification
    probs = model.predict(patch_batch, verbose=0)[0]
    best_idx = int(np.argmax(probs))
    best_cls = class_names[best_idx]
    best_p = float(probs[best_idx])

    # Optional: feature-space anomaly/clean-board check using centroids
    nearest_dist = None
    if centroids is not None and anomaly_thresh is not None:
        try:
            feature_layer = model.get_layer("feature_dense")
            feature_model = tf.keras.Model(model.input, feature_layer.output)
            feats = feature_model.predict(patch_batch, verbose=0)[0]
            dists = np.linalg.norm(centroids - feats, axis=1)
            nearest_dist = float(dists.min())
        except Exception:
            nearest_dist = None

    st.subheader("Prediction")

    is_anomaly = False
    if nearest_dist is not None and anomaly_thresh is not None:
        is_anomaly = nearest_dist > anomaly_thresh

    if best_p < healthy_thresh or is_anomaly:
        st.write(
            "Prediction: **No defect detected / clean or unknown region**."
        )
        st.caption(
            f"Max class `{best_cls}` (confidence {best_p*100:.1f}%)"
            + (
                f"; nearest centroid distance {nearest_dist:.2f} ≥ threshold {anomaly_thresh:.2f}"
                if nearest_dist is not None and anomaly_thresh is not None
                else ""
            )
        )
    else:
        st.write(
            f"Prediction: **{best_cls}** with confidence **{best_p*100:.1f}%**."
        )
        if nearest_dist is not None and anomaly_thresh is not None:
            st.caption(
                f"Nearest centroid distance {nearest_dist:.2f} ≤ threshold {anomaly_thresh:.2f}"
            )


# -------------------------------------------------------------------
# High-level demo: sample a few boards from train/val/test
# -------------------------------------------------------------------

def run_demo(
    split="test",
    num_boards=5,
    prob_thresh=0.5,
    stride=28,
    iou_thresh=0.25,
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
    # When executed directly we prefer to launch the Streamlit app.
    if st is not None:
        run_streamlit_app()
    else:
        print("Streamlit is not installed.")
        print("Install it with `pip install streamlit` and then run:")
        print("    streamlit run board_scanner.py")
        # Optional fallback: still allow the old CLI demo if someone
        # runs the file without Streamlit.
        # run_demo(split="test", num_boards=5)