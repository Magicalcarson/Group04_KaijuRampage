#!/usr/bin/env python3
"""Text pages for the FPGA picture (title, win, time up, evolve names) -> ../mem/overlay.mem

Each page is 160 x 120 (one overlay pixel = 2 x 2 game pixels = 4 x 4 screen pixels),
3 bits per pixel:
  0 see-through   1 ink (shadow)   2 orange   3 yellow   4 red
  5 white, blinking   6 ink, blinking
addr = page * 19200 + y * 160 + x
Pages: 0 TITLE, 1 YOU WIN! (city cleared), 2 YOU LOSE (time up), 3 BEAST!, 4 KAIJU!, 5 YOU LOSE (game over)
Text uses the same 5x7 font as the browser prototype.  Also writes overlay_preview.png.
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MEM = os.path.join(os.path.dirname(HERE), "mem")

FONT = {
    "A": [14, 17, 17, 31, 17, 17, 17], "B": [30, 17, 17, 30, 17, 17, 30], "C": [14, 17, 16, 16, 16, 17, 14],
    "D": [30, 17, 17, 17, 17, 17, 30], "E": [31, 16, 16, 30, 16, 16, 31], "G": [14, 17, 16, 23, 17, 17, 15],
    "H": [17, 17, 17, 31, 17, 17, 17], "I": [14, 4, 4, 4, 4, 4, 14], "J": [7, 2, 2, 2, 2, 18, 12],
    "K": [17, 18, 20, 24, 20, 18, 17], "L": [16, 16, 16, 16, 16, 16, 31], "M": [17, 27, 21, 21, 17, 17, 17],
    "N": [17, 17, 25, 21, 19, 17, 17], "O": [14, 17, 17, 17, 17, 17, 14], "P": [30, 17, 17, 30, 16, 16, 16],
    "R": [30, 17, 17, 30, 20, 18, 17], "S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4],
    "U": [17, 17, 17, 17, 17, 17, 14], "V": [17, 17, 17, 17, 17, 10, 4], "W": [17, 17, 17, 21, 21, 21, 10], "Y": [17, 17, 10, 4, 4, 4, 4],
    "!": [4, 4, 4, 4, 4, 0, 4], " ": [0, 0, 0, 0, 0, 0, 0],
}
W, H = 160, 120
INK, ORANGE, YELLOW, RED, WHITE_BLINK, INK_BLINK = 1, 2, 3, 4, 5, 6
PAL = {0: (0, 0, 0), 1: (17, 17, 34), 2: (255, 119, 34), 3: (255, 221, 68), 4: (221, 34, 51),
       5: (255, 255, 255), 6: (17, 17, 34)}


def text(page, s, y, scale, col, shadow):
    """Centred text; scale in overlay pixels (1 overlay pixel = 2 game pixels)."""
    w = len(s) * 6 * scale - scale
    x0 = (W - w) // 2
    for off, c in ((scale if scale > 1 else 1, shadow), (0, col)):
        for i, ch in enumerate(s):
            for r, row in enumerate(FONT[ch]):
                for b in range(5):
                    if row & (16 >> b):
                        for dy in range(scale):
                            for dx in range(scale):
                                x, yy = x0 + (i * 6 + b) * scale + dx + off, y + r * scale + dy + off
                                if 0 <= x < W and 0 <= yy < H:
                                    page[yy][x] = c


def pages():
    out = []
    p = [[0] * W for _ in range(H)]                      # 0 TITLE  (kaiju sprite goes between)
    text(p, "KAIJU", 12, 3, ORANGE, INK)
    text(p, "RAMPAGE", 37, 2, YELLOW, INK)
    text(p, "PRESS BTNC", 98, 1, WHITE_BLINK, INK_BLINK)
    out.append(p)
    p = [[0] * W for _ in range(H)]                      # 1 WIN
    text(p, "YOU WIN!", 26, 3, YELLOW, INK)
    text(p, "CITY CLEARED", 58, 2, ORANGE, INK)
    text(p, "PRESS BTNC", 84, 1, WHITE_BLINK, INK_BLINK)
    out.append(p)
    p = [[0] * W for _ in range(H)]                      # 2 TIME UP
    text(p, "YOU LOSE", 26, 3, RED, INK)
    text(p, "TIME UP", 58, 2, ORANGE, INK)
    text(p, "PRESS BTNC", 84, 1, WHITE_BLINK, INK_BLINK)
    out.append(p)
    for name in ("BEAST!", "KAIJU!"):                    # 3, 4 evolve
        p = [[0] * W for _ in range(H)]
        text(p, name, 16, 2, YELLOW, INK)
        out.append(p)
    p = [[0] * W for _ in range(H)]                      # 5 HP = 0
    text(p, "YOU LOSE", 26, 3, RED, INK)
    text(p, "GAME OVER", 58, 2, ORANGE, INK)
    text(p, "PRESS BTNC", 84, 1, WHITE_BLINK, INK_BLINK)
    out.append(p)
    return out


def main():
    ps = pages()
    with open(os.path.join(MEM, "overlay.mem"), "w", newline="\n") as f:
        f.write("\n".join(str(v) for p in ps for row in p for v in row) + "\n")
    img = Image.new("RGB", (W * 2 * len(ps) + 8 * (len(ps) - 1), H * 2), (60, 70, 60))
    for k, p in enumerate(ps):
        for y in range(H):
            for x in range(W):
                if p[y][x]:
                    for d in ((0, 0), (1, 0), (0, 1), (1, 1)):
                        img.putpixel((k * (W * 2 + 8) + x * 2 + d[0], y * 2 + d[1]), PAL[p[y][x]])
    img.save(os.path.join(HERE, "overlay_preview.png"))
    print("overlay.mem:", len(ps), "pages,", len(ps) * W * H, "entries")


if __name__ == "__main__":
    main()
