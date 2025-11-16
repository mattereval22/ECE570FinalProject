"""
torch_dataset.py
----------------------------------------
Dataset utilities for HDL bug classification.

Provides:
- load_train_test: reads train/test CSVs
- BoWDataset: TF-IDF vectorization for MLP
- SequenceDataset: token id sequences for CNN
- build_vocab: simple token vocabulary
"""

import pandas as pd
import numpy as np
from pathlib import Path
from typing import List, Tuple, Dict
import torch
from torch.utils.data import Dataset, TensorDataset
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder
from collections import Counter


# ----------------------------------------------------------------------
# Data Loading
# ----------------------------------------------------------------------
def load_train_test(base_dir: Path) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Loads hdl_train.csv and hdl_test.csv from the given base directory."""
    train_df = pd.read_csv(base_dir / "hdl_train.csv")
    test_df  = pd.read_csv(base_dir / "hdl_test.csv")
    return train_df, test_df


def build_label_encoder(labels: List[str]) -> LabelEncoder:
    """Encodes string labels into numeric class IDs."""
    le = LabelEncoder()
    le.fit(labels)
    return le


# ----------------------------------------------------------------------
# Vocabulary & Encoding Utilities
# ----------------------------------------------------------------------
def basic_tokenize(token_str: str) -> List[str]:
    return token_str.split()


def build_vocab(all_token_lists: List[List[str]], min_freq: int = 1) -> Dict[str, int]:
    counter = Counter()
    for tokens in all_token_lists:
        counter.update(tokens)
    vocab = {"<PAD>": 0, "<UNK>": 1}
    for tok, freq in counter.items():
        if freq >= min_freq and tok not in vocab:
            vocab[tok] = len(vocab)
    return vocab


def encode_sequence(tokens: List[str], vocab: Dict[str, int], max_len: int) -> List[int]:
    ids = [vocab.get(tok, vocab["<UNK>"]) for tok in tokens][:max_len]
    if len(ids) < max_len:
        ids += [vocab["<PAD>"]] * (max_len - len(ids))
    return ids


# ----------------------------------------------------------------------
# Datasets for PyTorch
# ----------------------------------------------------------------------
class SequenceDataset(Dataset):
    """Token ID sequences (for CNN or RNN models)."""
    def __init__(self, df: pd.DataFrame, vocab: Dict[str, int], label_encoder: LabelEncoder, max_len: int = 256):
        self.vocab = vocab
        self.le = label_encoder
        self.max_len = max_len
        self.X_tokens = [basic_tokenize(s) for s in df["tokens"].astype(str).tolist()]
        self.y = torch.tensor(self.le.transform(df["label"].astype(str).tolist()), dtype=torch.long)

    def __len__(self):
        return len(self.y)

    def __getitem__(self, idx):
        tok = self.X_tokens[idx]
        ids = encode_sequence(tok, self.vocab, self.max_len)
        return torch.tensor(ids, dtype=torch.long), self.y[idx]


class BoWDataset(TensorDataset):
    """TF-IDF → dense tensor dataset for MLP models."""
    @staticmethod
    def build_vectorizer(train_texts: List[str]) -> TfidfVectorizer:
        vec = TfidfVectorizer(ngram_range=(1, 2), min_df=2, max_features=20000)
        vec.fit(train_texts)
        return vec

    @classmethod
    def from_frames(cls, train_df: pd.DataFrame, test_df: pd.DataFrame, label_encoder: LabelEncoder):
        vec = cls.build_vectorizer(train_df["tokens"].astype(str).tolist())
        X_train = vec.transform(train_df["tokens"].astype(str).tolist()).astype(np.float32)
        X_test = vec.transform(test_df["tokens"].astype(str).tolist()).astype(np.float32)
        y_train = label_encoder.transform(train_df["label"].astype(str).tolist())
        y_test = label_encoder.transform(test_df["label"].astype(str).tolist())

        # Convert sparse → dense for PyTorch
        X_train = torch.tensor(X_train.toarray(), dtype=torch.float32)
        X_test  = torch.tensor(X_test.toarray(), dtype=torch.float32)
        y_train = torch.tensor(y_train, dtype=torch.long)
        y_test  = torch.tensor(y_test, dtype=torch.long)

        train_ds = TensorDataset(X_train, y_train)
        test_ds  = TensorDataset(X_test, y_test)
        return train_ds, test_ds, vec