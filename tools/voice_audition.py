#!/usr/bin/env python3
"""Hear the narrator options side by side: each voice reads the same line with the same
natural pacing and warmth processing used in the videos.

    python3 tools/voice_audition.py ["Your line here"]          -> out/voice-audition.mp4
    python3 tools/voice_audition.py --male ["Your line here"]   -> out/voice-audition-male.mp4
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from shortkit import FONT_DIR, ROOT, audio  # noqa: E402
from shortkit.tts import SAMPLE_RATE as SR, Voice  # noqa: E402

LINE = ("Okay, this one's wild. Nancy Pelosi's filings show up to thirteen million dollars of Intel "
        "buys... and then Intel fell twenty nine percent. In one day.")
CAST = [("af_heart", "Warm and calm", "Recommended"), ("af_bella", "Bright and expressive", ""),
        ("af_nicole", "Soft, almost whispered", ""), ("bf_emma", "British, polished", "")]
MALE_LINE = ("Datadog crushed earnings today... and the stock still fell fourteen percent. "
             "On a day the S and P five hundred jumped one point seven percent.")
MALE_CAST = [("am_michael", "Firm and clear", "Recommended"), ("am_onyx", "Deepest", ""),
             ("am_fenrir", "Brighter, more energy", ""), ("bm_george", "British, authoritative", "")]
W, H = 1080, 1920


def card(i, voice, desc, tag):
    img = Image.new("RGB", (W, H), (12, 15, 26))
    d = ImageDraw.Draw(img)
    f = lambda w, s: ImageFont.truetype(os.path.join(FONT_DIR, f"Inter-{w}.otf"), s)
    d.text((W // 2, 640), f"VOICE {i + 1} OF {len(CAST)}", font=f("Bold", 40), fill=(150, 158, 180), anchor="mm")
    d.text((W // 2, 790), voice, font=f("Black", 120), fill=(255, 214, 10), anchor="mm")
    d.text((W // 2, 930), desc, font=f("SemiBold", 56), fill=(242, 244, 248), anchor="mm")
    if tag:
        d.rounded_rectangle((W // 2 - 190, 1020, W // 2 + 190, 1100), radius=40, fill=(34, 211, 102))
        d.text((W // 2, 1060), tag.upper(), font=f("ExtraBold", 38), fill=(10, 12, 20), anchor="mm")
    return img


def main():
    global CAST
    args = [a for a in sys.argv[1:] if a != "--male"]
    male = "--male" in sys.argv
    if male:
        CAST = MALE_CAST
    line = args[0] if args else (MALE_LINE if male else LINE)
    speed, pause_scale = (1.1, 0.8) if male else (1.06, 1.0)
    work = os.path.join(ROOT, ".cache", "audition")
    os.makedirs(work, exist_ok=True)
    voice = Voice([line])
    parts, lst = [], []
    for i, (name, desc, tag) in enumerate(CAST):
        a = audio.voice_fx(voice.say_natural(line, name, speed, seed=1, pause_scale=pause_scale))
        a = np.concatenate([np.zeros(int(0.5 * SR), np.float32), a, np.zeros(int(0.8 * SR), np.float32)])
        parts.append(a)
        path = os.path.join(work, f"card{i}.png")
        card(i, name, desc, tag).save(path)
        lst += [f"file '{path}'", f"duration {len(a) / SR:.3f}"]
    lst.append(f"file '{os.path.join(work, f'card{len(CAST) - 1}.png')}'")
    with open(os.path.join(work, "cards.txt"), "w") as fh:
        fh.write("\n".join(lst) + "\n")
    wav = os.path.join(work, "audition.wav")
    audio.write(wav + ".raw.wav", np.concatenate(parts))
    audio.loudnorm(wav + ".raw.wav", wav)
    out = os.path.join(ROOT, "out", "voice-audition-male.mp4" if male else "voice-audition.mp4")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i",
                    os.path.join(work, "cards.txt"), "-i", wav, "-vf", "fps=30,format=yuv420p", "-c:v", "libx264",
                    "-preset", "veryfast", "-crf", "22", "-c:a", "aac", "-b:a", "160k", "-shortest", out], check=True)
    print("Done:", out)


if __name__ == "__main__":
    main()
