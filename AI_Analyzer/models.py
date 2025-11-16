# AI_Analyzer/models.py
import torch
import torch.nn as nn
import torch.nn.functional as F

class MLPClassifier(nn.Module):
    def __init__(self, input_dim: int, num_classes: int, hidden=(512, 256), p=0.2):
        super().__init__()
        h1, h2 = hidden
        self.net = nn.Sequential(
            nn.Linear(input_dim, h1), nn.ReLU(), nn.Dropout(p),
            nn.Linear(h1, h2), nn.ReLU(), nn.Dropout(p),
            nn.Linear(h2, num_classes)
        )

    def forward(self, x):
        return self.net(x)  # logits

class TextCNN(nn.Module):
    """
    1D CNN over token id sequences with an embedding layer + global max pool.
    """
    def __init__(self, vocab_size: int, num_classes: int, emb_dim: int = 128,
                 kernel_sizes=(3,5,7), num_channels=(128,128,128), p=0.3):
        super().__init__()
        self.emb = nn.Embedding(vocab_size, emb_dim, padding_idx=0)
        self.convs = nn.ModuleList([
            nn.Conv1d(emb_dim, c, k, padding=k//2) for k, c in zip(kernel_sizes, num_channels)
        ])
        self.dropout = nn.Dropout(p)
        self.fc = nn.Linear(sum(num_channels), num_classes)

    def forward(self, x_ids):  # (B, L)
        x = self.emb(x_ids)            # (B, L, E)
        x = x.transpose(1, 2)          # (B, E, L)
        feats = [F.relu(conv(x)).max(dim=2).values for conv in self.convs]  # list of (B, C)
        h = torch.cat(feats, dim=1)    # (B, sumC)
        h = self.dropout(h)
        return self.fc(h)              # logits