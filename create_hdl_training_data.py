"""
Builds a labeled dataset of clean and buggy Verilog HDL code.

Workflow:
1. Reads clean .v files from 'clean_repo/' (from your GitHub scraper)
2. Creates buggy variants in 'bug_repo/'
3. Tokenizes both sets using preprocess_hdl()
4. Saves a labeled dataset in JSON and CSV
5. Splits into train/test sets for ML training
"""

import os
import re
import random
import json
import pandas as pd
from pathlib import Path
from sklearn.model_selection import train_test_split
from preprocess_hdl import preprocess_hdl  # Import your tokenizer function

# === CONFIGURATION ===

# Base path = current script's directory
BASE_DIR = Path(__file__).parent

CLEAN_DIR = BASE_DIR / "clean_repo"
BUG_DIR = BASE_DIR / "bug_repo"
OUTPUT_JSON = BASE_DIR / "hdl_dataset.json"
OUTPUT_CSV = BASE_DIR / "hdl_dataset.csv"
TRAIN_CSV = BASE_DIR / "hdl_train.csv"
TEST_CSV = BASE_DIR / "hdl_test.csv"

BUG_DIR.mkdir(exist_ok=True)
# ======================
os.makedirs(BUG_DIR, exist_ok=True)
# ======================


# ------------------------------
# Inject synthetic bugs into Verilog code
# ------------------------------
def inject_bug(code: str) -> str:
    """Inject a random simple bug into Verilog code."""
    bug_funcs = []

    # Replace non-blocking <= with blocking =
    if "<=" in code:
        bug_funcs.append(lambda c: c.replace("<=", "="))

    # Remove one 'end' keyword
    if "end" in code:
        bug_funcs.append(lambda c: re.sub(r"\bend\b", "", c, count=1))

    # Delete one sensitivity list signal
    if "@(" in code and ")" in code:
        bug_funcs.append(lambda c: re.sub(r"@\([^)]*\)", "@()", c, count=1))

    # Remove a semicolon
    if ";" in code:
        bug_funcs.append(lambda c: re.sub(r";", "", c, count=1))

    if not bug_funcs:
        return code  # If no bug patterns found, return unchanged

    bug_func = random.choice(bug_funcs)
    return bug_func(code)


# ------------------------------
# Process a directory of Verilog files
# ------------------------------
def process_repo(input_dir: Path, label: str):
    """Tokenize all .v files in a directory and label them."""
    dataset = []
    for file_path in input_dir.glob("*.v"):
        try:
            code = file_path.read_text(encoding="utf-8", errors="ignore")
            tokens = preprocess_hdl(code)
            token_str = " ".join([t[0] for t in tokens])  # flatten token list for ML
            dataset.append({
                "file": str(file_path),
                "code": code,
                "tokens": token_str,
                "label": label
            })
        except Exception as e:
            print(f"⚠️ Skipped {file_path.name}: {e}")
    return dataset


# ------------------------------
# Main dataset builder
# ------------------------------
def main():
    print("🔧 [Step 1] Creating buggy versions in 'bug_repo/' ...")
    for clean_file in CLEAN_DIR.glob("*.v"):
        code = clean_file.read_text(encoding="utf-8", errors="ignore")
        buggy_code = inject_bug(code)
        (BUG_DIR / clean_file.name).write_text(buggy_code, encoding="utf-8")

    print("🔍 [Step 2] Tokenizing clean HDL files ...")
    clean_data = process_repo(CLEAN_DIR, label="clean")

    print("🐞 [Step 3] Tokenizing buggy HDL files ...")
    bug_data = process_repo(BUG_DIR, label="bug")

    dataset = clean_data + bug_data
    print(f"📁 Total samples collected: {len(dataset)}")

    # Save JSON version
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(dataset, f, indent=2)
    print(f"✅ Saved structured dataset to: {OUTPUT_JSON}")

    # Convert to CSV
    df = pd.DataFrame(dataset)
    df.to_csv(OUTPUT_CSV, index=False)
    print(f"✅ Saved flat dataset to: {OUTPUT_CSV}")

    # Split into train/test
    train_df, test_df = train_test_split(df, test_size=0.2, stratify=df["label"], random_state=42)
    train_df.to_csv(TRAIN_CSV, index=False)
    test_df.to_csv(TEST_CSV, index=False)
    print(f"✅ Train/Test split complete → {len(train_df)} train, {len(test_df)} test")

    # Dataset summary
    print("\n📊 Label Distribution:")
    print(df["label"].value_counts())

    print("\n🚀 Done! You can now train your model using 'hdl_train.csv' and 'hdl_test.csv'.")


# ------------------------------
if __name__ == "__main__":
    main()