#!/usr/bin/env python3
"""Kaiju Rampage - mock asset generator (CPE222 final project, Group04).

Every sprite and tile is drawn in code with ONE 16-colour, 12-bit palette, so the same
numbers go to the FPGA and to the browser prototype.  Outputs (next to this tools/ folder):

  mem/palette.mem        16 x 12-bit colours          ($readmemh, one value per line)
  mem/tiles.mem          16 tiles x 16x16 x 4-bit     addr = tile*256 + y*16 + x
  mem/spr_f1.mem ...     sprite frames, 4-bit index   addr = frame*W*H + y*W + x  (0 = transparent)
  mem/map.mem            64 x 48 tile map, 4-bit      addr = row*64 + col
  png/*.png              enlarged previews + mock screenshots
  web/kaiju_data.js      the same data for the browser prototype

Run:  python tools/make_assets.py
"""
import json
import os
import random
import shutil

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ----------------------------------------------------------------------------- palette
PALETTE = [  # (name, 12-bit RGB)
    ("clear", 0x000), ("ink", 0x112), ("shadow", 0x334), ("asphalt", 0x556),
    ("concrete", 0x889), ("light", 0xBBC), ("white", 0xFFF), ("grass", 0x5A3),
    ("deep", 0x263), ("lime", 0x9D3), ("water", 0x37C), ("sky", 0x6BE),
    ("yellow", 0xFD4), ("orange", 0xF72), ("red", 0xD23), ("brown", 0x853),
]
(CLEAR, INK, SHADOW, ASPHALT, CONCRETE, LIGHT, WHITE, GRASS,
 DEEP, LIME, WATER, SKY, YELLOW, ORANGE, RED, BROWN) = range(16)


def rgb(c12):
    return (((c12 >> 8) & 15) * 17, ((c12 >> 4) & 15) * 17, (c12 & 15) * 17)


# ----------------------------------------------------------------------------- tiny raster lib
def point_in_poly(x, y, pts):
    inside, j = False, len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


class Canvas:
    def __init__(self, w, h, fill=CLEAR):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def copy(self):
        c = Canvas(self.w, self.h)
        c.px = [row[:] for row in self.px]
        return c

    def set(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else CLEAR

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c, only=None):
        for y in range(self.h):
            for x in range(self.w):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1:
                    if only is None or self.px[y][x] in only:
                        self.px[y][x] = c

    def poly(self, pts, c):
        for y in range(self.h):
            for x in range(self.w):
                if point_in_poly(x + .5, y + .5, pts):
                    self.px[y][x] = c

    def line(self, x0, y0, x1, y1, c, t=1):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(int(n * 2) + 1):
            f = i / (n * 2)
            x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
            for dy in range(t):
                for dx in range(t):
                    self.set(int(x + .5) + dx - t // 2, int(y + .5) + dy - t // 2, c)

    def blob(self, cx, cy, rx, ry, body, shade):
        """Ellipse lit from the top-left: a shade crescent at the bottom-right."""
        self.ellipse(cx, cy, rx, ry, shade)
        self.ellipse(cx - .7, cy - .8, rx - .6, ry - .7, body)

    def paste(self, other, ox, oy):
        for y in range(other.h):
            for x in range(other.w):
                if other.px[y][x] != CLEAR:
                    self.set(x + ox, y + oy, other.px[y][x])

    def outline(self, c=INK):
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] == CLEAR and any(
                        self.get(x + dx, y + dy) not in (CLEAR, c)
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    add.append((x, y))
        for x, y in add:
            self.px[y][x] = c
        return self

    def transposed(self):
        c = Canvas(self.h, self.w)
        c.px = [list(col) for col in zip(*self.px)]
        return c

    def crop(self, x0, y0, w, h):
        c = Canvas(w, h)
        c.px = [row[x0:x0 + w] for row in self.px[y0:y0 + h]]
        return c

    def flat(self):
        return [v for row in self.px for v in row]


# ----------------------------------------------------------------------------- sprites
# All creatures face LEFT; the hardware mirrors them to face right (same as LAB08).
# Feet sit on the bottom row above the outline, anchor = (W/2, H-1).

def form1(frame):
    """HATCHLING 16x16 - just out of the egg, shell still on its head."""
    o = (0, -1, 1)[frame]
    bob = 0 if frame == 0 else -1
    c = Canvas(16, 16)
    c.rect(10 - o, 12, 11 - o, 14, DEEP)                      # far leg
    b = Canvas(16, 16)
    b.poly([(10.5, 9), (15, 11.5), (15, 13), (10.5, 12.5)], LIME)   # tail
    b.ellipse(15, 12.6, 1, 1, DEEP, only=[LIME])
    b.blob(9, 10.6, 4.3, 3.3, LIME, DEEP)                     # body
    b.ellipse(7.4, 11.6, 2.2, 1.7, YELLOW)                    # belly
    b.blob(6, 6.8, 4.6, 3.9, LIME, DEEP)                      # head
    for x in range(1, 12):                                    # egg shell cap, zig-zag edge
        for y in range(0, 6):
            edge = 4 if x % 2 else 5
            if y < edge and ((x + .5 - 6.2) / 4.9) ** 2 + ((y + .5 - 4.6) / 3.4) ** 2 <= 1:
                b.set(x, y, WHITE)
    b.set(8, 2, LIGHT); b.set(9, 3, LIGHT)                    # shell shading
    b.rect(3, 6, 4, 7, WHITE); b.set(3, 7, INK)               # eye
    b.set(1, 9, INK)                                          # mouth
    c.paste(b, 0, bob)
    c.rect(6 + o, 12, 7 + o, 14, LIME)                        # near leg
    return c.outline()


def form2(frame):
    """BEAST 32x32 - bigger, spikes on the back, teeth."""
    o = (0, -2, 2)[frame]
    bob = 0 if frame == 0 else -1
    c = Canvas(32, 32)
    c.rect(12 - o, 23, 14 - o, 28, DEEP)                      # far leg
    c.rect(11 - o, 29, 14 - o, 30, DEEP)
    b = Canvas(32, 32)
    for x, by in ((13, 13.5), (17, 12.8), (21, 13.5), (25, 16.5)):   # back spikes
        b.poly([(x - 2.4, by + 1.5), (x + 2.4, by + 1.5), (x + 1, by - 4.5)], ORANGE)
        b.set(x + 0.6, by - 2.5, YELLOW)
    b.poly([(21, 14.5), (30, 20), (30, 22.5), (22, 24.5)], LIME)      # tail
    b.poly([(22, 22), (30, 21.5), (30, 22.5), (22, 24.5)], DEEP)
    b.blob(17, 19, 8.6, 6.2, LIME, DEEP)                      # body
    b.ellipse(12, 15.5, 4.2, 4.2, LIME)                       # neck
    b.blob(9, 12, 6.8, 4.9, LIME, DEEP)                       # head
    b.poly([(1.5, 10), (6, 8.5), (7, 16), (1.5, 15)], LIME)   # snout
    b.ellipse(14, 21.5, 4.6, 3.2, YELLOW)                     # belly
    b.line(2, 14, 9, 15, INK)                                 # mouth
    for x, y in ((3, 15), (5, 15), (7, 16)):
        b.set(x, y, WHITE)
    b.set(3, 11, INK)                                         # nostril
    b.rect(8, 10, 9, 11, WHITE); b.set(8, 11, INK)            # eye
    b.line(7, 9, 10, 8, INK)                                  # angry brow
    b.line(13, 20, 10, 23, LIME, 2)                           # arm
    b.set(9, 24, WHITE); b.set(10, 24, WHITE)
    c.paste(b, 0, bob)
    c.ellipse(21, 23.5, 4, 3.6, LIME)                         # near leg
    c.ellipse(22, 24.5, 3, 2.6, DEEP, only=[LIME])
    c.rect(19 + o, 25, 22 + o, 28, LIME)
    c.rect(17 + o, 29, 22 + o, 30, LIME)
    c.set(17 + o, 30, WHITE); c.set(19 + o, 30, WHITE)
    return c.outline()


def ridge(c, spine, sizes):
    """Continuous row of back plates along the spine polyline, one plate per size.

    Plates are spaced at equal arc length and overlap, and each base sinks 2 px into the
    body (the body is drawn on top), so the ridge has no gaps and no floating plates.
    """
    seg = [((spine[i + 1][0] - spine[i][0]) ** 2 + (spine[i + 1][1] - spine[i][1]) ** 2) ** .5
           for i in range(len(spine) - 1)]
    total = sum(seg)

    def at(s):
        for i, length in enumerate(seg):
            if s <= length or i == len(seg) - 1:
                (x0, y0), (x1, y1) = spine[i], spine[i + 1]
                t = min(s / length, 1)
                return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, (x1 - x0) / length, (y1 - y0) / length
            s -= length

    plates = []
    for i, size in enumerate(sizes):
        x, y, dx, dy = at(total * i / (len(sizes) - 1))
        nx, ny = dy, -dx                                      # outward normal (up / right)
        hb = size * .8
        base0, base1 = (x - dx * hb, y - dy * hb), (x + dx * hb, y + dy * hb)
        tip = (x + nx * size * 1.35 + dx * size * .45, y + ny * size * 1.35 + dy * size * .45)
        sink = (x - nx * 2, y - ny * 2)
        plates.append((x, y, dx, dy, nx, ny, size, base0, tip, base1, sink))
    for x, y, dx, dy, nx, ny, size, base0, tip, base1, sink in reversed(plates):   # neck plates in front
        c.poly([base0, tip, base1, sink], ORANGE)
        c.poly([tip, base1, sink, (x, y)], RED)               # back half in shade: plates stay apart
        c.poly([(x - dx * size * .45, y - dy * size * .45),   # glowing core on the lit half
                (x + nx * size * .9 + dx * size * .3, y + ny * size * .9 + dy * size * .3),
                (x + dx * size * .1, y + dy * size * .1)], YELLOW)


def form3(frame):
    """KAIJU 48x48 - upright, glowing back plates. frame 3 = roar."""
    o = (0, -2, 2, 0)[frame]
    bob = (0, -1, -1, -1)[frame]
    roar = frame == 3
    c = Canvas(48, 48)
    c.rect(17 - o, 37, 21 - o, 44, DEEP)                      # far leg
    c.rect(15 - o, 44, 21 - o, 46, DEEP)
    b = Canvas(48, 48)
    ridge(b, [(20, 8.5), (24.5, 12.5), (28.5, 17), (31.5, 22), (33.5, 27.5), (36, 32), (40, 35.5), (43.5, 39.5)],
          [4.2, 5.6, 6.4, 6.6, 6.2, 5.4, 4.4])                # back plates (behind the body)
    b.poly([(27, 30), (37, 34), (44, 40), (46.5, 45.5), (41, 44.5), (33, 41.5), (26, 40)], DEEP)  # tail
    b.poly([(27, 29), (37, 33), (44, 39), (46, 44), (41, 42.5), (33, 39.5), (26, 38)], LIME)
    b.blob(24, 28, 9.6, 12.2, LIME, DEEP)                     # torso
    b.ellipse(19, 19.5, 6.2, 6, LIME)                         # neck
    head_dy = -2 if roar else 0
    b.blob(15, 13 + head_dy, 8.2, 6.2, LIME, DEEP)            # head
    b.poly([(3.5, 10.5 + head_dy), (10, 8 + head_dy), (12, 17.5 + head_dy), (3.5, 16.5 + head_dy)], LIME)
    b.ellipse(20, 30, 5.2, 9, YELLOW)                         # belly plates
    for y in (24, 27, 30, 33, 36):
        for x in range(12, 28):
            if b.get(x, y) == YELLOW:
                b.set(x, y, BROWN)
    if roar:                                                  # open jaw
        b.poly([(2.5, 13.5), (14, 15), (14, 18), (3, 22)], RED)
        b.poly([(2, 21), (14, 17.5), (15, 20.5), (5, 24)], LIME)
        b.line(3, 13.5, 13, 15, INK)
        for x, y in ((4, 14), (6, 14), (8, 15), (10, 15)):
            b.set(x, y, WHITE)
        for x, y in ((5, 21), (7, 20), (9, 19)):
            b.set(x, y, WHITE)
        b.rect(4, 16, 9, 18, INK)
        b.poly([(4, 16), (12, 16.5), (5, 19)], RED)
    else:
        b.line(3.5, 15, 13, 16, INK)                          # closed mouth
        for x, y in ((5, 16), (7, 16), (9, 17), (11, 17)):
            b.set(x, y, WHITE)
    b.set(5, 11 + head_dy, INK)                               # nostril
    b.rect(12, 10 + head_dy, 14, 11 + head_dy, YELLOW)        # eye
    b.set(12, 11 + head_dy, RED)
    b.line(16, 8 + head_dy, 10, 9.5 + head_dy, INK)           # brow
    b.line(20, 24, 13, 28, LIME, 3)                           # arm
    b.ellipse(12, 29.5, 2, 2, LIME)
    for x, y in ((10, 31), (12, 32), (14, 31)):
        b.set(x, y, WHITE)
    c.paste(b, 0, bob)
    c.ellipse(28, 37, 6.6, 5.6, LIME)                         # near leg
    c.ellipse(29.5, 38.5, 5, 4, DEEP, only=[LIME])
    c.ellipse(27.5, 36.5, 5.2, 4.2, LIME)
    c.rect(25 + o, 40, 30 + o, 44, LIME)
    c.rect(22 + o, 45, 31 + o, 46, LIME)
    for x in (22, 24, 26):
        c.set(x + o, 46, WHITE)
    return c.outline()


def tank(frame):
    """Army tank 16x16, top view, gun to the left."""
    c = Canvas(16, 16)
    for y0 in (2, 11):
        c.rect(1, y0, 14, y0 + 2, SHADOW)
        for x in range(1 + frame, 15, 3):
            c.set(x, y0 + 1, ASPHALT)
    c.rect(2, 5, 13, 10, DEEP)
    c.rect(2, 5, 13, 5, GRASS)
    c.ellipse(9, 7.8, 3.3, 3.3, DEEP)
    c.ellipse(8.6, 7.4, 2.4, 2.4, GRASS)
    c.rect(0, 7, 6, 8, SHADOW)
    c.set(9, 6, LIME)
    return c.outline()


def shell(frame):
    """Tank cannon shell 8x8, 2 frames (glow pulses)."""
    c = Canvas(8, 8)
    c.ellipse(4, 4, 2.7, 2.7, ORANGE)
    c.ellipse(3.6, 3.6, 1.5, 1.5, WHITE if frame else YELLOW)
    return c.outline()


def boom(frame):
    """Explosion 16x16, 2 frames."""
    c = Canvas(16, 16)
    if frame == 0:
        c.ellipse(8, 8, 6.6, 6.6, ORANGE)
        c.ellipse(8, 8, 4.4, 4.4, YELLOW)
        c.ellipse(7.5, 7.5, 2.2, 2.2, WHITE)
    else:
        for cx, cy, r in ((5, 6, 4), (11, 6, 4), (8, 11, 4.5), (8, 7, 4)):
            c.ellipse(cx, cy, r, r, CONCRETE)
        c.ellipse(8, 9, 3.5, 3, ORANGE)
        c.ellipse(8, 9.5, 1.8, 1.5, YELLOW)
        c.set(5, 4, LIGHT); c.set(6, 4, LIGHT); c.set(11, 4, LIGHT)
    return c


# ----------------------------------------------------------------------------- extra units
# Sample enemies for later.  NOT used by the game or the prototype yet; exported to extras/.
# Top view, front to the LEFT (mirror for right), same palette as everything else.

def police_car(frame):
    """Police car 16x16, 2 frames: the light bar swaps red/blue."""
    c = Canvas(16, 16)
    c.rect(2, 4, 13, 11, WHITE)                                  # white body
    for x, y in ((2, 4), (13, 4), (2, 11), (13, 11)):
        c.set(x, y, CLEAR)                                       # rounded corners
    c.rect(3, 5, 4, 10, INK)                                     # black hood
    c.rect(12, 5, 13, 10, INK)                                   # black boot
    c.rect(5, 5, 5, 10, SKY)                                     # windscreen
    c.rect(11, 5, 11, 10, SKY)                                   # rear window
    c.rect(6, 4, 10, 4, LIGHT); c.rect(6, 11, 10, 11, LIGHT)     # door edges
    top, bottom = (RED, SKY) if frame == 0 else (SKY, RED)
    c.rect(8, 5, 9, 7, top)
    c.rect(8, 8, 9, 10, bottom)                                  # light bar
    c.set(2, 5, YELLOW); c.set(2, 10, YELLOW)                    # headlights
    for x in (4, 5, 10, 11):
        c.set(x, 3, INK); c.set(x, 12, INK)                      # wheels
    return c.outline()


def tank2(frame):
    """Tank 16x16, 3 frames: two driving frames (tracks move) + one firing frame."""
    c = Canvas(16, 16)
    for y0 in (2, 11):
        c.rect(3, y0, 14, y0 + 2, SHADOW)
        for x in range(3 + frame % 2, 15, 3):
            c.set(x, y0 + 1, ASPHALT)                            # track links
    c.rect(4, 5, 13, 10, DEEP)
    c.rect(4, 5, 13, 5, GRASS)
    c.rect(12, 9, 13, 10, BROWN)                                 # engine deck
    c.ellipse(10, 7.8, 3.3, 3.3, DEEP)
    c.ellipse(9.6, 7.4, 2.4, 2.4, GRASS)                         # turret
    c.set(10, 7, WHITE)                                          # hatch
    c.rect(1, 7, 7, 8, SHADOW)                                   # long barrel
    c.outline()
    if frame == 2:                                               # muzzle flash
        c.ellipse(1, 7.5, 2.2, 2.2, ORANGE)
        c.ellipse(1, 7.5, 1.2, 1.2, YELLOW)
    return c


def helicopter(frame):
    """Attack helicopter 32x32, 2 frames: the main and tail rotors turn."""
    c = Canvas(32, 32)
    c.rect(7, 8, 18, 8, SHADOW); c.rect(7, 23, 18, 23, SHADOW)  # skids
    for x in (9, 16):
        c.rect(x, 9, x, 10, SHADOW); c.rect(x, 21, x, 22, SHADOW)
    c.rect(17, 14, 27, 17, DEEP)                                 # tail boom
    c.rect(17, 14, 27, 14, GRASS)
    c.rect(26, 11, 28, 20, DEEP)                                 # tail fin
    c.blob(12.5, 15.5, 8, 5.2, GRASS, DEEP)                      # body
    c.ellipse(6.5, 15.5, 3.4, 3.6, SKY)                          # cockpit glass
    c.set(5, 14, WHITE); c.set(6, 13, WHITE)
    c.rect(14, 12, 15, 12, ORANGE); c.rect(14, 19, 15, 19, ORANGE)   # rocket pods
    c.outline()
    if frame == 0:                                               # rotor blades (thin, drawn last)
        c.line(0, 15, 25, 15, LIGHT); c.line(12, 2, 12, 29, LIGHT)
        c.line(30, 12, 30, 19, LIGHT)
    else:
        c.line(3, 6, 21, 24, LIGHT); c.line(21, 6, 3, 24, LIGHT)
        c.line(28, 15, 31, 15, LIGHT)
    c.rect(11, 14, 13, 16, INK)                                  # rotor hub
    return c


def nuke_truck(frame):
    """Truck carrying a nuclear bomb, 32x16, 2 frames: warning beacons blink."""
    c = Canvas(32, 16)
    c.rect(10, 3, 29, 12, SHADOW)                                # flatbed trailer
    c.rect(10, 3, 29, 3, CONCRETE); c.rect(10, 12, 29, 12, CONCRETE)
    c.rect(2, 4, 8, 11, DEEP)                                    # cab
    c.rect(3, 5, 3, 10, SKY)                                     # windscreen
    c.rect(5, 5, 8, 6, GRASS)
    c.rect(9, 6, 9, 9, ASPHALT)                                  # hitch
    c.poly([(24.5, 7.5), (29, 3.5), (29, 11.5)], ASPHALT)        # bomb tail fins
    c.blob(19, 7.5, 7.6, 3.6, YELLOW, ORANGE)                    # the bomb
    for y in range(16):
        for x in range(16, 23):
            if c.get(x, y) in (YELLOW, ORANGE) and (x + y) % 4 < 2:
                c.set(x, y, INK)                                 # hazard stripe band
        for x in range(10, 14):
            if c.get(x, y) in (YELLOW, ORANGE):
                c.set(x, y, RED)                                 # red nose cone
    lamp = ORANGE if frame == 0 else RED
    for x, y in ((7, 4), (7, 11), (29, 3), (29, 12)):
        c.set(x, y, lamp)                                        # warning beacons
    return c.outline()


# ----------------------------------------------------------------------------- tiles
TILE_NAMES = ["GRASS", "ROAD_H", "ROAD_V", "ROAD_X", "PLAZA", "WATER", "EMBANK", "TREE",
              "CAR", "HOUSE", "TWR_TL", "TWR_TR", "TWR_BL", "TWR_BR", "RUBBLE", "FIRE"]
T = {n: i for i, n in enumerate(TILE_NAMES)}


def t_grass():
    c = Canvas(16, 16, GRASS)
    for x, y in ((2, 4), (9, 2), (12, 7), (5, 10), (11, 12), (1, 14), (7, 15)):
        c.set(x, y, DEEP); c.set(x + 1, y - 1, DEEP); c.set(x + 2, y, DEEP)
    return c


def t_road_h():
    c = Canvas(16, 16, ASPHALT)
    c.rect(0, 0, 15, 1, CONCRETE); c.rect(0, 0, 15, 0, LIGHT)
    c.rect(0, 14, 15, 15, CONCRETE); c.rect(0, 15, 15, 15, SHADOW)
    for x in (1, 2, 3, 4, 9, 10, 11, 12):
        c.set(x, 8, WHITE)
    for x, y in ((6, 4), (13, 11), (3, 11), (11, 4)):
        c.set(x, y, SHADOW)
    return c


def t_road_x():
    c = Canvas(16, 16, ASPHALT)
    for x0, y0 in ((0, 0), (14, 0), (0, 14), (14, 14)):
        c.rect(x0, y0, x0 + 1, y0 + 1, CONCRETE)
    for i in range(3, 13, 2):                               # zebra crossing on the left side
        c.rect(1, i, 2, i, WHITE)
    c.set(7, 7, SHADOW); c.set(10, 11, SHADOW)
    return c


def t_plaza():
    c = Canvas(16, 16, CONCRETE)
    c.rect(0, 0, 15, 0, LIGHT); c.rect(0, 0, 0, 15, LIGHT)
    c.rect(0, 8, 15, 8, LIGHT); c.rect(8, 0, 8, 15, LIGHT)
    return c


def t_water():
    c = Canvas(16, 16, WATER)
    for x, y in ((1, 3), (9, 6), (4, 11), (11, 14)):
        c.set(x, y, SKY); c.set(x + 1, y - 1, SKY); c.set(x + 2, y - 1, SKY); c.set(x + 3, y, SKY)
    return c


def t_embank():
    c = Canvas(16, 16, CONCRETE)
    c.rect(0, 0, 15, 0, LIGHT)
    c.rect(0, 7, 15, 7, SHADOW); c.rect(0, 15, 15, 15, SHADOW)
    for y0, xs in ((1, (3, 11)), (8, (7, 15))):
        for x in xs:
            c.rect(x, y0, x, y0 + 5, SHADOW)
    return c


def t_tree():
    c = t_grass()
    c.ellipse(9.5, 11, 6.2, 4, DEEP)                          # shadow on the grass
    c.ellipse(8, 7.5, 6.8, 6.6, INK)
    c.ellipse(8, 7.5, 5.9, 5.8, DEEP)
    c.ellipse(7.2, 6.7, 4.6, 4.5, LIME)
    for x, y in ((9, 9), (10, 7), (5, 9)):
        c.set(x, y, GRASS)
    c.set(5, 5, ORANGE); c.set(10, 4, ORANGE); c.set(8, 10, ORANGE)   # fruit = "edible"
    return c


def t_car():
    c = t_road_h()
    c.rect(2, 4, 13, 11, INK)
    for x, y in ((2, 4), (13, 4), (2, 11), (13, 11)):
        c.set(x, y, ASPHALT)
    c.rect(3, 5, 12, 10, RED)
    c.rect(7, 6, 10, 9, ORANGE)                                # roof
    c.rect(5, 6, 6, 9, SKY)                                    # windscreen (front = left)
    c.rect(11, 6, 11, 9, SKY)
    c.set(2, 5, YELLOW); c.set(2, 10, YELLOW)                  # headlights
    return c


def t_house():
    c = t_grass()
    c.rect(3, 14, 15, 15, DEEP)                                # shadow
    c.rect(1, 7, 14, 14, INK)
    c.rect(2, 8, 13, 13, LIGHT)
    c.poly([(0.5, 9), (15.5, 9), (12.5, 1), (3.5, 1)], INK)
    c.poly([(1.6, 8), (14.4, 8), (11.8, 2), (4.2, 2)], RED)
    c.rect(5, 2, 10, 2, ORANGE)
    for y in (4, 6):
        for x in range(2, 14):
            if c.get(x, y) == RED and (x + y) % 3:
                c.set(x, y, BROWN)
    c.rect(7, 10, 8, 13, BROWN)
    c.rect(3, 10, 4, 11, SKY); c.rect(11, 10, 12, 11, SKY)
    return c


def tower_block(rnd):
    """32x32 skyscraper drawn once, then cut into 4 tiles."""
    c = Canvas(32, 32)
    base = t_plaza()
    for ty in (0, 16):
        for tx in (0, 16):
            c.paste(base, tx, ty)
    c.rect(3, 29, 31, 31, SHADOW)                              # ground shadow
    c.rect(1, 0, 29, 29, INK)
    c.rect(2, 1, 28, 9, LIGHT)                                 # roof
    c.rect(5, 3, 10, 7, CONCRETE); c.rect(5, 7, 10, 7, SHADOW)  # AC box
    c.ellipse(21, 5, 2.6, 2.6, BROWN); c.ellipse(20.6, 4.6, 1.4, 1.4, ORANGE)  # water tank
    c.rect(2, 10, 28, 10, INK)
    c.rect(2, 11, 22, 28, CONCRETE)                            # front wall
    c.rect(23, 11, 28, 28, SHADOW)                             # side wall
    for wy in range(13, 25, 4):
        for wx in range(4, 21, 4):
            c.rect(wx, wy, wx + 1, wy + 2, YELLOW if rnd.random() < .3 else SKY)
        c.rect(25, wy, 26, wy + 2, ASPHALT)
    c.rect(10, 25, 14, 28, INK); c.rect(11, 26, 13, 28, SKY)   # entrance
    return c


def t_rubble(seed=7):
    rnd = random.Random(seed)
    c = Canvas(16, 16, CONCRETE)
    for _ in range(46):
        x, y = rnd.randrange(16), rnd.randrange(16)
        col = rnd.choice((SHADOW, SHADOW, LIGHT, BROWN, ASPHALT, INK))
        c.set(x, y, col)
        if rnd.random() < .5:
            c.set(x + 1, y, col)
    return c


def t_fire():
    c = t_rubble()
    for pts, col in (([(3, 15), (6, 4), (9, 15)], RED), ([(7, 15), (11, 2), (14, 15)], RED),
                     ([(4, 15), (6, 6), (8, 15)], ORANGE), ([(8, 15), (11, 4), (13, 15)], ORANGE),
                     ([(5, 15), (6, 9), (7, 15)], YELLOW), ([(9.5, 15), (11, 8), (12.5, 15)], YELLOW)):
        c.poly(pts, col)
    return c


def build_tiles():
    rnd = random.Random(222)
    tw = tower_block(rnd)
    road_h = t_road_h()
    tiles = [t_grass(), road_h, road_h.transposed(), t_road_x(), t_plaza(), t_water(), t_embank(),
             t_tree(), t_car(), t_house(),
             tw.crop(0, 0, 16, 16), tw.crop(16, 0, 16, 16), tw.crop(0, 16, 16, 16), tw.crop(16, 16, 16, 16),
             t_rubble(), t_fire()]
    return tiles


# ----------------------------------------------------------------------------- map
# 128 x 96 tiles = 2048 x 1536 px = 6.4 x 6.4 screens.  128 is a power of two, so the
# tile RAM address is just {row[6:0], col[6:0]} (14 bits, no multiplier); positions need 11 bits.
MW, MH = 128, 96
VROADS = list(range(3, MW, 8))              # 3, 11, ..., 123
NROADS = [4, 11, 18, 25, 32, 39]            # downtown (north of the river)
SROADS = [48, 55, 62, 69, 76, 83, 90]       # suburbs (south)
RIVER = (42, 46)                            # embankment rows; water in between (3 rows)
START = (67 * 16 + 8, 86 * 16 + 12)         # feet of the hatchling, on a vertical road
SQUARE = (52, 66, 12, 24)                   # downtown central square (whole blocks): c0, c1, r0, r1
LAKE = (28, 72, 9.5, 5.5)                   # suburb lake: centre col, centre row, radius cols, radius rows
FOREST = (92, 114, 70, 88)                  # dense trees, food for the hatchling: c0, c1, r0, r1


def build_map(seed=222):
    rnd = random.Random(seed)
    m = [[T["GRASS"]] * MW for _ in range(MH)]
    for r in range(0, RIVER[0]):
        m[r] = [T["PLAZA"]] * MW
    for c in range(MW):
        m[RIVER[0]][c] = m[RIVER[1]][c] = T["EMBANK"]
        for r in range(RIVER[0] + 1, RIVER[1]):
            m[r][c] = T["WATER"]

    def blocks(rows, r_lo, r_hi):
        edges = [r_lo - 1] + rows + [r_hi + 1]
        cols = [-1] + VROADS + [MW]
        for i in range(len(edges) - 1):
            for j in range(len(cols) - 1):
                r0, r1 = edges[i] + 1, edges[i + 1] - 1
                c0, c1 = cols[j] + 1, cols[j + 1] - 1
                if r1 >= r0 and c1 >= c0:
                    yield r0, r1, c0, c1

    # downtown: towers on plazas, a few trees
    for r0, r1, c0, c1 in blocks(NROADS, 0, RIVER[0] - 1):
        if SQUARE[0] <= c0 and c1 <= SQUARE[1] and SQUARE[2] <= r0 and r1 <= SQUARE[3]:
            for r in range(r0, r1 + 1):                   # central square: plaza and trees, no towers
                for c in range(c0, c1 + 1):
                    if (r + 2 * c) % 4 == 0:
                        m[r][c] = T["TREE"]
            continue
        for r in range(r0, r1 - 0, 3):
            for c in range(c0 + 1, c1, 3):
                if r + 1 <= r1 and c + 1 <= c1:
                    if rnd.random() < .78:
                        m[r][c], m[r][c + 1] = T["TWR_TL"], T["TWR_TR"]
                        m[r + 1][c], m[r + 1][c + 1] = T["TWR_BL"], T["TWR_BR"]
                    elif rnd.random() < .7:
                        m[r][c] = m[r + 1][c + 1] = T["TREE"]
    # suburbs: houses along the streets, parks with trees
    for r0, r1, c0, c1 in blocks(SROADS, RIVER[1] + 1, MH - 1):
        park = rnd.random() < .25
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                if park:
                    if rnd.random() < .42:
                        m[r][c] = T["TREE"]
                elif r in (r0, r1) or (r1 - r0 >= 4 and r == r0 + 3):
                    if rnd.random() < .8:
                        m[r][c] = T["HOUSE"]
                elif rnd.random() < .2:
                    m[r][c] = T["TREE"]
    # roads
    for r in NROADS + SROADS:
        for c in range(MW):
            m[r][c] = T["ROAD_H"]
    for c in VROADS:
        for r in list(range(0, RIVER[0])) + list(range(RIVER[1] + 1, MH)):
            m[r][c] = T["ROAD_X"] if r in NROADS + SROADS else T["ROAD_V"]
    # parked cars
    for r in NROADS + SROADS:
        for c in range(MW):
            if m[r][c] == T["ROAD_H"] and rnd.random() < (.18 if r < RIVER[0] else .12):
                m[r][c] = T["CAR"]
    # lake in the suburbs: only the KAIJU can wade through; houses on the shore become trees
    lc, lr, rx, ry = LAKE
    for r in range(RIVER[1] + 1, MH):
        for c in range(MW):
            d = ((c + .5 - lc) / rx) ** 2 + ((r + .5 - lr) / ry) ** 2
            if d <= 1:
                m[r][c] = T["WATER"]
            elif d <= 1.5 and m[r][c] in (T["HOUSE"], T["CAR"]):
                m[r][c] = T["TREE"] if (r + c) % 2 else T["GRASS"]
    # forest: lots of food for the hatchling
    c0, c1, r0, r1 = FOREST
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            if m[r][c] in (T["GRASS"], T["HOUSE"]):
                m[r][c] = T["TREE"] if rnd.random() < .6 else T["GRASS"]
    sc, sr = START[0] // 16, START[1] // 16
    for r in range(sr - 1, sr + 2):
        m[r][sc] = T["ROAD_V"] if r not in SROADS else T["ROAD_X"]
    return m


# ----------------------------------------------------------------------------- output helpers
def write_mem(path, values, digits=1):
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(f"{v:0{digits}X}" for v in values) + "\n")


def to_image(canvas, scale=1, bg=None):
    img = Image.new("RGBA", (canvas.w, canvas.h))
    for y in range(canvas.h):
        for x in range(canvas.w):
            v = canvas.px[y][x]
            if v == CLEAR and bg is None:
                img.putpixel((x, y), (0, 0, 0, 0))
            else:
                img.putpixel((x, y), rgb(PALETTE[v][1]) + (255,))
    if scale != 1:
        img = img.resize((canvas.w * scale, canvas.h * scale), Image.NEAREST)
    return img


def checker(w, h, s=8):
    img = Image.new("RGBA", (w, h), (40, 44, 56, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if (x // s + y // s) % 2:
                d.rectangle([x, y, x + s - 1, y + s - 1], fill=(52, 57, 72, 255))
    return img


def render_view(m, tiles, cam_x, cam_y, actors, w=320, h=240):
    """actors: list of (canvas, feet_x, feet_y, mirror) in map pixels."""
    v = Canvas(w, h)
    for y in range(h):
        wy = cam_y + y
        for x in range(w):
            wx = cam_x + x
            t = m[wy // 16][wx // 16]
            v.px[y][x] = tiles[t].px[wy % 16][wx % 16]
    for spr, fx, fy, mirror in actors:
        ox, oy = fx - spr.w // 2 - cam_x, fy - (spr.h - 1) - cam_y
        for y in range(spr.h):
            for x in range(spr.w):
                val = spr.px[y][spr.w - 1 - x if mirror else x]
                if val != CLEAR:
                    v.set(ox + x, oy + y, val)
    return v


# ----------------------------------------------------------------------------- main
def main():
    for d in ("mem", "png", "web"):
        os.makedirs(os.path.join(ROOT, d), exist_ok=True)

    sprites = {
        "f1": [form1(i) for i in range(3)],
        "f2": [form2(i) for i in range(3)],
        "f3": [form3(i) for i in range(4)],
        "tank": [tank(i) for i in range(2)],
        "boom": [boom(i) for i in range(2)],
        "shell": [shell(i) for i in range(2)],
    }
    tiles = build_tiles()
    m = build_map()

    # ---- .mem files for Vivado
    write_mem(os.path.join(ROOT, "mem", "palette.mem"), [c for _, c in PALETTE], 3)
    write_mem(os.path.join(ROOT, "mem", "tiles.mem"), [v for t in tiles for v in t.flat()])
    for key, frames in sprites.items():
        write_mem(os.path.join(ROOT, "mem", f"spr_{key}.mem"), [v for f in frames for v in f.flat()])
    write_mem(os.path.join(ROOT, "mem", "map.mem"), [v for row in m for v in row])

    # ---- memory budget
    bits = {
        "palette (LUT)": 16 * 12,
        "tile ROM": len(tiles) * 256 * 4,
        "sprite ROMs": sum(f.w * f.h * 4 for fr in sprites.values() for f in fr),
        "tile map RAM": MW * MH * 4,
        "map ROM (restart copy)": MW * MH * 4,   # BRAM init only happens at configuration time
    }
    lab08 = 512 * 768 * 7 + 9216 * 8
    total = sum(bits.values())
    print("memory (bits):", bits, "total", total, f"= {total / 1024:.1f} Kbit",
          f"| LAB08 {lab08 / 1024:.0f} Kbit")
    counts = {n: sum(row.count(i) for row in m) for n, i in T.items()}
    print("map tile counts:", counts)

    # ---- previews
    pal_img = Image.new("RGB", (16 * 40, 40))
    d = ImageDraw.Draw(pal_img)
    for i, (_, c) in enumerate(PALETTE):
        d.rectangle([i * 40, 0, i * 40 + 39, 39], fill=rgb(c))
        d.text((i * 40 + 3, 3), str(i), fill=(255, 255, 255) if i in (0, 1, 2, 3, 8, 10) else (0, 0, 0))
    pal_img.save(os.path.join(ROOT, "png", "palette.png"))

    S = 6
    rows = [("f1", "F1 HATCHLING 16x16"), ("f2", "F2 BEAST 32x32"), ("f3", "F3 KAIJU 48x48"),
            ("tank", "TANK 16x16"), ("boom", "BOOM 16x16"), ("shell", "SHELL 8x8")]
    sheet_w = max(sum(f.w * S + 12 for f in sprites[k]) for k, _ in rows) + 24
    sheet_h = sum(sprites[k][0].h * S + 34 for k, _ in rows) + 12
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (24, 27, 36, 255))
    dd = ImageDraw.Draw(sheet)
    y = 8
    for k, label in rows:
        dd.text((12, y), label, fill=(230, 230, 230))
        y += 18
        x = 12
        for f in sprites[k]:
            bg = checker(f.w * S, f.h * S, S * 2)
            bg.alpha_composite(to_image(f, S))
            sheet.paste(bg, (x, y))
            x += f.w * S + 12
        y += sprites[k][0].h * S + 16
    sheet.save(os.path.join(ROOT, "png", "sprites_sheet.png"))

    TS = 5
    tsheet = Image.new("RGBA", (8 * (16 * TS + 10) + 10, 2 * (16 * TS + 26) + 10), (24, 27, 36, 255))
    dt = ImageDraw.Draw(tsheet)
    for i, t in enumerate(tiles):
        x, yy = 10 + (i % 8) * (16 * TS + 10), 10 + (i // 8) * (16 * TS + 26)
        tsheet.paste(to_image(t, TS, bg=True), (x, yy))
        dt.text((x, yy + 16 * TS + 3), f"{i} {TILE_NAMES[i]}", fill=(230, 230, 230))
    tsheet.save(os.path.join(ROOT, "png", "tiles_sheet.png"))

    full = render_view(m, tiles, 0, 0, [(sprites["f1"][0], START[0], START[1], False)], MW * 16, MH * 16)
    to_image(full, 1, bg=True).save(os.path.join(ROOT, "png", "map_full.png"))

    # ---- three mock screenshots, one per form
    def smash(mm, cells, fire_every=2):
        for k, (r, c) in enumerate(cells):
            mm[r][c] = T["FIRE"] if k % fire_every == 0 else T["RUBBLE"]

    m1 = [row[:] for row in m]
    fx, fy = 92 * 16 + 4, 74 * 16 + 12                     # hatchling at the edge of the forest
    for r, c in ((73, 92), (74, 92), (74, 93)):
        m1[r][c] = T["GRASS"]                               # trees it has just eaten
    shot1 = render_view(m1, tiles, fx - 160, fy - 130, [
        (sprites["f1"][1], fx, fy, True), (sprites["tank"][0], fx - 12, fy - 66, False)])

    m2 = [row[:] for row in m]
    fx2, fy2 = 59 * 16 + 8, 86 * 16 + 12                   # beast in the street next to the start
    smash(m2, [(r, c) for r in range(84, 90) for c in range(52, 67) if m2[r][c] == T["HOUSE"]][::2])
    shot2 = render_view(m2, tiles, fx2 - 150, fy2 - 130, [
        (sprites["f2"][2], fx2, fy2, True), (sprites["boom"][0], fx2 + 40, fy2 - 70, False),
        (sprites["tank"][1], fx2 - 90, fy2 + 50, True)])

    m3 = [row[:] for row in m]
    fx3, fy3 = 60 * 16 + 8, 41 * 16 + 14                   # kaiju on the north bank of the river
    cells = [(r, c) for r in range(33, 39) for c in range(52, 68)
             if TILE_NAMES[m3[r][c]].startswith("TWR") or m3[r][c] in (T["CAR"], T["TREE"])]
    smash(m3, cells[::2] + cells[1::5], 3)
    shot3 = render_view(m3, tiles, fx3 - 160, fy3 - 160, [
        (sprites["f3"][3], fx3, fy3, False), (sprites["boom"][0], fx3 - 70, fy3 - 60, False),
        (sprites["boom"][1], fx3 + 60, fy3 - 90, False), (sprites["tank"][0], fx3 + 110, fy3 - 10, False)])

    # same view before the kaiju arrives (city intact) - for a before/after picture
    before3 = render_view(m, tiles, fx3 - 160, fy3 - 160, [(sprites["f3"][0], fx3, fy3, False)])

    mocks = Image.new("RGB", (3 * 640 + 40, 480 + 20), (24, 27, 36))
    for i, sh in enumerate((shot1, shot2, shot3)):
        to_image(sh, 2, bg=True).save(os.path.join(ROOT, "png", f"mock_screen_f{i + 1}.png"))
        mocks.paste(to_image(sh, 2, bg=True), (10 + i * 650, 10))
    mocks.save(os.path.join(ROOT, "png", "mock_screens.png"))

    # ---- clean, pre-scaled pictures for slides (no labels, transparent background)
    deck = os.path.join(ROOT, "png", "deck")
    os.makedirs(deck, exist_ok=True)

    def strip(frames, scale, gap):
        w = sum(f.w * scale for f in frames) + gap * (len(frames) - 1)
        hmax = max(f.h for f in frames) * scale
        img = Image.new("RGBA", (w, hmax), (0, 0, 0, 0))
        x = 0
        for f in frames:
            img.alpha_composite(to_image(f, scale), (x, (hmax - f.h * scale) // 2))
            x += f.w * scale + gap
        return img

    for k in ("f1", "f2", "f3"):
        to_image(sprites[k][0], 5).save(os.path.join(deck, f"{k}_idle_x5.png"))
    strip(sprites["f1"], 8, 24).save(os.path.join(deck, "f1_walk_x8.png"))
    strip(sprites["f2"], 5, 24).save(os.path.join(deck, "f2_walk_x5.png"))
    strip(sprites["f3"], 4, 24).save(os.path.join(deck, "f3_walk_x4.png"))
    strip(sprites["tank"] + sprites["boom"] + sprites["shell"], 6, 24).save(os.path.join(deck, "tank_boom_x6.png"))
    tg = Image.new("RGBA", (8 * 80 + 7 * 16, 2 * 80 + 16), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        tg.alpha_composite(to_image(t, 5, bg=True), ((i % 8) * 96, (i // 8) * 96))
    tg.save(os.path.join(deck, "tiles_x5.png"))
    k = 768 / (MW * 16)                                       # overview scale
    ov = to_image(full, 1, bg=True).convert("RGB").resize((768, round(MH * 16 * k)), Image.LANCZOS)
    d = ImageDraw.Draw(ov)
    cx = min(max(START[0] - 160, 0), MW * 16 - 320) * k       # same clamp as the game camera
    cy = min(max(START[1] - 8 - 120, 0), MH * 16 - 240) * k
    for i in range(3):
        d.rectangle([cx - i, cy - i, cx + 320 * k + i, cy + 240 * k + i], outline=(255, 119, 34))
    ov.save(os.path.join(deck, "map_overview.png"))
    to_image(before3, 2, bg=True).convert("RGB").save(os.path.join(deck, "city_before.png"))
    to_image(shot3, 2, bg=True).convert("RGB").save(os.path.join(deck, "city_after.png"))

    # ---- slide assets: big, crisp PNGs (nearest-neighbour upscaling) for people's own slides
    sa = os.path.join(ROOT, "slide_assets")
    if os.path.isdir(sa):
        shutil.rmtree(sa)
    for sub in ("sprites", "tiles", "map", "screens"):
        os.makedirs(os.path.join(sa, sub), exist_ok=True)
    frame_names = {"f1": ["idle", "step_a", "step_b"], "f2": ["idle", "step_a", "step_b"],
                   "f3": ["idle", "step_a", "step_b", "roar"], "tank": ["a", "b"],
                   "boom": ["flash", "smoke"], "shell": ["a", "b"]}
    labels = {"f1": "f1_hatchling", "f2": "f2_beast", "f3": "f3_kaiju", "tank": "tank",
              "boom": "explosion", "shell": "cannon_shell"}
    for key, frames in sprites.items():
        scale = max(1, 512 // max(frames[0].w, frames[0].h))          # about 512 px each
        for name, f in zip(frame_names[key], frames):
            to_image(f, scale).save(os.path.join(sa, "sprites", f"{labels[key]}_{name}.png"))
        strip(frames, scale // 2 or 1, 24).save(os.path.join(sa, "sprites", f"{labels[key]}_all_frames.png"))
    lineup = [sprites["f1"][0], sprites["f2"][0], sprites["f3"][0]]  # same scale: true relative size
    lw, lh = sum(f.w * 10 for f in lineup) + 2 * 60, 48 * 10
    li = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    x = 0
    for f in lineup:
        li.alpha_composite(to_image(f, 10), (x, lh - f.h * 10))
        x += f.w * 10 + 60
    li.save(os.path.join(sa, "sprites", "evolution_lineup_same_scale.png"))
    for i, t in enumerate(tiles):
        to_image(t, 16, bg=True).save(os.path.join(sa, "tiles", f"{i:02d}_{TILE_NAMES[i].lower()}.png"))
    ts = Image.new("RGBA", (8 * 128 + 7 * 16, 2 * 128 + 16), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        ts.alpha_composite(to_image(t, 8, bg=True), ((i % 8) * 144, (i // 8) * 144))
    ts.save(os.path.join(sa, "tiles", "all_tiles_sheet.png"))
    full_img = to_image(full, 1, bg=True).convert("RGB")
    full_img.save(os.path.join(sa, "map", "map_full_2048x1536.png"))
    full_img.resize((full_img.width * 2, full_img.height * 2), Image.NEAREST).save(
        os.path.join(sa, "map", "map_full_4096x3072.png"))
    ov.save(os.path.join(sa, "map", "map_overview_with_screen_box.png"))
    for i, sh in enumerate((shot1, shot2, shot3)):
        to_image(sh, 3, bg=True).convert("RGB").save(os.path.join(sa, "screens", f"mock_screen_form{i + 1}_960x720.png"))
    mocks.save(os.path.join(sa, "screens", "mock_screens_all_three.png"))
    pal = Image.new("RGB", (16 * 96, 96))
    dp = ImageDraw.Draw(pal)
    for i, (_, c) in enumerate(PALETTE):
        dp.rectangle([i * 96, 0, i * 96 + 95, 95], fill=rgb(c))
    pal.save(os.path.join(sa, "palette_16_colours.png"))
    with open(os.path.join(sa, "palette.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("index  name       12-bit  24-bit\n")
        for i, (n, c) in enumerate(PALETTE):
            f.write(f"{i:>5}  {n:<9}  {c:03X}     #{'%02X%02X%02X' % rgb(c)}\n")
    with open(os.path.join(sa, "README.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(
            "Kaiju Rampage - images for slides (generated by tools/make_assets.py)\n\n"
            "sprites/  every frame of every sprite, about 512 px, transparent background\n"
            "          *_all_frames.png = all frames of one sprite in a row\n"
            "          evolution_lineup_same_scale.png = the 3 forms at the same scale (real size ratio)\n"
            "tiles/    the 16 map tiles, 256 x 256 each, plus all_tiles_sheet.png\n"
            "map/      the whole 128 x 96 tile map at 1x and 2x, and an overview with the 320 x 240 screen box\n"
            "screens/  mock screenshots of the three forms, 960 x 720\n"
            "palette_16_colours.png / palette.txt  the 16-colour 12-bit palette\n\n"
            "Tip: these are pixel art. If your slide app blurs them when you enlarge them, turn off\n"
            "image smoothing, or use the file closest to the size you need instead of stretching.\n")
    shutil.make_archive(os.path.join(ROOT, "Kaiju_Rampage_slide_assets"), "zip", sa)

    # ---- extra units (samples only, not loaded by the game): extras/png, extras/mem
    extras = {
        "police_car": ("POLICE CAR 16x16", [police_car(i) for i in range(2)], ["lights_a", "lights_b"]),
        "tank_v2": ("TANK v2 16x16", [tank2(i) for i in range(3)], ["drive_a", "drive_b", "fire"]),
        "helicopter": ("HELICOPTER 32x32", [helicopter(i) for i in range(2)], ["rotor_a", "rotor_b"]),
        "nuke_truck": ("NUKE TRUCK 32x16", [nuke_truck(i) for i in range(2)], ["beacon_a", "beacon_b"]),
    }
    ex = os.path.join(ROOT, "extras")
    if os.path.isdir(ex):
        shutil.rmtree(ex)
    os.makedirs(os.path.join(ex, "png"))
    os.makedirs(os.path.join(ex, "mem"))
    for key, (label, frames, names) in extras.items():
        scale = max(1, 384 // max(frames[0].w, frames[0].h))
        for name, f in zip(names, frames):
            to_image(f, scale).save(os.path.join(ex, "png", f"{key}_{name}.png"))
        strip(frames, scale // 2, 24).save(os.path.join(ex, "png", f"{key}_all_frames.png"))
        write_mem(os.path.join(ex, "mem", f"spr_{key}.mem"), [v for f in frames for v in f.flat()])
    # preview sheet: every frame at 8x, then a size line-up next to the three kaiju forms at 5x
    S8, rows_h = 8, []
    for key, (label, frames, names) in extras.items():
        rows_h.append(frames[0].h * S8 + 44)
    lineup_units = [sprites["f1"][0], sprites["f2"][0], sprites["f3"][0]] + [v[1][0] for v in extras.values()]
    line_h = max(f.h for f in lineup_units) * 5 + 44
    sheet_w = max(sum(f.w * S8 + 16 for f in v[1]) for v in extras.values()) + 32
    sheet_w = max(sheet_w, sum(f.w * 5 + 24 for f in lineup_units) + 32)
    sh = Image.new("RGBA", (sheet_w, sum(rows_h) + line_h + 24), (24, 27, 36, 255))
    dsh = ImageDraw.Draw(sh)
    y = 12
    for key, (label, frames, names) in extras.items():
        dsh.text((16, y), label + "  (" + ", ".join(names) + ")", fill=(230, 230, 230))
        x = 16
        for f in frames:
            bg = checker(f.w * S8, f.h * S8, S8 * 2)
            bg.alpha_composite(to_image(f, S8))
            sh.paste(bg, (x, y + 18))
            x += f.w * S8 + 16
        y += frames[0].h * S8 + 44
    dsh.text((16, y), "SIZE vs KAIJU FORMS (same scale)", fill=(230, 230, 230))
    base_y, x = y + 18 + max(f.h for f in lineup_units) * 5, 16
    for f in lineup_units:
        sh.alpha_composite(to_image(f, 5), (x, base_y - f.h * 5))
        x += f.w * 5 + 24
    sh.save(os.path.join(ex, "units_sheet.png"))
    with open(os.path.join(ex, "README.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(
            "Kaiju Rampage - sample enemy units (NOT in the game yet)\n\n"
            "units_sheet.png      every frame + size next to the three kaiju forms\n"
            "png/                 each frame about 384 px, transparent; *_all_frames.png = one row\n"
            "mem/spr_*.mem        4-bit palette index per pixel, addr = frame*W*H + y*W + x, 0 = transparent\n\n"
            "police_car  16x16  2 frames  light bar red/blue\n"
            "tank_v2     16x16  3 frames  drive a, drive b, fire (muzzle flash)\n"
            "helicopter  32x32  2 frames  rotor turns 45 degrees\n"
            "nuke_truck  32x16  2 frames  warning beacons blink\n\n"
            "All face LEFT (mirror in hardware for right), same 16-colour palette as the game.\n")
    shutil.make_archive(os.path.join(ROOT, "Kaiju_Rampage_new_units"), "zip", ex)

    # ---- data for the browser prototype
    hexs = lambda vals: "".join(f"{v:X}" for v in vals)
    data = {
        "palette": ["#%03X" % c for _, c in PALETTE],
        "tileNames": TILE_NAMES,
        "tiles": [hexs(t.flat()) for t in tiles],
        "sprites": {k: {"w": f[0].w, "h": f[0].h, "frames": [hexs(x.flat()) for x in f]} for k, f in sprites.items()},
        "map": {"w": MW, "h": MH, "data": hexs(v for row in m for v in row)},
        "start": START,
        "memory": {"parts": bits, "total": total, "lab08": lab08},
        "counts": counts,
    }
    with open(os.path.join(ROOT, "web", "kaiju_data.js"), "w", newline="\n") as f:
        f.write("// generated by tools/make_assets.py - do not edit by hand\n")
        f.write("window.KAIJU_DATA = " + json.dumps(data, separators=(",", ":")) + ";\n")
    print("done ->", ROOT)


if __name__ == "__main__":
    main()
