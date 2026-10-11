"""Compatibility CLI for factory.taste.pieces.panel_name; see taste/README.md."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from factory.taste.pieces.panel_name import main

if __name__ == "__main__":
    main()
