from pathlib import Path
import os
import json
import joblib
import numpy as np

from sklearn.metrics import classification_report, confusion_matrix
from sklearn.utils.class_weight import compute_class_weight

import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.applications.efficientnet import EfficientNetB0

# ------------------------------
# TensorFlow GPU / XLA settings
try:
    # Disable global XLA JIT compilation (autoclustering)
    tf.config.optimizer.set_jit(False)
    print("XLA JIT disabled to avoid delay-kernel timeouts.")
except Exception as e:
    print("Could not disable XLA JIT:", e)

# Make TensorFlow allocate GPU memory on demand instead of grabbing all at once.
try:
    gpus = tf.config.experimental.list_physical_devices("GPU")
    if gpus:
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
        print(f"Enabled memory growth for {len(gpus)} GPU(s).")
except Exception as e:
    print("Could not set GPU memory growth:", e)

 # -----------------------
# Paths & hyperparameters
# -----------------------

COLAB_DRIVE_BASE = Path("/content/drive/MyDrive/ECE570FinalProject")
if COLAB_DRIVE_BASE.exists():
    BASE_DIR = COLAB_DRIVE_BASE
else:
    BASE_DIR = Path(__file__).resolve().parent

DATA_ROOT = BASE_DIR / "data" / "pcb_patches"
BOARD_DATA_ROOT = BASE_DIR / "data" / "pcb_defects"
DL_MODEL_PATH = BASE_DIR / "pcb_defect_classifier.keras"
CLASS_NAMES_PATH = BASE_DIR / "pcb_class_names.pkl"
CENTROIDS_PATH = BASE_DIR / "pcb_class_centroids.npy"
IMG_SIZE = (224, 224)
BATCH_SIZE = 32
MODEL_BACKBONE = "simple_cnn"
HEAD_EPOCHS = 80
HEAD_LEARNING_RATE = 1e-3
FINE_TUNE_EPOCHS = 0
FINE_TUNE_LEARNING_RATE = 1e-5
FINE_TUNE_NUM_LAYERS = 80
SANITY_OVERFIT_MODE = False
SANITY_OVERFIT_TRAIN_IMAGES = 64
SANITY_OVERFIT_VAL_IMAGES = 64
SANITY_LEARNING_RATE = 1e-3
DEBUG_MODE = False
DEBUG_TRAIN_STEPS = 100
DEBUG_VAL_STEPS = 30


# -------------
# Data loading
# -------------

def build_datasets():
    """Build train/validation/test tf.data datasets from directory structure under DATA_ROOT."""
    data_root = DATA_ROOT
    if not data_root.exists() and "BOARD_DATA_ROOT" in globals():
        if BOARD_DATA_ROOT.exists():
            print(f"⚠️ {data_root} not found, falling back to board dataset at {BOARD_DATA_ROOT}")
            data_root = BOARD_DATA_ROOT

    if not data_root.exists():
        raise FileNotFoundError(
            f"DATA_ROOT does not exist: {data_root}. "
        )

    train_dir = data_root / "train"
    val_dir = data_root / "val"
    test_dir = data_root / "test"

    if not train_dir.exists():
        raise FileNotFoundError(f"Train dir not found: {train_dir}")
    if not val_dir.exists():
        raise FileNotFoundError(f"Val dir not found: {val_dir}")
    if not test_dir.exists():
        raise FileNotFoundError(f"Test dir not found: {test_dir}")

    print(f"Using TRAIN_DIR = {train_dir}")
    print(f"Using VAL_DIR   = {val_dir}")
    print(f"Using TEST_DIR  = {test_dir}")

    train_ds = tf.keras.utils.image_dataset_from_directory(
        train_dir,
        labels="inferred",
        label_mode="int",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=True,
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        val_dir,
        labels="inferred",
        label_mode="int",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=False,
    )

    test_ds = tf.keras.utils.image_dataset_from_directory(
        test_dir,
        labels="inferred",
        label_mode="int",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=False,
    )

    class_names = train_ds.class_names
    print("Class names:", class_names)

    if val_ds.class_names != class_names:
        print("⚠️ Warning: val_ds.class_names differ from train_ds.class_names")
        print("  train:", class_names)
        print("  val  :", val_ds.class_names)
    if test_ds.class_names != class_names:
        print("⚠️ Warning: test_ds.class_names differ from train_ds.class_names")
        print("  train:", class_names)
        print("  test :", test_ds.class_names)

    # Cache + prefetch for performance
    AUTOTUNE = tf.data.AUTOTUNE
    train_ds = train_ds.cache().shuffle(1000).prefetch(buffer_size=AUTOTUNE)
    val_ds = val_ds.cache().prefetch(buffer_size=AUTOTUNE)
    test_ds = test_ds.cache().prefetch(buffer_size=AUTOTUNE)

    return train_ds, val_ds, test_ds, class_names


# ----------------
# Class weight util
# ----------------

def compute_class_weights_from_ds(dataset, num_classes):
    """Compute class weights from a (image, label) dataset by iterating through it once."""
    counts = np.zeros(num_classes, dtype=np.int64)
    for _, labels in dataset.unbatch():
        labels_np = labels.numpy()
        if labels_np.ndim == 0:
            counts[labels_np] += 1
        else:
            for l in labels_np:
                counts[l] += 1

    total = counts.sum()
    print("Label counts:", counts.tolist())

    # Use sklearn's balanced weighting formula
    classes = np.arange(num_classes)
    weights = compute_class_weight(
        class_weight="balanced",
        classes=classes,
        y=np.repeat(classes, counts),
    )
    class_weight_dict = {int(c): float(w) for c, w in zip(classes, weights)}
    return class_weight_dict


# -----------------------------
# Feature extractor / centroids
# -----------------------------

def build_feature_extractor(trained_model: tf.keras.Model) -> tf.keras.Model:
    try:
        feature_layer = trained_model.get_layer("feature_dense")
    except ValueError as e:
        raise ValueError(
            "Model does not contain a layer named 'feature_dense'. "
            "Make sure build_model defines a Dense layer with name='feature_dense'."
        ) from e

    feature_extractor = models.Model(
        inputs=trained_model.input,
        outputs=feature_layer.output,
    )
    return feature_extractor


def compute_class_centroids(feature_extractor: tf.keras.Model, dataset, num_classes: int):
    """Compute per-class centroids in feature space by averaging embeddings from a dataset."""
    sums = None
    counts = np.zeros(num_classes, dtype=np.int64)

    for images, labels in dataset:
        feats = feature_extractor.predict(images, verbose=0)
        if sums is None:
            sums = np.zeros((num_classes, feats.shape[1]), dtype=np.float64)

        labels_np = labels.numpy()
        for f, l in zip(feats, labels_np):
            sums[l] += f
            counts[l] += 1

    centroids = {}
    if sums is None:
        return centroids  # empty dataset

    for c in range(num_classes):
        if counts[c] > 0:
            centroids[c] = (sums[c] / counts[c]).astype(np.float32)
        else:
            centroids[c] = None  

    return centroids


# ----------------------
# Confusion matrix utils
# ----------------------

def print_confusion_matrix(cm, class_names, title="Confusion matrix"):
    """Print a confusion matrix as a text table."""
    num_classes = len(class_names)
    print(f"\n{title}")
    header = " " * 15 + " ".join(f"{name[:7]:>7}" for name in class_names)
    print(header)
    for i in range(num_classes):
        row_vals = " ".join(f"{int(v):7d}" for v in cm[i])
        print(f"{class_names[i][:13]:>13} {row_vals}")

def summarize_confusions(cm, class_names, top_k=5):
    """Print the most common off-diagonal confusions from a confusion matrix."""
    num_classes = len(class_names)
    confusions = []
    for i in range(num_classes):
        for j in range(num_classes):
            if i == j:
                continue
            count = int(cm[i, j])
            if count > 0:
                confusions.append((count, i, j))

    if not confusions:
        print("\nNo off-diagonal confusions (perfect classification on this split).")
        return

    confusions.sort(reverse=True, key=lambda x: x[0])
    print(f"\nTop {min(top_k, len(confusions))} confusions (true → predicted):")
    for count, i, j in confusions[:top_k]:
        print(
            f"  {class_names[i]} → {class_names[j]}: {count} samples"
        )


# -------------
# Model building
# -------------

def build_model(
    num_classes: int,
    learning_rate: float = HEAD_LEARNING_RATE,
    use_augmentation: bool = True,
    backbone_trainable: bool = True,
):
    inputs = layers.Input(shape=IMG_SIZE + (3,))

    # Data augmentation pipeline applied only during training
    data_augmentation = tf.keras.Sequential(
        [
            layers.RandomFlip("horizontal"),
            layers.RandomRotation(0.1),
            layers.RandomZoom(0.2),
            layers.RandomTranslation(0.05, 0.05),
            layers.RandomContrast(0.1),
        ],
        name="data_augmentation",
    )

    x = inputs
    if use_augmentation:
        x = data_augmentation(x)
    x = layers.Rescaling(1.0 / 255.0, name="rescale_1_255")(x)

    if MODEL_BACKBONE == "simple_cnn":
        # Deep custom CNN backbone with BatchNorm after each conv
        x = layers.Conv2D(32, (3, 3), activation="relu", padding="same")(x)
        x = layers.BatchNormalization()(x)
        x = layers.MaxPooling2D()(x)

        x = layers.Conv2D(64, (3, 3), activation="relu", padding="same")(x)
        x = layers.BatchNormalization()(x)
        x = layers.MaxPooling2D()(x)

        x = layers.Conv2D(128, (3, 3), activation="relu", padding="same")(x)
        x = layers.BatchNormalization()(x)
        x = layers.MaxPooling2D()(x)

        # Extra conv block for more expressive power
        x = layers.Conv2D(256, (3, 3), activation="relu", padding="same")(x)
        x = layers.BatchNormalization()(x)
        x = layers.MaxPooling2D()(x)

        x = layers.GlobalAveragePooling2D(name="avg_pool")(x)
    else:
        # Pretrained EfficientNetB0 backbone (ImageNet weights)
        base_model = EfficientNetB0(
            include_top=False,
            weights="imagenet",
            input_shape=IMG_SIZE + (3,),
            pooling=None,
        )
        base_model.trainable = backbone_trainable
        x = base_model(x, training=False)
        x = layers.GlobalAveragePooling2D(name="avg_pool")(x)

    # Classification head with an explicitly named feature layer
    x = layers.Dense(256, activation="relu", name="feature_dense")(x)
    x = layers.Dropout(0.5)(x)
    outputs = layers.Dense(num_classes, activation="softmax")(x)

    model = models.Model(inputs=inputs, outputs=outputs)

    optimizer = tf.keras.optimizers.Adam(learning_rate=learning_rate)
    model.compile(
        loss="sparse_categorical_crossentropy",
        optimizer=optimizer,
        metrics=["accuracy"],
    )

    return model


# -------------
# Training loop
# -------------

def train_model():
    print("🔧 Training PCB Defect Classifier (CNN + EfficientNet)...")
    print("CWD:", os.getcwd())
    print("BASE_DIR:", BASE_DIR)
    print("DATA_ROOT:", DATA_ROOT)

    train_ds, val_ds, test_ds, class_names = build_datasets()
    num_classes = len(class_names)

    if DEBUG_MODE:
        print("DEBUG_MODE is ON: limiting number of batches for quick experiments.")
        train_ds = train_ds.take(DEBUG_TRAIN_STEPS)
        val_ds = val_ds.take(DEBUG_VAL_STEPS)
        test_ds = test_ds.take(DEBUG_VAL_STEPS)

    if SANITY_OVERFIT_MODE:
        print("SANITY_OVERFIT_MODE is ON: using tiny subset without augmentation to check overfitting.")
        train_ds = train_ds.unbatch().take(SANITY_OVERFIT_TRAIN_IMAGES).batch(BATCH_SIZE)
        val_ds = val_ds.unbatch().take(SANITY_OVERFIT_VAL_IMAGES).batch(BATCH_SIZE)
        AUTOTUNE = tf.data.AUTOTUNE
        train_ds = train_ds.cache().shuffle(1000).prefetch(buffer_size=AUTOTUNE)
        val_ds = val_ds.cache().prefetch(buffer_size=AUTOTUNE)

    if SANITY_OVERFIT_MODE:
        class_weight_dict = None
        print("SANITY_OVERFIT_MODE: skipping class weights to make overfitting easier.")
    else:
        class_weight_dict = compute_class_weights_from_ds(train_ds, num_classes)
        print("Class weights:", class_weight_dict)

    if SANITY_OVERFIT_MODE:
        model = build_model(
            num_classes,
            learning_rate=SANITY_LEARNING_RATE,
            use_augmentation=False,
            backbone_trainable=True,
        )
        model.summary(print_fn=lambda x: print("   " + x))
        print(f"\n🚀 SANITY mode: training on {SANITY_OVERFIT_TRAIN_IMAGES} images "
              f"(val subset {SANITY_OVERFIT_VAL_IMAGES}) with higher LR to check overfitting...")
        history = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=40,
            class_weight=None,
        )
    else:
        print("\n🚀 Stage 1: training classifier head with frozen backbone...")
        model = build_model(
            num_classes,
            learning_rate=HEAD_LEARNING_RATE,
            use_augmentation=True,
            backbone_trainable=False,
        )
        model.summary(print_fn=lambda x: print("   " + x))

        early_stop_head = tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=8,
            restore_best_weights=True,
        )

        reduce_lr = tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=3,
            verbose=1,
            min_lr=1e-5,
        )

        history = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=HEAD_EPOCHS,
            class_weight=class_weight_dict,
            callbacks=[early_stop_head, reduce_lr],
        )

        if MODEL_BACKBONE == "efficientnet":
            print(f"\n🛠 Stage 2: fine-tuning top {FINE_TUNE_NUM_LAYERS} EfficientNet layers...")
            try:
                base_model = model.get_layer("efficientnetb0")
                for layer in base_model.layers[-FINE_TUNE_NUM_LAYERS:]:
                    layer.trainable = True
            except ValueError:
                print("⚠️ Could not find 'efficientnetb0' layer; skipping fine-tuning stage.")
            else:
                fine_tune_optimizer = tf.keras.optimizers.Adam(
                    learning_rate=FINE_TUNE_LEARNING_RATE
                )
                model.compile(
                    loss="sparse_categorical_crossentropy",
                    optimizer=fine_tune_optimizer,
                    metrics=["accuracy"],
                )

                early_stop_ft = tf.keras.callbacks.EarlyStopping(
                    monitor="val_loss",
                    patience=8,
                    restore_best_weights=True,
                )

                model.fit(
                    train_ds,
                    validation_data=val_ds,
                    epochs=HEAD_EPOCHS + FINE_TUNE_EPOCHS,
                    initial_epoch=HEAD_EPOCHS,
                    class_weight=class_weight_dict,
                    callbacks=[early_stop_ft],
                )
        else:
            print("\nℹ️ MODEL_BACKBONE != 'efficientnet'; skipping fine-tuning stage.")
    try:
        if "history" in locals() and hasattr(history, "history"):
            history_path = BASE_DIR / "train_history.json"
            with open(history_path, "w") as f:
                json.dump(history.history, f)
            print(f"\n✅ Saved training history to: {history_path}")
    except Exception as e:
        print(f"\n⚠️ Could not save training history: {e}")

    print("\n📊 Evaluating on validation set...")
    y_true = []
    y_pred = []

    for images, labels in val_ds:
        preds = model.predict(images, verbose=0)
        pred_labels = np.argmax(preds, axis=1)
        y_true.extend(labels.numpy())
        y_pred.extend(pred_labels)

    y_true = np.array(y_true)
    y_pred = np.array(y_pred)

    print("\n📊 Validation Classification Report:")
    labels = np.arange(num_classes)
    print(
        classification_report(
            y_true,
            y_pred,
            labels=labels,
            target_names=class_names,
            zero_division=0,
        )
    )
    cm_val = confusion_matrix(y_true, y_pred, labels=np.arange(num_classes))
    print_confusion_matrix(cm_val, class_names, title="Validation Confusion Matrix")
    summarize_confusions(cm_val, class_names, top_k=5)

    print("\n📊 Evaluating on TEST set...")
    y_true_test = []
    y_pred_test = []

    for images, labels in test_ds:
        preds = model.predict(images, verbose=0)
        pred_labels = np.argmax(preds, axis=1)
        y_true_test.extend(labels.numpy())
        y_pred_test.extend(pred_labels)

    y_true_test = np.array(y_true_test)
    y_pred_test = np.array(y_pred_test)

    print("\n📊 Test Classification Report:")
    labels_test = np.arange(num_classes)
    print(
        classification_report(
            y_true_test,
            y_pred_test,
            labels=labels_test,
            target_names=class_names,
            zero_division=0,
        )
    )
    cm_test = confusion_matrix(y_true_test, y_pred_test, labels=np.arange(num_classes))
    print_confusion_matrix(cm_test, class_names, title="Test Confusion Matrix")
    summarize_confusions(cm_test, class_names, top_k=5)

    model.save(DL_MODEL_PATH)
    joblib.dump(class_names, CLASS_NAMES_PATH)

    print(f"\n✅ PCB defect model saved to: {DL_MODEL_PATH}")
    print(f"✅ Class names saved to: {CLASS_NAMES_PATH}")

    try:
        print("\n📐 Computing per-class feature centroids for anomaly detection...")
        feature_extractor = build_feature_extractor(model)
        centroids = compute_class_centroids(feature_extractor, train_ds, num_classes)
        np.save(CENTROIDS_PATH, centroids, allow_pickle=True)
        print(f"✅ Class centroids saved to: {CENTROIDS_PATH}")
    except Exception as e:
        print(f"⚠️ Could not compute/save class centroids: {e}")


# -------------
# Inference helper
# -------------

def predict_single_image(image_path: str):
    """Load a single PCB image and predict its defect class, returning label and confidence."""
    if not DL_MODEL_PATH.exists() or not CLASS_NAMES_PATH.exists():
        raise FileNotFoundError(
            "Model or class names file not found. "
            "Train the model first by running this script."
        )

    model = tf.keras.models.load_model(DL_MODEL_PATH)
    class_names = joblib.load(CLASS_NAMES_PATH)

    img = tf.keras.utils.load_img(image_path, target_size=IMG_SIZE)
    x = tf.keras.utils.img_to_array(img)
    x = np.expand_dims(x, axis=0)
    x = x.astype("float32")

    preds = model.predict(x)
    pred_idx = int(np.argmax(preds, axis=1)[0])
    confidence = float(np.max(preds))

    predicted_label = class_names[pred_idx]
    return predicted_label, confidence


def predict_single_image_with_anomaly(image_path: str, anomaly_threshold: float = 10.0):
    """Predict a PCB image class and compute an anomaly score based on distance to class centroids."""
    if not DL_MODEL_PATH.exists() or not CLASS_NAMES_PATH.exists() or not CENTROIDS_PATH.exists():
        raise FileNotFoundError(
            "Model, class names, or centroids file not found. "
            "Train the model first by running this script normally."
        )

    # Load model, class names, and centroids
    model = tf.keras.models.load_model(DL_MODEL_PATH)
    class_names = joblib.load(CLASS_NAMES_PATH)
    centroids = np.load(CENTROIDS_PATH, allow_pickle=True).item()
    feature_extractor = build_feature_extractor(model)

    # Load and preprocess image (same as predict_single_image)
    img = tf.keras.utils.load_img(image_path, target_size=IMG_SIZE)
    x = tf.keras.utils.img_to_array(img)
    x = np.expand_dims(x, axis=0)
    x = x.astype("float32")

    # Softmax prediction
    probs = model.predict(x, verbose=0)[0]
    pred_idx = int(np.argmax(probs))
    confidence = float(probs[pred_idx])

    # Feature embedding
    feat = feature_extractor.predict(x, verbose=0)[0]

    # Distance to each centroid
    distances = {}
    for c, centroid in centroids.items():
        if centroid is None:
            continue
        distances[int(c)] = float(np.linalg.norm(feat - centroid))

    if not distances:
        # No centroids available; fall back to pure softmax prediction
        return {
            "predicted_label": class_names[pred_idx],
            "softmax_confidence": confidence,
            "nearest_centroid_label": class_names[pred_idx],
            "nearest_centroid_distance": None,
            "is_anomaly": False,
        }

    best_class = min(distances, key=distances.get)
    best_dist = distances[best_class]
    is_anomaly = best_dist > anomaly_threshold

    return {
        "predicted_label": class_names[pred_idx],
        "softmax_confidence": confidence,
        "nearest_centroid_label": class_names[best_class],
        "nearest_centroid_distance": best_dist,
        "is_anomaly": is_anomaly,
    }


if __name__ == "__main__":
    train_model()