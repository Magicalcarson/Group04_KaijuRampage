#!/usr/bin/env python3
"""Sprites for the enemies, explosions and power-ups -> ../mem/*.mem  (+ units_preview.png)

  spr_enemy.mem   4 types x 2 frames, each in a 32x32 cell, top-left aligned, 4-bit index
                  addr = type*2048 + frame*1024 + y*32 + x
                  type 0 police car 16x16 · 1 tank 16x16 · 2 helicopter 32x32 · 3 nuke truck 32x16
  spr_boom.mem    2 frames 16x16          addr = frame*256 + y*16 + x
  spr_items.mem   3 items 16x16           addr = item*256 + y*16 + x   (0 heal, 1 speed, 2 shield)

The vehicle drawings come from kaiju_mock/tools/make_assets.py (same palette).
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "kaiju_mock", "tools"))
import make_assets as A  # noqa: E402

MEM = os.path.join(os.path.dirname(HERE), "mem")


def badge():
    """Light round badge with an ink ring, so an item stands out on any tile."""
    c = A.Canvas(16, 16)
    c.ellipse(7.5, 7.5, 7.4, 7.4, A.INK)
    c.ellipse(7.5, 7.5, 6.3, 6.3, A.WHITE)
    c.ellipse(8.2, 8.4, 5.6, 5.6, A.LIGHT, only=[A.WHITE])
    return c


def item_heal():
    c = badge()
    c.ellipse(5.6, 6.2, 2.4, 2.4, A.RED)
    c.ellipse(9.4, 6.2, 2.4, 2.4, A.RED)
    c.poly([(3.1, 6.8), (12, 6.8), (7.5, 12.4)], A.RED)
    c.set(5, 5, A.WHITE)
    return c


def item_speed():
    c = badge()
    c.poly([(8.8, 2.6), (4.3, 8.6), (7.4, 8.6), (6.2, 13.2), (11.4, 6.6), (8.3, 6.6), (9.8, 2.6)], A.ORANGE)
    c.poly([(8.6, 3.6), (5.4, 8.0), (7.6, 8.0)], A.YELLOW)
    return c


def item_shield():
    c = badge()
    c.poly([(3.6, 3.6), (11.4, 3.6), (11.4, 8.0), (7.5, 12.6), (3.6, 8.0)], A.WATER)
    c.poly([(4.6, 4.5), (7.5, 4.5), (7.5, 11.2), (4.6, 7.8)], A.SKY)
    c.rect(7, 5, 7, 10, A.WHITE)
    return c


def cell(canvas, w=32, h=32):
    out = A.Canvas(w, h)
    for y in range(canvas.h):
        for x in range(canvas.w):
            out.set(x, y, canvas.get(x, y))
    return out


def main():
    enemies = [
        [A.police_car(0), A.police_car(1)],
        [A.tank2(0), A.tank2(1)],
        [A.helicopter(0), A.helicopter(1)],
        [A.nuke_truck(0), A.nuke_truck(1)],
    ]
    vals = []
    for frames in enemies:
        for f in frames:
            vals += cell(f).flat()
    A.write_mem(os.path.join(MEM, "spr_enemy.mem"), vals)

    booms = [A.boom(0), A.boom(1)]
    A.write_mem(os.path.join(MEM, "spr_boom.mem"), [v for b in booms for v in b.flat()])

    items = [item_heal(), item_speed(), item_shield()]
    A.write_mem(os.path.join(MEM, "spr_items.mem"), [v for it in items for v in it.flat()])

    # preview, 6x
    pics = [f for fr in enemies for f in fr] + booms + items
    S = 6
    wsum = sum(p.w * S + 12 for p in pics)
    img = Image.new("RGBA", (wsum + 12, 32 * S + 24), (34, 38, 52, 255))
    x = 12
    for p in pics:
        img.alpha_composite(A.to_image(p, S), (x, 12))
        x += p.w * S + 12
    img.save(os.path.join(HERE, "units_preview.png"))
    print("spr_enemy.mem", len(vals), "· spr_boom.mem 512 · spr_items.mem 768")


if __name__ == "__main__":
    main()
