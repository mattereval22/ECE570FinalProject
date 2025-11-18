from pathlib import Path
import os
import joblib
import numpy as np

from sklearn.metrics import classification_report
from sklearn.utils.class_weight import compute_class_weight

import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.applications.efficientnet import EfficientNetB0, preprocess_input

# ------------------------------
# TensorFlow GPU / XLA settings
# ------------------------------
# On some Colab GPUs (e.g., A100) TensorFlow may auto-enable XLA JIT.
# This can trigger a flood of "Delay kernel timed out" messages from
# the XLA CUDA timer even though training is actually running.
#
# To keep training stable and avoid those warnings, explicitly disable
# XLA JIT and enable memory growth on the GPU.
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

BASE_DIR = Path(__file__).resolve().parent

# Root directory where the Kaggle PCB defects dataset is linked.
# In Colab we set this up as: /content/ECE570FinalProject/data/pcb_defects
DATA_ROOT = BASE_DIR / "data" / "pcb_defects"

# Model + metadata save paths
DL_MODEL_PATH = BASE_DIR / "pcb_defect_classifier.keras"
CLASS_NAMES_PATH = BASE_DIR / "pcb_class_names.pkl"

IMG_SIZE = (380, 380)       # higher resolution to better capture tiny PCB defects
BATCH_SIZE = 16
EPOCHS = 15                 # kept for reference (not directly used in 2‑stage training)
LEARNING_RATE = 1e-4        # base reference LR (not used directly)

# Two‑stage training hyperparameters
# (more aggressive to reduce underfitting)
HEAD_EPOCHS = 20
FINE_TUNE_EPOCHS = 25
HEAD_LEARNING_RATE = 1e-3
FINE_TUNE_LEARNING_RATE = 1e-4

# Optional debug mode to train quickly on a subset of data
DEBUG_MODE = False
DEBUG_TRAIN_STEPS = 100    # number of batches for training when debug
DEBUG_VAL_STEPS = 30       # number of batches for validation when debug

# Optional tiny overfit sanity-check mode
# When True, we train on a very small subset of the data without augmentation
# to verify that the model can overfit (reach very high training accuracy).
SANITY_OVERFIT_MODE = True
SANITY_OVERFIT_TRAIN_IMAGES = 32
SANITY_OVERFIT_VAL_IMAGES = 32


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

def build_model(
    num_classes: int,
    learning_rate: float = HEAD_LEARNING_RATE,
    use_augmentation: bool = True,
    backbone_trainable: bool = False,
):
    """Build a CNN-based image classifier using a pretrained EfficientNetB0 backbone.

    This version uses EfficientNetB0's `preprocess_input` so we don't double-normalize
    images (we feed in raw [0, 255] pixel values from the dataset and let
    `preprocess_input` handle scaling/normalization). It also allows turning
    data augmentation on/off (for tiny overfit sanity checks).
    """
    inputs = layers.Input(shape=IMG_SIZE + (3,))

    # Data augmentation pipeline applied only during training
    data_augmentation = tf.keras.Sequential(
        [
            layers.RandomFlip("horizontal"),
            layers.RandomRotation(0.05),
            layers.RandomZoom(0.1),
        ],
        name="data_augmentation",
    )

    x = inputs
    if use_augmentation:
        x = data_augmentation(x)

    # Let EfficientNetB0 handle scaling/normalization via its preprocess_input
    x = preprocess_input(x)

    # Pretrained backbone (ImageNet weights)
    base_model = EfficientNetB0(
        include_top=False,
        weights="imagenet",
        input_shape=IMG_SIZE + (3,),
        pooling=None,
    )
    base_model.trainable = backbone_trainable  # optionally start with frozen backbone for stability

    x = base_model(x, training=False)
    x = layers.GlobalAveragePooling2D(name="avg_pool")(x)

    # Classification head
    x = layers.Dense(256, activation="relu")(x)
    # Slightly lower dropout to let the model fit the small dataset more easily
    x = layers.Dropout(0.3)(x)
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

    # Build datasets (now using explicit train/val/test splits)
    train_ds, val_ds, test_ds, class_names = build_datasets()
    num_classes = len(class_names)

    # Optionally trim datasets for debug mode
    if DEBUG_MODE:
        print("DEBUG_MODE is ON: limiting number of batches for quick experiments.")
        train_ds = train_ds.take(DEBUG_TRAIN_STEPS)
        val_ds = val_ds.take(DEBUG_VAL_STEPS)
        test_ds = test_ds.take(DEBUG_VAL_STEPS)

    if SANITY_OVERFIT_MODE:
        print("SANITY_OVERFIT_MODE is ON: using tiny subset without augmentation to check overfitting.")

        # Take a small subset of train/val for a quick overfit sanity check
        train_ds = train_ds.unbatch().take(SANITY_OVERFIT_TRAIN_IMAGES).batch(BATCH_SIZE)
        val_ds = val_ds.unbatch().take(SANITY_OVERFIT_VAL_IMAGES).batch(BATCH_SIZE)

        AUTOTUNE = tf.data.AUTOTUNE
        train_ds = train_ds.cache().shuffle(1000).prefetch(buffer_size=AUTOTUNE)
        val_ds = val_ds.cache().prefetch(buffer_size=AUTOTUNE)

    # Decide training settings based on sanity overfit mode
    if SANITY_OVERFIT_MODE:
        # In sanity mode, train the whole backbone with a higher learning rate
        backbone_trainable_flag = True
        head_lr = 1e-3
        head_epochs = 40
    else:
        backbone_trainable_flag = False
        head_lr = HEAD_LEARNING_RATE
        head_epochs = HEAD_EPOCHS

    # Compute class weights to handle class imbalance
    # NOTE: We compute from the (possibly trimmed) training dataset.
    if SANITY_OVERFIT_MODE:
        class_weight_dict = None
        print("SANITY_OVERFIT_MODE: skipping class weights to make overfitting easier.")
    else:
        class_weight_dict = compute_class_weights_from_ds(train_ds, num_classes)
        print("Class weights:", class_weight_dict)

    # ------------------------
    # Stage 1: Train classifier head
    # ------------------------
    model = build_model(
        num_classes,
        learning_rate=head_lr,
        use_augmentation=not SANITY_OVERFIT_MODE,
        backbone_trainable=backbone_trainable_flag,
    )
    model.summary(print_fn=lambda x: print("   " + x))

    early_stop_head = tf.keras.callbacks.EarlyStopping(
        monitor="val_loss",
        patience=3,
        restore_best_weights=True,
    )

    print("\n🚀 Stage 1: training classifier head with frozen EfficientNet backbone...")
    history_head = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=head_epochs,
        class_weight=class_weight_dict,
        callbacks=[early_stop_head],
    )

    # ------------------------
    # Stage 2: Fine-tune top EfficientNet blocks
    # ------------------------
    if not SANITY_OVERFIT_MODE:
        base_model = model.get_layer("efficientnetb0")
        base_model.trainable = True

        # Freeze earlier layers, unfreeze only last ~100 layers for fine-tuning
        fine_tune_at = max(0, len(base_model.layers) - 100)
        for layer in base_model.layers[:fine_tune_at]:
            layer.trainable = False

        print(f"Unfreezing EfficientNet from layer index {fine_tune_at} (of {len(base_model.layers)}) for fine-tuning.")

        # Recompile with a lower learning rate for fine-tuning
        optimizer_fine = tf.keras.optimizers.Adam(learning_rate=FINE_TUNE_LEARNING_RATE)
        model.compile(
            loss="sparse_categorical_crossentropy",
            optimizer=optimizer_fine,
            metrics=["accuracy"],
        )

        early_stop_fine = tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=5,
            restore_best_weights=True,
        )

        print("\n🛠 Stage 2: fine-tuning top EfficientNet layers...")
        total_epochs = HEAD_EPOCHS + FINE_TUNE_EPOCHS
        # Continue training from where Stage 1 left off
        initial_epoch = history_head.epoch[-1] + 1 if hasattr(history_head, "epoch") else HEAD_EPOCHS
        history_fine = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=total_epochs,
            initial_epoch=initial_epoch,
            class_weight=class_weight_dict,
            callbacks=[early_stop_fine],
        )
    else:
        print("\nSkipping Stage 2 fine-tuning in SANITY_OVERFIT_MODE.")

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