#!/usr/bin/env python3
"""Make the StockTwib profile pictures (800x800, safe for YouTube's circle crop).

    python3 tools/brand_assets.py   -> brand/profile-*.png and brand/profile-preview.png

Same palette and typeface as the videos: deep navy, signal yellow, market red/green, Inter Black.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from shortkit import FONT_DIR, ROOT  # noqa: E402

BRAND = "StockTwib"
OUT = os.path.join(ROOT, "brand")
SS = 4                      # draw 4x and downsample for smooth edges
SIZE = 800
N = SIZE * SS
NAVY_HI, NAVY_LO = (28, 42, 84), (7, 10, 19)
YELLOW, RED, GREEN, WHITE = (255, 214, 10), (255, 77, 77), (34, 211, 102), (244, 246, 250)


def font(size):
    return ImageFont.truetype(os.path.join(FONT_DIR, "Inter-Black.otf"), int(size))


def background():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    r = np.sqrt((xx - N * 0.5) ** 2 + (yy - N * 0.42) ** 2) / (N * 0.72)
    t = np.clip(r, 0, 1)[..., None]
    img = np.array(NAVY_HI, np.float32) * (1 - t) + np.array(NAVY_LO, np.float32) * t
    return Image.fromarray(img.astype(np.uint8), "RGB")


def arrow(d, pts, color, width, head):
    """A chart line that ends in an arrowhead pointing along its last segment."""
    pts = [(x * N, y * N) for x, y in pts]
    (x1, y1), (x2, y2) = pts[-2], pts[-1]
    v = np.array([x2 - x1, y2 - y1])
    v /= np.linalg.norm(v)
    nrm = np.array([-v[1], v[0]])
    tip = np.array([x2, y2]) + v * head * 0.55
    base = np.array([x2, y2]) - v * head * 0.45
    d.line(pts[:-1] + [tuple(base)], fill=color, width=int(width), joint="curve")
    for p in pts[:-1]:  # round the joints and the start cap
        d.ellipse((p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2), fill=color)
    d.polygon([tuple(tip), tuple(base + nrm * head * 0.62), tuple(base - nrm * head * 0.62)], fill=color)


def candle(d, cx, wick, body, color, w=0.115):
    d.rounded_rectangle((N * (cx - 0.012), N * wick[0], N * (cx + 0.012), N * wick[1]), radius=N * 0.012, fill=color)
    d.rounded_rectangle((N * (cx - w / 2), N * body[0], N * (cx + w / 2), N * body[1]), radius=N * 0.022, fill=color)


def centered(d, y, s, f, fill):
    d.text((N / 2, N * y), s, font=f, fill=fill, anchor="mm")


def mark_candles():
    """Icon only: three rising candles and an up-arrow. Reads even at YouTube's tiny sizes."""
    img = background()
    d = ImageDraw.Draw(img)
    candle(d, 0.31, (0.50, 0.78), (0.56, 0.72), RED)
    candle(d, 0.50, (0.38, 0.72), (0.44, 0.64), GREEN)
    candle(d, 0.69, (0.25, 0.62), (0.31, 0.55), YELLOW)
    return img


def monogram():
    """'ST' with a chart arrow climbing underneath, and the red 'live' dot from the videos."""
    img = background()
    d = ImageDraw.Draw(img)
    centered(d, 0.43, "ST", font(N * 0.36), WHITE)
    arrow(d, [(0.22, 0.785), (0.39, 0.695), (0.52, 0.745), (0.75, 0.62)], YELLOW, N * 0.046, N * 0.13)
    d.ellipse((N * 0.735, N * 0.215, N * 0.805, N * 0.285), fill=RED)
    return img


def wordmark():
    """Stacked name for places that show the picture bigger (TikTok, Instagram, banners)."""
    img = background()
    d = ImageDraw.Draw(img)
    f = font(N * 0.205)
    centered(d, 0.40, "STOCK", f, WHITE)
    centered(d, 0.585, "TWIB", f, YELLOW)
    arrow(d, [(0.25, 0.80), (0.40, 0.75), (0.50, 0.785), (0.73, 0.70)], GREEN, N * 0.03, N * 0.085)
    return img


def circle(img, size):
    small = img.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    out = Image.new("RGB", (size, size), (255, 255, 255))
    out.paste(small, (0, 0), mask.resize((size, size), Image.LANCZOS))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    variants = [("candles", mark_candles()), ("monogram", monogram()), ("wordmark", wordmark())]
    sheet = Image.new("RGB", (3 * 460, 640), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    label = ImageFont.truetype(os.path.join(FONT_DIR, "Inter-SemiBold.otf"), 22)
    for i, (name, big) in enumerate(variants):
        final = big.resize((SIZE, SIZE), Image.LANCZOS)
        final.save(os.path.join(OUT, f"profile-{name}.png"))
        x = i * 460 + 30
        sheet.paste(circle(big, 400), (x, 20))
        sheet.paste(circle(big, 98), (x, 450))     # YouTube channel page size
        sheet.paste(circle(big, 40), (x + 130, 480))  # comments / sidebar size
        d.text((x, 600), f"{i + 1}. {name}", font=label, fill=(30, 30, 40))
    sheet.save(os.path.join(OUT, "profile-preview.png"))
    print("Done:", OUT)


if __name__ == "__main__":
    main()
