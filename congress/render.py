#!/usr/bin/env python3
"""Render a "Congress Trades" Short (1080x1920, 30 fps) from an episode JSON.

    python3 congress/render.py congress/episodes/2026-11-03.json

Pipeline: script -> Kokoro voiceover -> Parakeet word timings -> animations synced to the
words -> synthesized music bed + SFX -> word-by-word captions -> H.264/AAC MP4 at -14 LUFS.
Also writes a cover image and a post.txt (title/description/hashtags) for the uploader.
Scene types and their fields are documented in congress/EPISODES.md.
"""
import argparse
import datetime as dt
import json
import math
import os
import re
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from shortkit import FONT_DIR, ROOT, audio, brand, captions  # noqa: E402
from shortkit.asr import Transcriber  # noqa: E402
from shortkit.tts import SAMPLE_RATE, Voice  # noqa: E402

W, H, FPS = 1080, 1920, 30
LEAD, TAIL, LAST_TAIL = 0.25, 0.35, 1.3
SR = SAMPLE_RATE
PAN_X, PAN_Y = 120, 240  # the background is this much bigger than the frame and drifts slowly

BG0, BG1 = (7, 10, 19), (17, 24, 44)
CARD, CARD_HI = (23, 30, 50), (34, 44, 72)
TEXT, MUTED = (242, 244, 248), (140, 150, 172)
RED, GREEN, YELLOW, BLUE = (255, 77, 77), (34, 211, 102), (255, 214, 10), (96, 165, 250)
INK = (10, 12, 20)
COLORS = {"red": RED, "green": GREEN, "yellow": YELLOW, "blue": BLUE, "white": TEXT}
TICKER_COLORS = {"AAPL": (96, 98, 110), "MSFT": (0, 132, 210), "AMZN": (230, 135, 0),
                 "GOOGL": (52, 110, 220), "NVDA": (98, 160, 0), "TSLA": (205, 30, 36),
                 "AVGO": (190, 20, 50), "INTC": (0, 104, 181), "BE": (0, 150, 110),
                 "DDOG": (99, 44, 166), "FIS": (60, 120, 70), "MDLN": (0, 106, 170), "XYZ": (30, 30, 34),
                 "MRNA": (200, 40, 50), "VRT": (230, 110, 20), "APP": (20, 110, 230), "QCOM": (50, 80, 200)}

_fonts = {}
FADE = 1.0  # scene-level opacity, multiplied into every draw call
CANVAS = None  # the frame being drawn
BRAND_HDR = BRAND_BADGE = None  # Stock Geek lockup and glasses, pre-rendered once per video


def F(weight, size):
    size = max(12, int(size))
    if (weight, size) not in _fonts:
        _fonts[(weight, size)] = ImageFont.truetype(f"{FONT_DIR}/Inter-{weight}.otf", size)
    return _fonts[(weight, size)]


def fit(s, weight, size, max_w):
    while size > 20 and F(weight, size).getlength(s) > max_w:
        size -= 3
    return F(weight, size)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def ease_out(t):
    t = clamp(t)
    return 1 - (1 - t) ** 3


def ease_back(t):
    t = clamp(t)
    c = 1.70158
    return 1 + (c + 1) * (t - 1) ** 3 + c * (t - 1) ** 2


def prog(t, start, dur):
    return clamp((t - start) / dur)


def rgba(c, a=1.0):
    return (c[0], c[1], c[2], int(255 * clamp(a * FADE)))


def draw_text(im, xy, s, font, fill, alpha=1.0, anchor="la"):
    """Text with real opacity. (Pillow ignores the alpha of text ink when blending onto RGB,
    so partially transparent text is drawn into a mask and pasted.)"""
    alpha = clamp(alpha)
    if alpha <= 0.004:
        return
    if alpha >= 0.996:
        ImageDraw.Draw(im).text(xy, s, font=font, fill=tuple(fill[:3]), anchor=anchor)
        return
    x0, y0, x1, y1 = ImageDraw.Draw(im).textbbox(xy, s, font=font, anchor=anchor)
    x0, y0, x1, y1 = int(x0) - 2, int(y0) - 2, int(x1) + 3, int(y1) + 3
    mask = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(mask).text((xy[0] - x0, xy[1] - y0), s, font=font, fill=int(255 * alpha), anchor=anchor)
    im.paste(tuple(fill[:3]), (x0, y0, x1, y1), mask)


def text(d, xy, s, font, fill, a=1.0, anchor="la"):
    draw_text(CANVAS, xy, s, font, fill, a * FADE, anchor)


def pill(d, cx, cy, s, font, bg, fg=TEXT, a=1.0, padx=22, pady=12, radius=14, anchor="m"):
    tw = font.getlength(s)
    asc, desc = font.getmetrics()
    h = asc * 0.75 + 2 * pady
    x0 = cx - tw / 2 - padx if anchor == "m" else (cx if anchor == "l" else cx - tw - 2 * padx)
    d.rounded_rectangle((x0, cy - h / 2, x0 + tw + 2 * padx, cy + h / 2), radius=radius, fill=rgba(bg, a))
    text(d, (x0 + padx + tw / 2, cy), s, font, fg, a, "mm")
    return x0, x0 + tw + 2 * padx


def on_color(c):
    """Readable text color on top of a filled pill."""
    return INK if c in (YELLOW, GREEN) else TEXT


def money_k(v):
    return f"${v / 1000:.1f}M" if v >= 1000 else f"${v:.0f}K"


def minus(s):
    return re.sub(r"(?<![\w$])-(?=\d)", "−", s)


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


# ---------------------------------------------------------------- background + header
def make_background():
    bw, bh = W + PAN_X, H + PAN_Y
    y = np.linspace(0, 1, bh)[:, None, None]
    grad = np.repeat(np.array(BG0) * (1 - y) + np.array(BG1) * y, bw, axis=1)
    yy, xx = np.mgrid[0:bh, 0:bw]
    g1 = np.exp(-(((xx - bw * 0.35) / 650) ** 2 + ((yy - 430) / 520) ** 2))[..., None]
    g2 = np.exp(-(((xx - bw * 0.85) / 560) ** 2 + ((yy - bh * 0.72) / 620) ** 2))[..., None]
    grad = grad + g1 * np.array([18, 26, 56]) + g2 * np.array([26, 12, 38])
    img = Image.fromarray(np.clip(grad, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img, "RGBA")
    for gx in range(0, bw, 90):
        d.line([(gx, 0), (gx, bh)], fill=(255, 255, 255, 9))
    for gy in range(0, bh, 90):
        d.line([(0, gy), (bw, gy)], fill=(255, 255, 255, 9))
    return img


def draw_header(img, d, ep):
    # row 1: the Stock Geek lockup and the date; row 2: show + format pills; row 3: the source
    img.paste(BRAND_HDR, (50, 172), BRAND_HDR)
    d.text((1000, 204), ep["week_label"], font=F("SemiBold", 30), fill=MUTED, anchor="rm")
    f = F("ExtraBold", 26)
    label = ep["series"]
    tw = f.getlength(label)
    d.rounded_rectangle((60, 250, 60 + tw + 64, 292), radius=21, fill=RED + (255,))
    d.ellipse((76, 264, 90, 278), fill=(255, 255, 255, 255))
    d.text((100, 271), label, font=f, fill=TEXT, anchor="lm")
    if ep.get("badge"):
        x = 60 + tw + 64 + 10
        bw = f.getlength(ep["badge"])
        d.rounded_rectangle((x, 250, x + bw + 36, 292), radius=21, fill=YELLOW + (255,))
        d.text((x + 18, 271), ep["badge"], font=f, fill=INK, anchor="lm")
    d.text((60, 326), ep["source_line"], font=F("Medium", 24), fill=MUTED, anchor="lm")


# ---------------------------------------------------------------- scenes
def cue(sc, word, default):
    t = sc["_cues"].get(word)
    return default if t is None else t


def scene_title(d, t, who, sub):
    a = ease_out(prog(t, 0, 0.35))
    text(d, (60, 380 - 24 * (1 - a)), who, fit(who, "Black", 66, 950), TEXT, a, "lm")
    if sub:
        text(d, (60, 448 - 24 * (1 - a)), sub, fit(sub, "Medium", 34, 950), MUTED, a, "lm")


def draw_hook(img, d, sc, t, dur):
    # Everything is on screen from frame 1 (it doubles as the feed preview); motion is a slow
    # push-in plus a pulse on the number, then the pill pops when it's spoken.
    f1 = fit(sc["line1"], "ExtraBold", 66, 940)
    text(d, (W // 2, 590), sc["line1"], f1, TEXT, 1.0, "mm")
    if "big_text" in sc:
        final = minus(sc["big_text"])
    else:
        final = f"{money_k(sc['big']['lo'])}–{money_k(sc['big']['hi'])}"
    fb = fit(final, "Black", 160, 960)
    grow = 1 + 0.05 * prog(t, 0, dur) + 0.07 * np.sin(np.pi * prog(t, 0.2, 0.45))
    text(d, (W // 2, 790), final, F("Black", fb.size * grow), COLORS[sc.get("big_color", "yellow")], 1.0, "mm")
    if sc.get("line2"):
        text(d, (W // 2, 990), sc["line2"], f1, TEXT, 1.0, "mm")
    if sc.get("pill"):
        label = minus(sc["pill"])
        tp = cue(sc, sc.get("pill_cue"), dur * 0.7)
        pp = prog(t, tp - 0.05, 0.3)
        if pp > 0:
            kk = ease_back(pp)
            col = COLORS[sc.get("pill_color", "red")]
            size = fit(label, "Black", 88, 860).size
            pill(d, W // 2, 1170, label, F("Black", size * kk), col, on_color(col), clamp(pp * 3),
                 padx=44 * kk, pady=26 * kk, radius=28)


def ticker_badge(d, x, cy, ticker, a, w=96, h=72, size=24):
    d.rounded_rectangle((x, cy - h / 2, x + w, cy + h / 2), radius=16,
                        fill=rgba(TICKER_COLORS.get(ticker, (80, 90, 110)), a))
    text(d, (x + w / 2, cy), ticker, fit(ticker, "Black", size, w - 12), TEXT, a, "mm")


def side_color(side):
    return GREEN if side.upper() in ("BUY", "UP") else RED


def draw_trades(img, d, sc, t, dur):
    scene_title(d, t, sc["who"], sc["sub"])
    top, rh, gap = 520, 112, 16
    emph = sc["_emph"]  # when each row's name is spoken (None = not heard)
    heard = [i for i, e in enumerate(emph) if e is not None and e <= t]
    active = max(heard, key=lambda i: emph[i]) if heard else None
    for i, row in enumerate(sc["rows"]):
        p = prog(t, sc["_reveals"][i], 0.35)
        if p <= 0:
            continue
        spot = 1.0 if (not heard or emph[i] is None or i in heard) else 0.45
        off = (1 - ease_out(p)) * 260 - (np.sin(np.pi * prog(t, emph[i], 0.3)) * 14 if i == active else 0)
        a = clamp(p * 2) * spot
        y0 = top + i * (rh + gap)
        cy = y0 + rh / 2
        d.rounded_rectangle((60 + off, y0, 1000 + off, y0 + rh), radius=22,
                            fill=rgba(CARD_HI if i == active else CARD, a))
        if i == active:
            d.rounded_rectangle((60 + off, y0, 68 + off, y0 + rh), radius=4, fill=rgba(side_color(row["side"]), a))
        ticker_badge(d, 86 + off, cy, row["ticker"], a)
        text(d, (204 + off, cy), row["name"], fit(row["name"], "SemiBold", 44, 420), TEXT, a, "lm")
        fr = F("Bold", 42)
        rx = 976 + off
        text(d, (rx, cy), row["range"], fr, TEXT, a, "rm")
        pill(d, rx - fr.getlength(row["range"]) - 24, cy, row["side"], F("ExtraBold", 28),
             side_color(row["side"]), on_color(side_color(row["side"])), a, padx=16, pady=12, radius=12, anchor="r")


def draw_bars(img, d, sc, t, dur):
    scene_title(d, t, sc["title"], sc["sub"])
    rows = sorted(sc["rows"], key=lambda r: r["pct"])
    zero_x, max_len = 600, 330
    scale = max_len / max(abs(r["pct"]) for r in rows)
    top, rh = 520, 125
    cue_times = [cue(sc, r.get("cue"), None) for r in rows]
    first_cue = min([c for c in cue_times if c is not None], default=None)
    d.line([(zero_x, top - 10), (zero_x, top + len(rows) * rh - 20)], fill=rgba(MUTED, 0.5), width=3)
    for i, r in enumerate(rows):
        cy = top + i * rh + rh / 2 - 10
        grow = ease_out(prog(t, 0.2 + i * 0.07, 0.7))
        ct = cue_times[i]
        dim = 1.0
        if first_cue is not None and t > first_cue:
            dim = 1.0 if (ct is not None and t >= ct) else 0.38
        bump = np.sin(np.pi * prog(t, ct, 0.35)) * 10 if ct is not None else 0.0
        a = clamp(grow * 2) * dim
        text(d, (60, cy), r["ticker"], F("ExtraBold", 44), TEXT, a, "lm")
        L = r["pct"] * scale * grow
        h2 = 32 + bump
        col = RED if r["pct"] < 0 else GREEN
        x0, x1 = (zero_x + L, zero_x) if L < 0 else (zero_x, zero_x + L)
        if abs(L) > 2:
            d.rounded_rectangle((x0, cy - h2, x1, cy + h2), radius=12, fill=rgba(col, a))
        label = minus(f"{r['pct'] * grow:+.1f}%")
        fl = F("Black", 46 + bump)
        la = a * clamp((grow - 0.25) * 3)  # don't flash "−0.0%" while the bar starts growing
        if r["pct"] < 0:
            text(d, (zero_x + 22, cy), label, fl, col, la, "lm")
        else:
            text(d, (zero_x - 22, cy), label, fl, col, la, "rm")


# --- chart: a price line that draws itself in sync with the narration
def y_range(prices):
    pmin, pmax = min(prices), max(prices)
    span = max(pmax - pmin, 1e-6)
    step = next((s for s in (0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000) if span / s <= 5), 1000)
    return (math.floor((pmin - span * 0.06) / step) * step, math.ceil((pmax + span * 0.06) / step) * step, step)


def x_ticks(dates, marker_idx, width=820):
    ds = [dt.date.fromisoformat(x) for x in dates]
    if (ds[-1] - ds[0]).days > 75:  # long ranges: one tick per month
        ticks = [(i, ds[i].strftime("%b")) for i in range(len(ds)) if i == 0 or ds[i].month != ds[i - 1].month]
    else:
        ticks = [(i, f"{ds[i]:%b} {ds[i].day}") for i in sorted({0, *marker_idx, len(ds) - 1})]
    out = []
    for i, lab in ticks:
        x = width * i / (len(ds) - 1)
        if not out or x - out[-1][2] >= 110:
            out.append((i, lab, x))
    return [(i, lab) for i, lab, _ in out]


def chart_timeline(sc, dur):
    """Keyframes (time -> series index) for drawing the line, and when it reaches each marker."""
    dates = [x for x, _ in sc["series"]]
    n = len(dates)
    items = list(sc.get("markers", [])) + ([sc["drop"]] if sc.get("drop") else [])
    for it in items:
        it["_i"] = dates.index(it["date"])
    keys = [(0.35, 0.0)]
    for it in sorted(items, key=lambda m: m["_i"]):
        tc = sc["_cues"].get(it.get("cue")) if it.get("cue") else None
        if tc is not None and it["_i"] > keys[-1][1]:
            keys.append((max(tc, keys[-1][0] + 0.5), float(it["_i"])))
    keys.append((keys[-1][0] + (0.9 if len(keys) > 1 else max(1.5, dur * 0.55)), float(n - 1)))
    for it in items:
        it["_t"] = time_at_index(keys, it["_i"])
    sc["_keys"] = keys
    sc["_yr"] = y_range([p for _, p in sc["series"]])
    sc["_xt"] = x_ticks(dates, [m["_i"] for m in sc.get("markers", [])])


def time_at_index(keys, i):
    for (ta, ia), (tb, ib) in zip(keys, keys[1:]):
        if ia <= i <= ib:
            return ta + (tb - ta) * ((i - ia) / (ib - ia) if ib > ia else 0)
    return keys[-1][0]


def index_at_time(keys, t):
    if t <= keys[0][0]:
        return keys[0][1]
    for (ta, ia), (tb, ib) in zip(keys, keys[1:]):
        if ta <= t <= tb:
            return ia + (ib - ia) * (t - ta) / (tb - ta)
    return keys[-1][1]


def draw_chart(img, d, sc, t, dur):
    scene_title(d, t, sc["who"], sc["sub"])
    prices = [p for _, p in sc["series"]]
    n = len(prices)
    pidx = index_at_time(sc["_keys"], t)
    lo, hi, step = sc["_yr"]

    S = 2  # draw at 2x and downsample for smooth lines
    rx0, ry0, rx1, ry1 = 40, 500, 1040, 1250
    region = img.crop((rx0, ry0, rx1, ry1)).resize(((rx1 - rx0) * S, (ry1 - ry0) * S))
    cd = ImageDraw.Draw(region, "RGBA")
    px0, px1, py0, py1 = 170, 990, 560, 1150

    def X(i):
        return ((px0 + (px1 - px0) * i / (n - 1)) - rx0) * S

    def Y(p):
        return ((py1 - (py1 - py0) * (p - lo) / (hi - lo)) - ry0) * S

    a = ease_out(prog(t, 0.1, 0.4))
    gp = lo
    while gp <= hi + 1e-9:
        cd.line([(X(0), Y(gp)), (X(n - 1), Y(gp))], fill=rgba((255, 255, 255), 0.08 * a), width=2 * S)
        draw_text(region, (X(0) - 18 * S, Y(gp)), f"${gp:g}", F("Medium", 26 * S), MUTED, a * FADE, "rm")
        gp += step
    for i, lab in sc["_xt"]:
        draw_text(region, (X(i), Y(lo) + 40 * S), lab, F("Medium", 26 * S), MUTED, a * FADE, "mm")

    k = int(np.floor(pidx))
    frac = pidx - k
    pts = [(X(i), Y(prices[i])) for i in range(k + 1)]
    if k < n - 1:
        pts.append((X(k + frac), Y(prices[k] + (prices[k + 1] - prices[k]) * frac)))
    drop = sc.get("drop")
    if len(pts) >= 2:
        cd.polygon(pts + [(pts[-1][0], Y(lo)), (pts[0][0], Y(lo))], fill=rgba(BLUE, 0.14))
        cd.line(pts, fill=rgba(BLUE), width=7 * S, joint="curve")
        if drop and pidx >= drop["_i"] - 1:  # the big one-day move in red
            j = drop["_i"] - 1
            seg = min(1.0, pidx - j)
            cd.line([(X(j), Y(prices[j])), (X(j + seg), Y(prices[j] + (prices[j + 1] - prices[j]) * seg))],
                    fill=rgba(RED), width=9 * S)
        hx, hy = pts[-1]
        cd.ellipse((hx - 11 * S, hy - 11 * S, hx + 11 * S, hy + 11 * S), fill=rgba(TEXT))

    for m in sc.get("markers", []):
        ps = prog(t, m["_t"] - 0.05, 0.35)
        if ps <= 0:
            continue
        kk = ease_back(ps)
        col = COLORS[m.get("color", "yellow")]
        sx, sy = X(m["_i"]), Y(prices[m["_i"]])
        r = 15 * S * kk
        cd.ellipse((sx - r, sy - r, sx + r, sy + r), fill=rgba(col, ps * 2))
        f = F("ExtraBold", 30 * S * kk)
        tw = f.getlength(m["label"])
        by = sy - 80 * S if not m.get("below") else sy + 80 * S
        bx = min(max(sx, X(0) + tw / 2 + 20 * S), X(n - 1) - tw / 2 - 20 * S)
        cd.rounded_rectangle((bx - tw / 2 - 18 * S, by - 28 * S * kk, bx + tw / 2 + 18 * S, by + 28 * S * kk),
                             radius=12 * S, fill=rgba(col, ps * 2))
        draw_text(region, (bx, by), m["label"], f, on_color(col), clamp(ps * 2) * FADE, "mm")
        edge = by + 28 * S * kk if not m.get("below") else by - 28 * S * kk
        cd.line([(sx, sy - r if not m.get("below") else sy + r), (sx, edge)], fill=rgba(col, ps * 2), width=3 * S)

    if drop:
        pdp = prog(t, drop["_t"] + 0.05, 0.35)
        if pdp > 0:
            kk = ease_back(pdp)
            f = F("Black", 36 * S * kk)
            lab = minus(drop["label"])
            tw = f.getlength(lab)
            # just left of the drop, half-way down it (clear of the axis labels)
            j = drop["_i"]
            bx1, by = X(j - 1) - 10 * S, Y((prices[j - 1] + prices[j]) / 2) + 30 * S
            cd.rounded_rectangle((bx1 - tw - 40 * S, by - 34 * S * kk, bx1, by + 34 * S * kk),
                                 radius=14 * S, fill=rgba(RED, pdp * 2))
            draw_text(region, (bx1 - 20 * S - tw / 2, by), lab, f, TEXT, clamp(pdp * 2) * FADE, "mm")

    region = region.resize((rx1 - rx0, ry1 - ry0), Image.LANCZOS)
    shake = 0
    if drop and 0 < t - drop["_t"] < 0.35:
        e = t - drop["_t"]
        shake = int(np.sin(e * 90) * 10 * (1 - e / 0.35))
    img.paste(region, (rx0 + shake, ry0))

    st = sc.get("stat")  # the takeaway number, in the free band between the chart and the captions
    if st:
        tc = cue(sc, st.get("cue"), dur * 0.75)
        pst = prog(t, tc - 0.05, 0.35)
        if pst > 0:
            kk = ease_back(pst)
            val = minus(st["value"])
            col = RED if val.startswith("−") else GREEN
            fv = F("Black", 84 * kk)
            text(d, (60, 1305), val, fv, col, clamp(pst * 2), "lm")
            text(d, (60 + F("Black", 84).getlength(val) + 22, 1311), st["label"],
                 fit(st["label"], "SemiBold", 36, 560), TEXT, clamp(pst * 2), "lm")


def draw_list(img, d, sc, t, dur):
    scene_title(d, t, sc["title"], None)
    top, rh, gap = 470, 216, 26
    for i, row in enumerate(sc["rows"]):
        p = prog(t, sc["_reveals"][i] - 0.06, 0.35)
        if p <= 0:
            continue
        off = (1 - ease_out(p)) * 260
        a = clamp(p * 2)
        y0 = top + i * (rh + gap)
        d.rounded_rectangle((60 + off, y0, 1000 + off, y0 + rh), radius=24, fill=rgba(CARD, a))
        text(d, (96 + off, y0 + 52), row["who"], fit(row["who"], "Bold", 42, 860), TEXT, a, "lm")
        ticker_badge(d, 96 + off, y0 + 118, row["ticker"], a, w=118, h=58, size=28)
        x_after = pill(d, 238 + off, y0 + 118, row["side"], F("ExtraBold", 28), side_color(row["side"]),
                       on_color(side_color(row["side"])), a, padx=16, pady=12, radius=12, anchor="l")[1]
        text(d, (x_after + 22, y0 + 118), row["range"], F("Bold", 42), TEXT, a, "lm")
        text(d, (96 + off, y0 + 180), row["dates"], F("Medium", 30), MUTED, a, "lm")


def draw_outro(img, d, sc, t, dur):
    for i, note in enumerate(sc["notes"]):
        a = ease_out(prog(t, 0.1 + i * 0.25, 0.4))
        y = 400 + i * 100
        d.rounded_rectangle((60, y - 12, 84, y + 12), radius=5, fill=rgba(YELLOW, a))
        text(d, (110, y + 24 * (1 - a)), note, fit(note, "SemiBold", 40, 880), TEXT, a, "lm")
    ab = ease_out(prog(t, 0.35, 0.5))  # the Stock Geek glasses settle in above the call to action
    if ab > 0:
        bw, bh = BRAND_BADGE.size
        mask = BRAND_BADGE.getchannel("A").point(lambda v: int(v * clamp(ab * FADE)))
        img.paste(BRAND_BADGE, (W // 2 - bw // 2, int(735 - bh // 2 + 30 * (1 - ab))), mask)
    tc = cue(sc, sc.get("cta_cue"), dur * 0.75)
    pc = prog(t, tc - 0.1, 0.4)
    if pc > 0:
        kk = ease_back(pc)
        words = sc["cta"].split()
        half = (len(words) + 1) // 2
        l1, l2 = " ".join(words[:half]), " ".join(words[half:])
        pulse = 1 + 0.03 * np.sin(max(0, t - tc) * 6)
        f = fit(max(l1, l2, key=len), "Black", 92, 940)
        f = F("Black", f.size * kk * pulse)
        text(d, (W // 2, 890), l1, f, YELLOW, clamp(pc * 2), "mm")
        text(d, (W // 2, 995), l2, f, YELLOW, clamp(pc * 2), "mm")
        pill(d, W // 2, 1100, "SUBSCRIBE", F("Black", 46 * kk * pulse), RED, TEXT, clamp(pc * 2),
             padx=40 * kk, pady=20 * kk, radius=30)
    a = ease_out(prog(t, 0.6, 0.5))
    text(d, (W // 2, 1205), sc["credits"], fit(sc["credits"], "Medium", 28, 940), MUTED, a, "mm")


DRAW = {"hook": draw_hook, "trades": draw_trades, "bars": draw_bars, "chart": draw_chart,
        "list": draw_list, "outro": draw_outro}


# ---------------------------------------------------------------- pipeline
def prepare(ep, workdir):
    scenes = ep["scenes"]
    print(f"[1/4] Voiceover ({ep['voice']}) for {len(scenes)} scenes…", flush=True)
    voice = Voice([s["say"] for s in scenes], say_as=ep.get("say_as"))
    ep["_qa"] = {"warnings": [], "espeak_words": sorted(voice.oov)}
    if voice.oov:
        print("      words not in the dictionary (pronounced via espeak):", ", ".join(voice.oov))
    tr = Transcriber()
    t0 = 0.0
    for i, sc in enumerate(scenes):
        if ep.get("natural", True):  # phrase-by-phrase delivery with human pauses
            samples = voice.say_natural(sc["say"], ep["voice"], ep.get("speed", 1.0), seed=i,
                                        pause_scale=ep.get("pause_scale", 1.0))
        else:
            samples = voice.say(sc["say"], ep["voice"], ep.get("speed", 1.0))
        heard = tr.words(samples, sr=SR)
        words = captions.fix_phrases(captions.align_to_script(heard, sc["say"]), ep.get("caption_fix"))
        sc["_audio"] = samples
        sc["_start"] = t0
        sc["_dur"] = LEAD + len(samples) / SR + (LAST_TAIL if i == len(scenes) - 1 else TAIL)
        sc["_words"] = [dict(w, start=w["start"] + LEAD, end=w["end"] + LEAD) for w in words]

        def find(key, after=-1.0):
            for w in sc["_words"]:
                if w["start"] > after and norm(w["w"]).startswith(norm(key)):
                    return w["start"]
            msg = f"cue {key!r} not heard in scene {i + 1}"
            ep["_qa"]["warnings"].append(msg)
            print(f"      ! {msg}; using a default time")
            return None

        cues = {}
        keys = [sc.get("pill_cue"), sc.get("cta_cue"), (sc.get("drop") or {}).get("cue"),
                (sc.get("stat") or {}).get("cue")] + [m.get("cue") for m in sc.get("markers", [])]
        for key in filter(None, keys):
            if (tc := find(key)) is not None:
                cues[key] = tc
        # row cues are matched in order, so repeated words ("Representative") map to the right row
        after, sc["_row_cues"] = -1.0, []
        for r in sc.get("rows", []):
            tc = find(r["cue"], after) if r.get("cue") else None
            sc["_row_cues"].append(tc)
            if tc is not None:
                cues.setdefault(r["cue"], tc)
                after = tc
        sc["_cues"] = cues
        sc["_pops"] = []  # local times for a UI "pop" sound
        if sc["type"] == "trades":  # rows fly in up front, then get spotlit as they're named
            sc["_reveals"] = [0.2 + j * 0.1 for j in range(len(sc["rows"]))]
            sc["_emph"] = list(sc["_row_cues"])
            sc["_pops"] = [e for e in sc["_emph"] if e is not None]
        if sc["type"] == "list":  # rows appear as they're named
            n = len(sc["rows"])
            sc["_reveals"] = [c if c is not None else 0.6 + j * (sc["_dur"] - 1.2) / n
                              for j, c in enumerate(sc["_row_cues"])]
            sc["_pops"] = list(sc["_reveals"])
        if sc["type"] == "bars":
            for r in sc["rows"]:
                r["pct"] = (r["to"] / r["from"] - 1) * 100
            sc["_pops"] = [cues[r["cue"]] for r in sc["rows"] if r.get("cue") in cues]
        if sc["type"] == "chart":
            chart_timeline(sc, sc["_dur"])
            sc["_pops"] = [m["_t"] + 0.07 for m in sc.get("markers", [])]
            if (sc.get("stat") or {}).get("cue") in cues:
                sc["_pops"].append(cues[sc["stat"]["cue"]])
        # reveal moments get the full treatment (riser, music cut, impact, zoom punch, flash);
        # smaller beats just get a zoom punch
        rv = []
        if sc["type"] == "hook" and sc.get("pill_cue") in cues:
            rv.append((cues[sc["pill_cue"]], 1.0))
        if sc["type"] == "chart" and sc.get("drop"):
            rv.append((sc["drop"]["_t"], 1.0))
        if sc["type"] == "chart" and (sc.get("stat") or {}).get("cue") in cues:
            rv.append((cues[sc["stat"]["cue"]], 0.5))
        if sc["type"] == "bars" and sc["_pops"]:
            rv.append((min(sc["_pops"]), 0.5))
        if sc["type"] == "outro" and sc.get("cta_cue") in cues:
            rv.append((cues[sc["cta_cue"]], 0.4))
        sc["_fx"] = rv
        heard_text = " ".join(w["w"] for w in heard)
        print(f"      scene {i + 1} [{sc['type']}] {sc['_dur']:.1f}s  heard: {heard_text}")
        t0 += sc["_dur"]
    return t0


def build_audio(ep, total, path):
    print("[2/4] Mixing voice, music bed and sound effects…", flush=True)
    n = int(total * SR) + SR
    voice = np.zeros(n, dtype=np.float32)
    sfx = np.zeros(n, dtype=np.float32)
    wh, pp = audio.whoosh(), audio.pop()
    boom_t = np.arange(int(0.6 * SR)) / SR
    boom = (np.sin(2 * np.pi * (38 + 60 * np.exp(-boom_t * 9)) * boom_t) * np.exp(-boom_t * 6)).astype(np.float32)
    for i, sc in enumerate(ep["scenes"]):
        audio.place(voice, sc["_audio"], sc["_start"] + LEAD)
        if i > 0:
            audio.place(sfx, wh, sc["_start"] - 0.3, 0.5)
        # pops land just before the cue word so they don't mask its first consonant
        for tp in sc["_pops"]:
            audio.place(sfx, pp, sc["_start"] + tp - 0.12, 0.5)
        for key in ("pill_cue", "cta_cue"):
            if sc.get(key) in sc["_cues"]:
                audio.place(sfx, pp, sc["_start"] + sc["_cues"][sc[key]] - 0.12, 0.6)
        if sc["type"] == "chart" and sc.get("drop") and ep.get("music", "groove") != "groove":
            audio.place(sfx, boom, sc["_start"] + sc["drop"]["_t"], 0.9)
    if ep.get("voice_fx", True):
        voice = audio.voice_fx(voice)
    if ep.get("music", "groove") == "groove":
        bed = audio.music_groove(n / SR)
        gain = np.ones(n, dtype=np.float32)
        rs, hit = audio.riser(), audio.impact()
        for sc in ep["scenes"]:
            for t_local, strength in sc["_fx"]:
                T = sc["_start"] + t_local
                if strength >= 1.0:  # build up, drop the music out for a beat, then hit
                    audio.place(sfx, rs, T - len(rs) / SR, 0.55)
                    audio.place(sfx, hit, T, 0.95)
                    s, e = int((T - 0.32) * SR), int(T * SR)
                    if s > 0 and e < n:
                        gain[s:e] = np.minimum(gain[s:e], np.linspace(1.0, 0.12, e - s))
                        ramp = min(int(0.12 * SR), n - e)
                        gain[e:e + ramp] = np.minimum(gain[e:e + ramp], np.linspace(0.12, 1.0, ramp))
        bed = audio.duck_under(bed * gain, voice, amount=0.5)
        mix = voice + 0.2 * bed[:n] + 0.35 * sfx
    else:
        bed = audio.duck_under(audio.music_bed(n / SR), voice)
        mix = voice + 0.17 * bed[:n] + 0.35 * sfx
    raw = path.replace(".wav", "-raw.wav")
    audio.write(raw, mix[: int(total * SR)])
    audio.loudnorm(raw, path)


def render_video(ep, total, wav, ass, out_mp4):
    global FADE, CANVAS, BRAND_HDR, BRAND_BADGE
    print("[3/4] Rendering frames + burning captions…", flush=True)
    bg = make_background()
    BRAND_HDR, BRAND_BADGE = brand.lockup(62), brand.badge(300)
    frames = int(np.ceil(total * FPS))
    cmd = ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-r", str(FPS), "-i", "-", "-i", wav, "-vf", f"ass={ass}:fontsdir={FONT_DIR}", "-c:v", "libx264",
           "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p", "-profile:v", "high",
           "-movflags", "+faststart", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-shortest", out_mp4]
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    scenes = ep["scenes"]
    started = time.time()
    cover = None
    reveals = [(s["_start"] + t, k) for s in scenes for t, k in s.get("_fx", [])]

    def punch(T):  # zoom punch and white flash when something big lands
        z = fl = 0.0
        for tr, k in reveals:
            dt = T - tr
            if 0 <= dt < 0.5:
                z = max(z, k * 0.065 * (1 - dt / 0.5) ** 2)
                if k >= 1.0 and dt < 0.14:
                    fl = max(fl, 0.24 * (1 - dt / 0.14))
        return z, fl

    for fi in range(frames):
        T = fi / FPS
        sc = next((s for s in scenes if s["_start"] <= T < s["_start"] + s["_dur"]), scenes[-1])
        t = T - sc["_start"]
        last = sc is scenes[-1]
        ox = int(PAN_X / 2 + PAN_X * 0.4 * math.sin(2 * math.pi * T / 19))
        oy = int(PAN_Y / 2 + PAN_Y * 0.4 * math.sin(2 * math.pi * T / 27 + 1.3))
        img = CANVAS = bg.crop((ox, oy, ox + W, oy + H))
        d = ImageDraw.Draw(img, "RGBA")
        draw_header(img, d, ep)
        fade_in = 1.0 if sc is scenes[0] else ease_out(prog(t, 0, 0.18))  # frame 1 must hook
        FADE = min(fade_in, 1.0 if last else clamp((sc["_dur"] - t) / 0.16))
        DRAW[sc["type"]](img, d, sc, t, sc["_dur"])
        FADE = 1.0
        z, fl = punch(T)
        if z > 0.002:
            zw, zh = int(W * (1 + z)), int(H * (1 + z))
            img = img.resize((zw, zh), Image.BILINEAR).crop(((zw - W) // 2, (zh - H) // 2, (zw - W) // 2 + W, (zh - H) // 2 + H))
            d = ImageDraw.Draw(img, "RGBA")
        if fl > 0:
            d.rectangle((0, 0, W, H), fill=(255, 255, 255, int(255 * fl)))
        d.rectangle((0, 0, W * T / total, 8), fill=YELLOW + (255,))
        if cover is None and sc["type"] == "hook" and t >= cue(sc, sc.get("pill_cue"), 2.0) + 0.8:
            cover = img.copy()
        ff.stdin.write(img.tobytes())
        if fi % 150 == 0:
            print(f"      frame {fi}/{frames}  ({time.time() - started:.0f}s)", flush=True)
    ff.stdin.close()
    if ff.wait() != 0:
        raise SystemExit("ffmpeg failed")
    return cover


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("episode")
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    args = ap.parse_args()
    with open(args.episode, encoding="utf-8") as f:
        ep = json.load(f)
    work = os.path.join(ROOT, ".cache", f"congress-{ep['id']}")
    os.makedirs(work, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)

    total = prepare(ep, work)
    wav = os.path.join(work, "mix.wav")
    build_audio(ep, total, wav)
    all_words = [dict(w, start=w["start"] + s["_start"], end=w["end"] + s["_start"])
                 for s in ep["scenes"] for w in s["_words"]]
    ass = captions.write_ass(all_words, os.path.join(work, "captions.ass"), y=1450)
    with open(os.path.join(work, "words.json"), "w") as f:
        json.dump(all_words, f, indent=1)

    base = os.path.join(args.out, ep.get("slug") or f"congress-trades-{ep['id']}")
    cover = render_video(ep, total, wav, ass, base + ".mp4")
    print("[4/4] Writing cover + post text…", flush=True)
    if cover:
        cover.save(base + "-cover.png")
    post = ep.get("post", {})
    with open(base + "-post.txt", "w", encoding="utf-8") as f:
        f.write(f"{post.get('title', '')}\n\n{post.get('description', '')}\n\n{' '.join(post.get('hashtags', []))}\n")
    # What the auto-poster (tools/publish.py) checks before it will put this video online.
    qa = dict(ep.get("_qa", {}), episode=os.path.abspath(args.episode), video=base + ".mp4",
              duration=round(total, 2), rendered_at=dt.datetime.now().astimezone().isoformat(timespec="seconds"),
              **probe(base + ".mp4"))
    with open(base + "-qa.json", "w") as f:
        json.dump(qa, f, indent=1)
    if qa["warnings"]:
        print("QA warnings (the auto-poster will refuse this video until they're fixed):")
        for w in qa["warnings"]:
            print("   -", w)
    print(f"Done: {base}.mp4  ({total:.1f}s)")


def probe(path):
    """Frame size, streams and length of the finished file."""
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,width,height",
                          "-show_entries", "format=duration", "-of", "json", path],
                         capture_output=True, text=True, check=True).stdout
    info = json.loads(out)
    vid = next((s for s in info["streams"] if s["codec_type"] == "video"), {})
    return {"width": vid.get("width"), "height": vid.get("height"),
            "has_audio": any(s["codec_type"] == "audio" for s in info["streams"]),
            "file_duration": round(float(info["format"]["duration"]), 2)}


if __name__ == "__main__":
    main()
