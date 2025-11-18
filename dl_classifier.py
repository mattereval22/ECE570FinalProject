from pathlib import Path
import os
import joblib
import numpy as np

from sklearn.metrics import classification_report
from sklearn.utils.class_weight import compute_class_weight

import tensorflow as tf
from tensorflow.keras import layers, models

# -----------------------
# Paths & hyperparameters
# -----------------------

BASE_DIR = Path(__file__).resolve().parent

# Root directory where the Kaggle PCB defects dataset is linked.
# In Colab we set this up as: /content/ECE570FinalProject/data/pcb_defects
DATA_ROOT = BASE_DIR / "data" / "pcb_defects"

# Model + metadata save paths
DL_MODEL_PATH = BASE_DIR / "pcb_defect_classifier.keras"
CLASS_NAMES_PATH = BASE_DIR / "pcb_class_names.pkl"

# Image / training hyperparameters
IMG_SIZE = (224, 224)       # standard for many pretrained backbones
BATCH_SIZE = 32
EPOCHS = 15
LEARNING_RATE = 1e-4

# Optional debug mode to train quickly on a subset of data
DEBUG_MODE = False
DEBUG_TRAIN_STEPS = 100    # number of batches for training when debug
DEBUG_VAL_STEPS = 30       # number of batches for validation when debug


# -------------
# Data loading
# -------------

def build_datasets():
    """
    Build tf.data datasets for training, validation, and test from directories of images.

    Expected directory structure under DATA_ROOT:
        pcb_defects/
            train/
                class_0_name/
                    img001.png
                    ...
                class_1_name/
                    ...
                ...
            val/
                class_0_name/
                    ...
                ...
            test/
                class_0_name/
                    ...
                ...

    If your Kaggle dataset uses a slightly different naming scheme (e.g., "valid" instead of
    "val"), adjust the directory names below accordingly.
    """
    if not DATA_ROOT.exists():
        raise FileNotFoundError(
            f"DATA_ROOT does not exist: {DATA_ROOT}. "
            "Make sure you downloaded the Kaggle PCB dataset and placed/symlinked it as data/pcb_defects."
        )

    train_dir = DATA_ROOT / "train"
    val_dir = DATA_ROOT / "val"
    test_dir = DATA_ROOT / "test"

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

    # (Optional) sanity check that val/test have the same classes
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
    """
    Compute class weights from a (image, label) dataset by iterating through it once.
    """
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


# -------------
# Model building
# -------------

def build_model(num_classes: int):
    """
    Build a CNN-based image classifier using a pretrained EfficientNetB0 backbone.
    """
    inputs = layers.Input(shape=IMG_SIZE + (3,))

    # Basic rescaling
    x = layers.Rescaling(1.0 / 255)(inputs)

    # Pretrained backbone (ImageNet weights)
    base_model = tf.keras.applications.EfficientNetB0(
        include_top=False,
        input_tensor=x,
        pooling="avg",
        weights="imagenet",
    )
    base_model.trainable = False  # start with frozen backbone for stability

    # Classification head
    x = layers.Dense(256, activation="relu")(base_model.output)
    x = layers.Dropout(0.5)(x)
    outputs = layers.Dense(num_classes, activation="softmax")(x)

    model = models.Model(inputs=inputs, outputs=outputs)

    optimizer = tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE)
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

    # Build datasets (now using explicit train/val/test splits)
    train_ds, val_ds, test_ds, class_names = build_datasets()
    num_classes = len(class_names)

    # Optionally trim datasets for debug mode
    if DEBUG_MODE:
        print("DEBUG_MODE is ON: limiting number of batches for quick experiments.")
        train_ds = train_ds.take(DEBUG_TRAIN_STEPS)
        val_ds = val_ds.take(DEBUG_VAL_STEPS)
        test_ds = test_ds.take(DEBUG_VAL_STEPS)

    # Compute class weights to handle class imbalance
    # NOTE: We compute from the (possibly trimmed) training dataset.
    class_weight_dict = compute_class_weights_from_ds(train_ds, num_classes)
    print("Class weights:", class_weight_dict)

    # Build model
    model = build_model(num_classes)
    model.summary(print_fn=lambda x: print("   " + x))

    # Early stopping + checkpoint
    early_stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_loss",
        patience=3,
        restore_best_weights=True,
    )

    # Train
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS,
        class_weight=class_weight_dict,
        callbacks=[early_stop],
    )

    # Evaluate on validation set and print classification report
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
    print(classification_report(y_true, y_pred, target_names=class_names))

    # Evaluate on held-out test set
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
    print(classification_report(y_true_test, y_pred_test, target_names=class_names))

    # Save model + class names
    model.save(DL_MODEL_PATH)
    joblib.dump(class_names, CLASS_NAMES_PATH)

    print(f"\n✅ PCB defect model saved to: {DL_MODEL_PATH}")
    print(f"✅ Class names saved to: {CLASS_NAMES_PATH}")


# -------------
# Inference helper
# -------------

def predict_single_image(image_path: str):
    """
    Load a single PCB image and predict its defect class.

    Parameters
    ----------
    image_path : str
        Path to the image file to classify.

    Returns
    -------
    (predicted_label: str, confidence: float)
    """
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
    x = x.astype("float32") / 255.0

    preds = model.predict(x)
    pred_idx = int(np.argmax(preds, axis=1)[0])
    confidence = float(np.max(preds))

    predicted_label = class_names[pred_idx]
    return predicted_label, confidence


if __name__ == "__main__":
    train_model()