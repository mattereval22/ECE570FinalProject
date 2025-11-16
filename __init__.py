# Marks Checkpoint2 as a Python package
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
if str(root.parent) not in sys.path:
    sys.path.append(str(root.parent))