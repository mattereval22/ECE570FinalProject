# AI_Analyzer/ablation.py
import argparse
from pathlib import Path
import pandas as pd
import re

from AI_Analyzer.train_torch import main as train_main

# ---- Simple ablation transforms on the tokens column ----
def keep_only_keywords_ops(df: pd.DataFrame) -> pd.DataFrame:
    KW = {"always","assign","begin","end","posedge","negedge","if","else","case","endcase","module","endmodule","wire","reg"}
    OPS = {"<=","=","+","-","*",";","@", "(",")","[","]",":"}
    def filt(s: str):
        toks = s.split()
        kept = [t for t in toks if (t in KW or t in OPS)]
        return " ".join(kept) if kept else "UNK"
    df2 = df.copy()
    df2["tokens"] = df2["tokens"].astype(str).apply(filt)
    return df2

def remove_keywords_ops(df: pd.DataFrame) -> pd.DataFrame:
    KW = {"always","assign","begin","end","posedge","negedge","if","else","case","endcase","module","endmodule","wire","reg"}
    OPS = {"<=","=","+","-","*",";","@", "(",")","[","]",":"}
    def filt(s: str):
        toks = s.split()
        kept = [t for t in toks if (t not in KW and t not in OPS)]
        return " ".join(kept) if kept else "UNK"
    df2 = df.copy()
    df2["tokens"] = df2["tokens"].astype(str).apply(filt)
    return df2

def shuffle_tokens(df: pd.DataFrame, seed=42) -> pd.DataFrame:
    import random
    rnd = random.Random(seed)
    def shuf(s: str):
        toks = s.split()
        rnd.shuffle(toks)
        return " ".join(toks)
    df2 = df.copy()
    df2["tokens"] = df2["tokens"].astype(str).apply(shuf)
    return df2

def run_ablation(kind: str, base_dir: Path):
    train_df = pd.read_csv(base_dir / "hdl_train.csv")
    test_df  = pd.read_csv(base_dir / "hdl_test.csv")

    if kind == "keep_kw_ops":
        train_df = keep_only_keywords_ops(train_df)
        test_df  = keep_only_keywords_ops(test_df)
    elif kind == "remove_kw_ops":
        train_df = remove_keywords_ops(train_df)
        test_df  = remove_keywords_ops(test_df)
    elif kind == "shuffle":
        train_df = shuffle_tokens(train_df, seed=42)
        test_df  = shuffle_tokens(test_df, seed=42)
    else:
        raise ValueError("Unknown ablation kind")

    # Save temporary copies, then call train_torch script against them
    tmp_dir = base_dir / f"_ablation_{kind}"
    tmp_dir.mkdir(exist_ok=True)
    train_df.to_csv(tmp_dir / "hdl_train.csv", index=False)
    test_df.to_csv(tmp_dir / "hdl_test.csv", index=False)

    # Reuse trainer with overridden base_dir
    import sys
    sys.argv = ["train_torch", "--base_dir", str(tmp_dir), "--model", "mlp", "--epochs", "6"]
    train_main()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=["keep_kw_ops","remove_kw_ops","shuffle"], required=True)
    parser.add_argument("--base_dir", type=str, default=str(Path(__file__).resolve().parents[1] / "Checkpoint2"))
    args = parser.parse_args()
    run_ablation(args.kind, Path(args.base_dir))