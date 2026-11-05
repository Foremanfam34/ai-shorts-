#!/usr/bin/env python3
"""Make a ~3 minute two-host podcast video (original script, local TTS) to test the clipper on.

    python3 clipper/demo/make_sample_podcast.py   -> samples/side-quest-ep12.mp4
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from shortkit import FONT_DIR, ROOT, audio  # noqa: E402
from shortkit.tts import SAMPLE_RATE as SR, Voice  # noqa: E402

HOSTS = {"M": ("Maya", "af_heart", (255, 128, 86)), "J": ("Jordan", "am_fenrir", (86, 160, 255))}
SCRIPT = [
    ("M", "Welcome back to Side Quest. I'm Maya."),
    ("J", "And I'm Jordan. Today we're talking about why most side hustles die in the first ninety days."),
    ("M", "And honestly, it's almost never because the idea was bad."),
    ("J", "Right. So here's something I didn't expect. We surveyed our listeners, and asked people who quit a side project why they stopped. Do you want to guess the number one answer?"),
    ("M", "Money? Like, it just wasn't making any?"),
    ("J", "That was number three. Number one was, and I'm quoting here, I got bored of doing the same thing every day."),
    ("M", "Oh, that hurts. Because that's the whole game, right? The boring part is the business."),
    ("J", "Exactly. Nobody quits during the fun part. You quit in week six, when the logo is done, the website is live, and now you just have to show up and do it again. And again."),
    ("M", "I call that the valley of nothing. You're doing all the work, and the numbers don't move. Zero sales, eleven views, and your mom liked the post."),
    ("J", "Your mom is always your first customer."),
    ("M", "But here's what people miss. The valley of nothing is where everyone else quits too. So if you can just survive it, most of your competition disappears on its own."),
    ("J", "It's a filter. The ninety day filter."),
    ("M", "Okay, so practical advice. What actually gets people through it?"),
    ("J", "Three things. First, make it smaller. If your plan needs two hours a day, it's going to break the first time life gets busy. Build a version that takes twenty minutes."),
    ("M", "Twenty minutes every day beats a perfect weekend once a month."),
    ("J", "Every single time. Second, measure inputs, not outputs. You can't control how many people buy. You can control whether you published today."),
    ("M", "I love that. Track the reps, not the results."),
    ("J", "And third, the one nobody likes. Pick an end date in advance. Say, I'm doing this until March first, no matter what. Then you're not deciding again every single morning whether it's worth it."),
    ("M", "Because deciding over and over is exhausting. That's what actually burns people out. Not the work."),
    ("J", "Decision fatigue kills more side hustles than competitors ever will."),
    ("M", "Okay, that one's going on a mug."),
    ("J", "Put it on the mug."),
    ("M", "Before we go, one thing I really want people to hear. If you quit something before, that's not proof you're not cut out for this. It usually just means the plan was too big for your real life."),
    ("J", "Shrink the plan, not the dream."),
    ("M", "Shrink the plan, not the dream. That's the episode. See you next week."),
]

W, H = 1920, 1080
FONT = os.path.join(FONT_DIR, "Inter-{}.otf")


def f(weight, size):
    return ImageFont.truetype(FONT.format(weight), size)


def frame(active):
    y = np.linspace(0, 1, H)[:, None, None]
    img = Image.fromarray((np.array([12, 14, 24]) * (1 - y) + np.array([26, 22, 40]) * y)
                          .repeat(W, axis=1).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img, "RGBA")
    d.text((90, 92), "SIDE QUEST", font=f("Black", 46), fill=(255, 214, 10), anchor="lm")
    d.text((420, 92), "Ep. 12  ·  Why side hustles die in 90 days", font=f("Medium", 32),
           fill=(170, 175, 195), anchor="lm")
    for i, key in enumerate(("M", "J")):
        name, _, color = HOSTS[key]
        x0 = 90 + i * 900
        box = (x0, 170, x0 + 840, 830)
        on = key == active
        d.rounded_rectangle(box, radius=36, fill=(32, 34, 52, 255),
                            outline=(255, 214, 10, 255) if on else (60, 62, 84, 255), width=8 if on else 2)
        cx = x0 + 420
        d.ellipse((cx - 150, 270, cx + 150, 570), fill=color + (255,))
        d.text((cx, 420), name[0], font=f("Black", 160), fill=(255, 255, 255), anchor="mm")
        d.text((cx, 650), name, font=f("Bold", 56), fill=(240, 242, 248), anchor="mm")
        d.text((cx, 712), "Host", font=f("Medium", 30), fill=(150, 155, 175), anchor="mm")
        if on:
            d.rounded_rectangle((x0 + 30, 200, x0 + 236, 248), radius=24, fill=(255, 214, 10, 255))
            d.text((x0 + 133, 224), "SPEAKING", font=f("ExtraBold", 24), fill=(20, 20, 30), anchor="mm")
    return img


def main():
    out_dir = os.path.join(ROOT, "samples")
    work = os.path.join(ROOT, ".cache", "sample-podcast")
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(work, exist_ok=True)
    voice = Voice([t for _, t in SCRIPT])
    rng = np.random.default_rng(3)
    parts, timeline, t = [], [], 0.6
    parts.append(np.zeros(int(0.6 * SR), dtype=np.float32))
    for key, text in SCRIPT:
        a = voice.say(text, HOSTS[key][1], speed=1.04)
        timeline.append((key, t, t + len(a) / SR))
        gap = float(rng.uniform(0.28, 0.55))
        parts += [a, np.zeros(int(gap * SR), dtype=np.float32)]
        t += len(a) / SR + gap
        print(f"  {HOSTS[key][0]:>6}: {text[:60]}…")
    parts.append(np.zeros(int(1.0 * SR), dtype=np.float32))
    track = np.concatenate(parts)
    wav = os.path.join(work, "podcast.wav")
    audio.write(wav, track * 0.9)

    for key in ("M", "J", None):
        frame(key).save(os.path.join(work, f"frame_{key or 'none'}.png"))
    lines, cursor = [], 0.0
    for key, s, e in timeline:
        if s > cursor:
            lines += [f"file 'frame_none.png'", f"duration {s - cursor:.3f}"]
        lines += [f"file 'frame_{key}.png'", f"duration {e - s:.3f}"]
        cursor = e
    lines += ["file 'frame_none.png'", f"duration {len(track) / SR - cursor:.3f}", "file 'frame_none.png'"]
    with open(os.path.join(work, "frames.txt"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    out = os.path.join(out_dir, "side-quest-ep12.mp4")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "concat", "-safe", "0",
                    "-i", os.path.join(work, "frames.txt"), "-i", wav, "-filter_complex",
                    "[1:a]showwaves=s=1200x150:mode=cline:rate=30:colors=0xFFD60A@0.85[w];"
                    "[0:v]fps=30,format=yuv420p[b];[b][w]overlay=360:875:shortest=1[v]",
                    "-map", "[v]", "-map", "1:a", "-c:v", "libx264", "-preset", "veryfast", "-crf", "21",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", out], check=True)
    print(f"Done: {out}  ({len(track) / SR:.0f}s)")


if __name__ == "__main__":
    main()
