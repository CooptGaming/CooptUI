"""
Generate assets/icon.ico from assets/banner.png (CooptGaming logo) for the .exe and window icon.
Run from patcher/ directory: python build_icon.py
Requires: pip install Pillow
"""

import os

from PIL import Image

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(SCRIPT_DIR, "assets")
BANNER = os.path.join(ASSETS, "banner.png")
ICON = os.path.join(ASSETS, "icon.ico")

SIZES = [(256, 256), (48, 48), (32, 32), (16, 16)]


def main():
    if not os.path.isfile(BANNER):
        print(f"Not found: {BANNER}")
        return 1
    img = Image.open(BANNER).convert("RGBA")
    # ICO needs one image per size; use largest as primary and append the rest
    resized = [img.resize(s, Image.Resampling.LANCZOS) for s in SIZES]
    resized[0].save(ICON, format="ICO", append_images=resized[1:])
    print(f"Created {ICON}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
