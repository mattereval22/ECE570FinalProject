import os
import shutil
import subprocess
from pathlib import Path

# ==== CONFIGURATION ====
PROJECT_DIR = Path(__file__).parent
SCRAPER_SCRIPT = PROJECT_DIR / "github_verilog_scraper.py"
DATASET_SCRIPT = PROJECT_DIR / "create_hdl_training_data.py"
CLEAN_DIR = PROJECT_DIR / "clean_repo"
SCRAPER_OUTPUT = PROJECT_DIR / "verilog_data"
BUG_DIR = PROJECT_DIR / "bug_repo"
# ========================


def run_command(description, command):
    """Run a shell command and display progress."""
    print(f"\n🚀 {description} ...")
    result = subprocess.run(command, shell=True)
    if result.returncode != 0:
        print(f"❌ Error during: {description}")
        exit(1)
    print(f"✅ {description} completed.\n")


def prepare_directories():
    """Prepare folders and ensure consistency between scraper and dataset builder."""
    # If verilog_data exists, rename it to clean_repo
    if SCRAPER_OUTPUT.exists():
        if CLEAN_DIR.exists():
            shutil.rmtree(CLEAN_DIR)
        SCRAPER_OUTPUT.rename(CLEAN_DIR)
        print(f"📁 Renamed '{SCRAPER_OUTPUT}' → '{CLEAN_DIR}' for consistency.")
    else:
        CLEAN_DIR.mkdir(exist_ok=True)
        print(f"📁 Created '{CLEAN_DIR}' folder (no prior scraper data found).")

    # Ensure bug_repo is fresh
    if BUG_DIR.exists():
        shutil.rmtree(BUG_DIR)
    BUG_DIR.mkdir(exist_ok=True)
    print(f"📁 Reset '{BUG_DIR}' for new dataset generation.")


def main():
    print("============================================")
    print("🧩 HDL Debugging Assistant – Full Pipeline")
    print("============================================")

    # Step 1. Run GitHub scraper
    run_command("Step 1: Scraping Verilog files from GitHub",
                f"python3 {SCRAPER_SCRIPT}")

    # Step 2. Prepare directories
    prepare_directories()

    # Step 3. Build dataset (tokenize + inject bugs + split)
    run_command("Step 2: Building HDL dataset with bug injection and tokenization",
                f"python3 {DATASET_SCRIPT}")

    print("============================================")
    print("🎉 Pipeline Complete!")
    print("📦 Outputs generated:")
    print(f"   - Clean HDL files: {CLEAN_DIR}")
    print(f"   - Bug-injected files: {BUG_DIR}")
    print(f"   - hdl_dataset.json / hdl_dataset.csv")
    print(f"   - hdl_train.csv / hdl_test.csv")
    print("============================================")


if __name__ == "__main__":
    main()