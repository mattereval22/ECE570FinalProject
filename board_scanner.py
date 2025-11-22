from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import joblib
import tensorflow as tf

try:
    import streamlit as st
except ImportError:  
    st = None

# --- Paths / constants ---
# -------------------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent

DL_MODEL_PATH = BASE_DIR / "pcb_defect_classifier.keras"
CLASS_NAMES_PATH = BASE_DIR / "pcb_class_names.pkl"
CENTROIDS_PATH = BASE_DIR / "pcb_class_centroids.npy"

IMG_SIZE = (224, 224)   # patch model input size



# --- Streamlit helpers: model loading + single-patch prediction ---
# -------------------------------------------------------------------

def _load_patch_model_and_classes():
    """Load trained patch model, class names, and optional centroids."""
    if not DL_MODEL_PATH.exists() or not CLASS_NAMES_PATH.exists():
        raise FileNotFoundError(
            f"Model or class names not found at {DL_MODEL_PATH} / {CLASS_NAMES_PATH}. "
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
    @st.cache_resource
    def get_model_and_classes():
        return _load_patch_model_and_classes()
else:
    # Non-Streamlit environment: simple loader
    def get_model_and_classes():
        return _load_patch_model_and_classes()


def _preprocess_patch(img: Image.Image) -> np.ndarray:
    resized = img.resize(IMG_SIZE, Image.BILINEAR)
    arr = np.array(resized).astype("float32")  
    return np.expand_dims(arr, axis=0)  



def run_streamlit_app():
    """Streamlit UI for classifying a single cropped patch from a user image."""
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



if __name__ == "__main__":
    if st is not None:
        run_streamlit_app()
    else:
        print("Streamlit is not installed.")
        print("Install it with `pip install streamlit` and then run:")
        print("    streamlit run board_scanner.py")