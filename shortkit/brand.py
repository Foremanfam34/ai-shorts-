"""Stock Geek brand marks, shared by the videos (header lockup, outro badge) and the channel art."""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import FONT_DIR

NAME = "Stock Geek"
YELLOW, RED, GREEN, WHITE = (255, 214, 10), (255, 77, 77), (34, 211, 102), (244, 246, 250)


def font(size, weight="Black"):
    return ImageFont.truetype(os.path.join(FONT_DIR, f"Inter-{weight}.otf"), int(size))


def arrow(d, pts, color, width, head, scale=1.0):
    """A chart line that ends in an arrowhead pointing along its last segment."""
    pts = [(x * scale, y * scale) for x, y in pts]
    (x1, y1), (x2, y2) = pts[-2], pts[-1]
    v = np.array([x2 - x1, y2 - y1], dtype=float)
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
    (cx, cy, w) are in pixels: the centre and the width of the two lenses plus the bridge."""
    d = ImageDraw.Draw(img, "RGBA")
    lw, lh, gap = w * 0.43, w * 0.30, w * 0.14
    t = w * 0.055                      # frame thickness
    lx0, rx0 = cx - gap / 2 - lw, cx + gap / 2
    y0 = cy - lh / 2
    rad = lh * 0.34
    for x0 in (lx0, rx0):              # lens glass: a faint tint so the line reads as "inside"
        d.rounded_rectangle((x0, y0, x0 + lw, y0 + lh), radius=rad, fill=(255, 255, 255, 18))
    pts = [(lx0 + lw * 0.16, y0 + lh * 0.74), (lx0 + lw * 0.50, y0 + lh * 0.48),
           (lx0 + lw * 0.78, y0 + lh * 0.62), (rx0 + lw * 0.30, y0 + lh * 0.38),
           (rx0 + lw * 0.80, y0 + lh * 0.24)]
    arrow(d, pts, line, t * 0.82, t * 2.3)
    for x0 in (lx0, rx0):
        d.rounded_rectangle((x0, y0, x0 + lw, y0 + lh), radius=rad, outline=frame, width=int(t))
    d.arc((cx - gap * 0.75, y0 + lh * 0.05, cx + gap * 0.75, y0 + lh * 0.60), 200, 340, fill=frame, width=int(t * 0.9))
    d.rounded_rectangle((lx0 - t * 1.6, y0 + lh * 0.12, lx0 + t * 0.5, y0 + lh * 0.12 + t), radius=t / 2, fill=frame)
    d.rounded_rectangle((rx0 + lw - t * 0.5, y0 + lh * 0.12, rx0 + lw + t * 1.6, y0 + lh * 0.12 + t), radius=t / 2, fill=frame)


def lockup(height=62, ss=4):
    """Small glasses + 'STOCK GEEK' on a transparent background, for the top of every video."""
    h = height * ss
    f = font(h * 0.6)
    gw = h * 1.5                       # lens-to-lens width of the glasses
    pad = gw * 0.1                     # room for the temple stubs
    x_text = pad + gw + h * 0.28
    w = int(x_text + f.getlength("STOCK GEEK") + h * 0.1)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glasses(im, pad + gw / 2, h * 0.52, gw)
    d = ImageDraw.Draw(im)
    d.text((x_text, h * 0.53), "STOCK", font=f, fill=WHITE + (255,), anchor="lm")
    d.text((x_text + f.getlength("STOCK "), h * 0.53), "GEEK", font=f, fill=YELLOW + (255,), anchor="lm")
    return im.resize((w // ss, height), Image.LANCZOS)


def badge(width=300, ss=4):
    """The glasses alone, centred on a transparent canvas, for the outro."""
    h = int(width * 0.42)
    im = Image.new("RGBA", (width * ss, h * ss), (0, 0, 0, 0))
    glasses(im, width * ss / 2, h * ss / 2, width * ss * 0.84)
    return im.resize((width, h), Image.LANCZOS)
