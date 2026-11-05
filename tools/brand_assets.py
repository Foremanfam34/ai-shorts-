#!/usr/bin/env python3
"""Make the Stock Geek profile pictures (800x800, safe for YouTube's circle crop) and the
YouTube banner (2560x1440, text inside the 1546x423 area every device shows).

    python3 tools/brand_assets.py   -> brand/profile-*.png, brand/youtube-banner.png, brand/preview.png

Same palette and typeface as the videos: deep navy, signal yellow, market red/green, Inter Black.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from shortkit import FONT_DIR, ROOT  # noqa: E402

BRAND = "Stock Geek"
OUT = os.path.join(ROOT, "brand")
SS = 4                      # draw 4x and downsample for smooth edges
SIZE = 800
N = SIZE * SS
NAVY_HI, NAVY_LO = (28, 42, 84), (7, 10, 19)
YELLOW, RED, GREEN, WHITE = (255, 214, 10), (255, 77, 77), (34, 211, 102), (244, 246, 250)


def font(size, weight="Black"):
    return ImageFont.truetype(os.path.join(FONT_DIR, f"Inter-{weight}.otf"), int(size))


def background(w=N, h=N, cy=0.42):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt((xx - w * 0.5) ** 2 + (yy - h * cy) ** 2) / (max(w, h) * 0.72)
    t = np.clip(r, 0, 1)[..., None]
    img = np.array(NAVY_HI, np.float32) * (1 - t) + np.array(NAVY_LO, np.float32) * t
    return Image.fromarray(img.astype(np.uint8), "RGB")


def arrow(d, pts, color, width, head, scale=N):
    """A chart line that ends in an arrowhead pointing along its last segment."""
    pts = [(x * scale, y * scale) for x, y in pts]
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


def glasses(img, cx, cy, w, frame=WHITE, line=GREEN):
    """Thick 'geek' glasses with a rising chart line running through both lenses.
    (cx, cy, w) are in pixels: the centre and total width of the glasses."""
    d = ImageDraw.Draw(img, "RGBA")
    lw, lh, gap = w * 0.43, w * 0.30, w * 0.14
    t = w * 0.055                      # frame thickness
    lx0, rx0 = cx - gap / 2 - lw, cx + gap / 2
    y0 = cy - lh / 2
    rad = lh * 0.34
    for x0 in (lx0, rx0):              # lens glass: a faint tint so the line reads as "inside"
        d.rounded_rectangle((x0, y0, x0 + lw, y0 + lh), radius=rad, fill=(255, 255, 255, 18))
    # chart line: low in the left lens, rising across the bridge, ending high in the right lens
    pts = [(lx0 + lw * 0.16, y0 + lh * 0.74), (lx0 + lw * 0.50, y0 + lh * 0.48),
           (lx0 + lw * 0.78, y0 + lh * 0.62), (rx0 + lw * 0.30, y0 + lh * 0.38),
           (rx0 + lw * 0.80, y0 + lh * 0.24)]
    arrow(d, [(x / 1.0, y / 1.0) for x, y in pts], line, t * 0.82, t * 2.3, scale=1)
    for x0 in (lx0, rx0):
        d.rounded_rectangle((x0, y0, x0 + lw, y0 + lh), radius=rad, outline=frame, width=int(t))
    # bridge and the little temple stubs
    d.arc((cx - gap * 0.75, y0 + lh * 0.05, cx + gap * 0.75, y0 + lh * 0.60), 200, 340, fill=frame, width=int(t * 0.9))
    d.rounded_rectangle((lx0 - t * 1.6, y0 + lh * 0.12, lx0 + t * 0.5, y0 + lh * 0.12 + t), radius=t / 2, fill=frame)
    d.rounded_rectangle((rx0 + lw - t * 0.5, y0 + lh * 0.12, rx0 + lw + t * 1.6, y0 + lh * 0.12 + t), radius=t / 2, fill=frame)


def centered(d, x, y, s, f, fill):
    d.text((x, y), s, font=f, fill=fill, anchor="mm")


def mark_glasses():
    """The geek glasses with a chart inside: works with no text at every size."""
    img = background()
    glasses(img, N * 0.5, N * 0.5, N * 0.74)
    return img


def monogram():
    """'SG' with a chart arrow climbing underneath, and the red 'live' dot from the videos."""
    img = background()
    d = ImageDraw.Draw(img)
    centered(d, N / 2, N * 0.43, "SG", font(N * 0.36), WHITE)
    arrow(d, [(0.22, 0.785), (0.39, 0.695), (0.52, 0.745), (0.75, 0.62)], YELLOW, N * 0.046, N * 0.13)
    d.ellipse((N * 0.765, N * 0.215, N * 0.835, N * 0.285), fill=RED)
    return img


def wordmark():
    """Stacked name with the glasses on top, for places that show the picture bigger."""
    img = background()
    d = ImageDraw.Draw(img)
    glasses(img, N * 0.5, N * 0.27, N * 0.38, frame=WHITE, line=GREEN)
    f = font(N * 0.205)
    centered(d, N / 2, N * 0.52, "STOCK", f, WHITE)
    centered(d, N / 2, N * 0.71, "GEEK", f, YELLOW)
    return img


def banner():
    """2560x1440 YouTube banner. Everything that matters sits in the centre 1546x423."""
    W, H = 2560, 1440
    img = background(W, H, cy=0.5)
    d = ImageDraw.Draw(img, "RGBA")
    for gx in range(0, W, 80):         # faint chart grid, like the videos
        d.line([(gx, 0), (gx, H)], fill=(255, 255, 255, 10))
    for gy in range(0, H, 80):
        d.line([(0, gy), (W, gy)], fill=(255, 255, 255, 10))
    rng = np.random.default_rng(4)     # faint candlestick tape across the full width
    price = 0.0
    for i, x in enumerate(range(40, W, 70)):
        step = rng.normal(0.35, 1.0)
        o, c = price, price + step
        price = c
        hi, lo = max(o, c) + abs(rng.normal(0, 0.5)), min(o, c) - abs(rng.normal(0, 0.5))
        y = lambda v: H * 0.78 - v * 9 - i * 1.2
        col = (34, 211, 102, 46) if c >= o else (255, 77, 77, 46)
        d.line([(x, y(hi)), (x, y(lo))], fill=col, width=4)
        d.rectangle((x - 14, y(max(o, c)), x + 14, y(min(o, c)) + 2), fill=col)
    # Everything below sits inside the safe area (x 507..2053, y 508..931), centred as one group.
    def fit(text, size, max_w, weight="Black"):
        while font(size, weight).getlength(text) > max_w:
            size -= 2
        return font(size, weight)

    gw, gap, max_text = 360, 56, 1546 - 120 - 360 - 56
    tf = fit("STOCK GEEK", 150, max_text)
    lines = ["The day's biggest stock moves & Congress trades,", "explained in under a minute."]
    lf = fit(lines[0], 44, max_text, "SemiBold")
    text_w = max(tf.getlength("STOCK GEEK"), lf.getlength(lines[0]))
    x0 = 1280 - (gw + gap + text_w) / 2
    tx = x0 + gw + gap
    glasses(img, x0 + gw / 2, 728, gw)
    d = ImageDraw.Draw(img)
    pill = "NEW EVERY TRADING DAY"
    pf = font(32, "ExtraBold")
    d.rounded_rectangle((tx, 566, tx + pf.getlength(pill) + 44, 612), radius=23, fill=RED)
    d.text((tx + 22, 589), pill, font=pf, fill=WHITE, anchor="lm")
    d.text((tx - 4, 690), "STOCK", font=tf, fill=WHITE, anchor="lm")
    d.text((tx - 4 + tf.getlength("STOCK "), 690), "GEEK", font=tf, fill=YELLOW, anchor="lm")
    d.text((tx, 800), lines[0], font=lf, fill=WHITE, anchor="lm")
    d.text((tx, 856), lines[1], font=lf, fill=WHITE, anchor="lm")
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
    for old in ("profile-candles.png", "profile-preview.png"):  # retired with the rename
        p = os.path.join(OUT, old)
        if os.path.exists(p):
            os.remove(p)
    variants = [("glasses", mark_glasses()), ("monogram", monogram()), ("wordmark", wordmark())]
    ban = banner()
    ban.save(os.path.join(OUT, "youtube-banner.png"))
    sheet = Image.new("RGB", (3 * 460, 640 + 420), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    label = font(22, "SemiBold")
    for i, (name, big) in enumerate(variants):
        big.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, f"profile-{name}.png"))
        x = i * 460 + 30
        sheet.paste(circle(big, 400), (x, 20))
        sheet.paste(circle(big, 98), (x, 450))       # YouTube channel page size
        sheet.paste(circle(big, 40), (x + 130, 480))  # comments / sidebar size
        d.text((x, 600), f"{i + 1}. {name}", font=label, fill=(30, 30, 40))
    sheet.paste(ban.resize((660, 371)), (30, 660))
    d.text((720, 680), "YouTube banner", font=label, fill=(30, 30, 40))
    d.text((720, 715), "(phones show only the middle strip)", font=font(18, "Medium"), fill=(90, 90, 100))
    safe = ban.crop((507, 508, 2053, 931)).resize((620, 170))
    sheet.paste(safe, (720, 760))
    sheet.save(os.path.join(OUT, "preview.png"))
    print("Done:", OUT)


if __name__ == "__main__":
    main()
