"""
AI_Analyzer/train_torch.py
----------------------------------------
Train and evaluate MLP (TF-IDF) or CNN (token sequence) models
for HDL bug classification using PyTorch.
"""

import argparse
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from sklearn.metrics import classification_report
from AI_Analyzer.torch_dataset import load_train_test, build_label_encoder, build_vocab, SequenceDataset, BoWDataset
from AI_Analyzer.models import MLPClassifier, TextCNN

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# ---------------- Training helpers ---------------- #
def train_epoch(model, loader, criterion, optimizer):
    model.train()
    total_loss = 0
    for xb, yb in loader:
        xb, yb = xb.to(DEVICE), yb.to(DEVICE)
        optimizer.zero_grad()
        logits = model(xb)
        loss = criterion(logits, yb)
        loss.backward()
        optimizer.step()
        total_loss += loss.item() * yb.size(0)
    return total_loss / len(loader.dataset)


def eval_epoch(model, loader):
    model.eval()
    preds, golds = [], []
    with torch.no_grad():
        for xb, yb in loader:
            xb = xb.to(DEVICE)
            logits = model(xb)
            yhat = logits.argmax(dim=1).cpu().numpy()
            preds.extend(yhat.tolist())
            golds.extend(yb.numpy().tolist())
    return np.array(golds), np.array(preds)


# ---------------- Main ---------------- #
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base_dir", type=str, default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--model", type=str, choices=["mlp", "cnn"], default="mlp")
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--max_len", type=int, default=256)
    args = parser.parse_args()

    base_dir = Path(args.base_dir)
    print(f"🚀 Using device: {DEVICE}")
    print(f"📂 Loading data from: {base_dir}")

    # Load CSVs
    train_df, test_df = load_train_test(base_dir)
    labels_all = sorted(set(train_df["label"]) | set(test_df["label"]))
    le = build_label_encoder(labels_all)
    num_classes = len(le.classes_)

    if args.model == "mlp":
        # TF-IDF vectorization
        train_ds, test_ds, vec = BoWDataset.from_frames(train_df, test_df, le)
        input_dim = train_ds.tensors[0].shape[1]
        model = MLPClassifier(input_dim=input_dim, num_classes=num_classes).to(DEVICE)
        train_loader = DataLoader(train_ds, batch_size=args.batch, shuffle=True)
        test_loader = DataLoader(test_ds, batch_size=args.batch)
    else:
        # Token sequence dataset for CNN
        all_tokens = [s.split() for s in train_df["tokens"].astype(str)]
        vocab = build_vocab(all_tokens)
        train_ds = SequenceDataset(train_df, vocab=vocab, label_encoder=le, max_len=args.max_len)
        test_ds  = SequenceDataset(test_df, vocab=vocab, label_encoder=le, max_len=args.max_len)
        model = TextCNN(vocab_size=len(vocab), num_classes=num_classes).to(DEVICE)
        train_loader = DataLoader(train_ds, batch_size=args.batch, shuffle=True)
        test_loader  = DataLoader(test_ds, batch_size=args.batch)

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)

    print(f"\n🧠 Training {args.model.upper()} for {args.epochs} epochs...\n")
    for epoch in range(1, args.epochs + 1):
        loss = train_epoch(model, train_loader, criterion, optimizer)
        y_true, y_pred = eval_epoch(model, test_loader)
        report = classification_report(y_true, y_pred, target_names=le.classes_, digits=3, zero_division=0)
        print(f"Epoch {epoch} | Train Loss: {loss:.4f}")
        print(report)

    # Save model weights
    out_dir = Path(__file__).resolve().parent / "torch_models"
    out_dir.mkdir(exist_ok=True)
    torch.save(model.state_dict(), out_dir / f"{args.model}_weights.pt")
    print(f"\n✅ Model saved to: {out_dir / (args.model + '_weights.pt')}\n")

# ----------------------------------------------------------------------
# Entry Point
# ----------------------------------------------------------------------
if (
    __name__ == "__main__"
    or __name__.endswith("AI_Analyzer.train_torch")
    or __name__.endswith("Checkpoint2.AI_Analyzer.train_torch")
):
    print(f"DEBUG: Forcing main() to run (__name__ = {__name__})")
    main()
else:
    print(f"⚠️ Skipping main() — running as imported module (__name__ = {__name__})")