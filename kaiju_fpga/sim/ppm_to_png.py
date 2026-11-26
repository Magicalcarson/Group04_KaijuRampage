#!/usr/bin/env python3
"""Turn the simulation screenshots shot_*.ppm (12-bit colour, 320 x 240) into PNG, 2x bigger.

Usage: python ppm_to_png.py <folder with shot_*.ppm>
"""
import glob
import os
import sys

from PIL import Image


def convert(path):
    tok = open(path).read().split()
    assert tok[0] == "P3"
    w, h, mx = int(tok[1]), int(tok[2]), int(tok[3])
    vals = [int(v) * 255 // mx for v in tok[4:4 + w * h * 3]]
    img = Image.new("RGB", (w, h))
    img.putdata([tuple(vals[i:i + 3]) for i in range(0, len(vals), 3)])
    img = img.resize((w * 2, h * 2), Image.NEAREST)
    out = os.path.splitext(path)[0] + ".png"
    img.save(out)
    return out


if __name__ == "__main__":
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    for p in sorted(glob.glob(os.path.join(folder, "shot_*.ppm"))):
        print(convert(p))
