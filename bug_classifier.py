"""
bug_classifier.py
----------------------------------------
Handles AI model training and inference for HDL bug classification.
Uses token-based features for classical ML and can be extended with deep learning.
"""

import pandas as pd
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.naive_bayes import MultinomialNB
from sklearn.metrics import classification_report
import joblib
from pathlib import Path

# Paths
BASE_DIR = Path(__file__).resolve().parent.parent / "Checkpoint2"
TRAIN_PATH = BASE_DIR / "hdl_train.csv"
TEST_PATH = BASE_DIR / "hdl_test.csv"

MODEL_PATH = Path(__file__).resolve().parent / "hdl_bug_classifier.pkl"
VECTORIZER_PATH = Path(__file__).resolve().parent / "hdl_vectorizer.pkl"


def train_model():
    print("🔧 Training HDL Bug Classifier...")

    train_df = pd.read_csv(TRAIN_PATH)
    test_df = pd.read_csv(TEST_PATH)

    vectorizer = CountVectorizer()
    X_train = vectorizer.fit_transform(train_df["tokens"])
    X_test = vectorizer.transform(test_df["tokens"])

    y_train = train_df["label"]
    y_test = test_df["label"]

    clf = MultinomialNB()
    clf.fit(X_train, y_train)
    y_pred = clf.predict(X_test)

    print("\n📊 Model Evaluation:")
    print(classification_report(y_test, y_pred))

    joblib.dump(clf, MODEL_PATH)
    joblib.dump(vectorizer, VECTORIZER_PATH)
    print(f"\n✅ Model saved to: {MODEL_PATH}")
    print(f"✅ Vectorizer saved to: {VECTORIZER_PATH}")


def predict_single(code_snippet: str):
    """Load the trained model and predict bug type for a single Verilog snippet."""
    clf = joblib.load(MODEL_PATH)
    vectorizer = joblib.load(VECTORIZER_PATH)
    X = vectorizer.transform([code_snippet])
    pred = clf.predict(X)[0]
    probs = clf.predict_proba(X)[0]
    confidence = max(probs)
    return pred, confidence


if __name__ == "__main__":
    train_model()