from pathlib import Path
import os
import joblib
import numpy as np
import pandas as pd

from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report

import tensorflow as tf
from tensorflow.keras.preprocessing.text import Tokenizer
from tensorflow.keras.preprocessing.sequence import pad_sequences
from tensorflow.keras import layers, models

# -----------------------
# Paths & hyperparameters
# -----------------------

BASE_DIR = Path(__file__).resolve().parent

TRAIN_PATH = BASE_DIR / "hdl_train.csv"
TEST_PATH = BASE_DIR / "hdl_test.csv"

DL_MODEL_PATH = BASE_DIR / "dl_bug_classifier.keras"
TOKENIZER_PATH = BASE_DIR / "dl_tokenizer.pkl"

# Hyperparameters
MAX_VOCAB = 20000        # max number of tokens in vocab
MAX_LEN   = 512          # max sequence length (tokens per example)
EMB_DIM   = 128          # embedding dimension
LSTM_UNITS = 128         # BiLSTM units
BATCH_SIZE = 64
EPOCHS     = 5


# -------------
# Data loading
# -------------

def load_data(csv_path: Path):
    """Load tokens and labels from CSV and convert labels to 0/1."""
    df = pd.read_csv(csv_path)

    # tokens column is assumed to be a string of space-separated tokens
    texts = df["tokens"].astype(str).tolist()

    # Map labels to integers: clean -> 0, bug -> 1
    label_map = {"clean": 0, "bug": 1}
    labels = df["label"].map(label_map).values

    return texts, labels


def prepare_sequences(train_texts, test_texts):
    """Fit tokenizer on train_texts and convert train/test to padded sequences."""
    tokenizer = Tokenizer(num_words=MAX_VOCAB, oov_token="<UNK>")
    tokenizer.fit_on_texts(train_texts)

    train_seqs = tokenizer.texts_to_sequences(train_texts)
    test_seqs = tokenizer.texts_to_sequences(test_texts)

    X_train = pad_sequences(
        train_seqs, maxlen=MAX_LEN, padding="post", truncating="post"
    )
    X_test = pad_sequences(
        test_seqs, maxlen=MAX_LEN, padding="post", truncating="post"
    )

    return X_train, X_test, tokenizer


# -------------
# Model building
# -------------

def build_model():
    model = models.Sequential([
        # 1) Token embedding
        layers.Embedding(
            input_dim=MAX_VOCAB,
            output_dim=EMB_DIM,
            input_length=MAX_LEN,
        ),

        # 2) 1D convolution to capture local n-gram patterns
        layers.Conv1D(
            filters=128,
            kernel_size=5,
            activation="relu",
            padding="same",
        ),

        # 3) Max pooling to reduce sequence length and focus on strongest features
        layers.MaxPooling1D(pool_size=2),

        # 4) BiLSTM to capture longer-range dependencies over pooled features
        layers.Bidirectional(
            layers.LSTM(LSTM_UNITS, return_sequences=False)
        ),

        # 5) Dense + Dropout head
        layers.Dense(128, activation="relu"),
        layers.Dropout(0.5),
        layers.Dense(1, activation="sigmoid"),  # binary output: bug vs clean
    ])

    model.compile(
        loss="binary_crossentropy",
        optimizer="adam",
        metrics=["accuracy"],
    )

    return model

# -------------
# Training loop
# -------------


def train_model():
    print("🔧 Training DL HDL Bug Classifier (CNN + BiLSTM)...")
    print("CWD:", os.getcwd())
    print("BASE_DIR:", BASE_DIR)
    print("TRAIN_PATH:", TRAIN_PATH)
    print("TEST_PATH:", TEST_PATH)

    # Load data (tokens + labels) from CSV
    train_texts, train_labels = load_data(TRAIN_PATH)
    test_texts,  test_labels  = load_data(TEST_PATH)

    # Split train into train/val at the TEXT level
    X_train_texts, X_val_texts, y_train, y_val = train_test_split(
        train_texts,
        train_labels,
        test_size=0.2,
        random_state=42,
        stratify=train_labels,
    )

    # ---- Fit ONE tokenizer on *training* texts ----
    tokenizer = Tokenizer(num_words=MAX_VOCAB, oov_token="<UNK>")
    tokenizer.fit_on_texts(X_train_texts)

    def texts_to_padded(texts):
        seqs = tokenizer.texts_to_sequences(texts)
        return pad_sequences(
            seqs, maxlen=MAX_LEN, padding="post", truncating="post"
        )

    # Convert all splits using the SAME tokenizer
    X_train = texts_to_padded(X_train_texts)
    X_val   = texts_to_padded(X_val_texts)
    X_test  = texts_to_padded(test_texts)

    y_train = np.array(y_train)
    y_val   = np.array(y_val)
    y_test  = np.array(test_labels)

    # Build model
    model = build_model()
    model.summary(print_fn=lambda x: print("   " + x))

    # Early stopping on val_loss to keep best model
    early_stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_loss",
        patience=2,
        restore_best_weights=True,
    )

    # Train
    history = model.fit(
        X_train,
        y_train,
        validation_data=(X_val, y_val),
        batch_size=BATCH_SIZE,
        epochs=EPOCHS,
        callbacks=[early_stop],
    )

    # Evaluate on test set
    print("\n📊 Evaluating on test set...")
    y_pred_probs = model.predict(X_test).ravel()
    y_pred = (y_pred_probs >= 0.5).astype(int)

    print("\n📊 DL Model Evaluation (CNN + BiLSTM):")
    print(classification_report(y_test, y_pred, target_names=["clean", "bug"]))

    # Save model & tokenizer
    model.save(DL_MODEL_PATH)
    joblib.dump(tokenizer, TOKENIZER_PATH)

    print(f"\n✅ DL model saved to: {DL_MODEL_PATH}")
    print(f"✅ Tokenizer saved to: {TOKENIZER_PATH}")

def predict_single(code_tokens: str):
    """
    Predict bug vs clean for a single HDL snippet (as tokenized string).
    code_tokens: a string of space-separated tokens.
    """
    # Load trained model and tokenizer
    model = tf.keras.models.load_model(DL_MODEL_PATH)
    tokenizer = joblib.load(TOKENIZER_PATH)

    seq = tokenizer.texts_to_sequences([code_tokens])
    X = pad_sequences(seq, maxlen=MAX_LEN, padding="post", truncating="post")

    prob = model.predict(X).ravel()[0]
    pred = int(prob >= 0.5)
    confidence = float(prob if pred == 1 else 1 - prob)

    label_map_rev = {0: "clean", 1: "bug"}
    return label_map_rev[pred], confidence


if __name__ == "__main__":
    train_model()