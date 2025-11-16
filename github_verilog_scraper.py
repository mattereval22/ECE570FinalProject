import os
import re
import requests
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import time

# ==== USER SETTINGS ====
GITHUB_TOKEN = "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"
OUTPUT_DIR = Path(__file__).parent / "clean_repo"
OUTPUT_DIR.mkdir(exist_ok=True)
SEARCH_QUERY = "extension:v language:Verilog"  # GitHub code search
MAX_FILES = 1000  # total files to download
PER_PAGE = 10   # files per request
THREADS = 8                                # Number of parallel downloads

SEARCH_URL = "https://api.github.com/search/code"
SEEN_HASHES = set()  # track content hashes to skip duplicates


# -----------------------------
# HELPERS
# -----------------------------
def is_valid_verilog(content: str) -> bool:
    """Basic sanity check for Verilog HDL code."""
    # must contain module or always; avoid C preprocessor or test logs
    return bool(re.search(r"\b(module|endmodule|always|assign|input|output)\b", content))


def file_hash(text: str) -> str:
    """Create a short hash for deduplication."""
    return hashlib.sha1(text.encode("utf-8", errors="ignore")).hexdigest()


def save_file(filename: Path, text: str):
    """Save text to file."""
    with open(filename, "w", encoding="utf-8") as f:
        f.write(text)


def fetch_file(item):
    """Download and save a single file if valid and new."""
    raw_url = item["html_url"].replace("github.com", "raw.githubusercontent.com").replace("/blob/", "/")
    try:
        r = requests.get(raw_url, headers={"Authorization": f"token {GITHUB_TOKEN}"} if GITHUB_TOKEN else {}, timeout=10)
        if r.status_code == 200:
            text = r.text
            if not is_valid_verilog(text):
                return None
            h = file_hash(text)
            if h in SEEN_HASHES:
                return None
            SEEN_HASHES.add(h)
            filename = OUTPUT_DIR / f"{h[:10]}.v"
            save_file(filename, text)
            return filename
    except Exception as e:
        return None
    return None


# -----------------------------
# MAIN SCRAPER
# -----------------------------
def scrape_github():
    print(f"🚀 Starting GitHub Verilog scrape (target={MAX_FILES})...")
    existing_files = list(OUTPUT_DIR.glob("*.v"))
    print(f"📁 {len(existing_files)} files already exist; skipping duplicates.")
    for f in existing_files:
        try:
            text = open(f, "r", encoding="utf-8", errors="ignore").read()
            SEEN_HASHES.add(file_hash(text))
        except Exception:
            pass

    files_downloaded = len(existing_files)
    page = 1

    while files_downloaded < MAX_FILES:
        print(f"🔍 Querying page {page}...")
        params = {"q": SEARCH_QUERY, "per_page": 100, "page": page}
        r = requests.get(SEARCH_URL, headers={"Authorization": f"token {GITHUB_TOKEN}"} if GITHUB_TOKEN else {}, params=params)
        if r.status_code != 200:
            print(f"⚠️ GitHub API error ({r.status_code}): {r.text}")
            break

        items = r.json().get("items", [])
        if not items:
            print("✅ No more results from GitHub.")
            break

        # Download concurrently
        with ThreadPoolExecutor(max_workers=THREADS) as executor:
            futures = [executor.submit(fetch_file, item) for item in items]
            for future in as_completed(futures):
                result = future.result()
                if result:
                    files_downloaded += 1
                    if files_downloaded % 20 == 0:
                        print(f"📦 Downloaded {files_downloaded} files...")
                    if files_downloaded >= MAX_FILES:
                        break

        page += 1
        if files_downloaded >= MAX_FILES:
            break

        time.sleep(2)  # gentle delay to respect rate limit

    print(f"✅ Finished. Total unique HDL files: {files_downloaded}")
    print(f"📁 Saved to: {OUTPUT_DIR.resolve()}")


if __name__ == "__main__":
    scrape_github()