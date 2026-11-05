#!/usr/bin/env python3
"""Make an Instagram Reels version of a finished Short.

    python3 tools/reels.py out/market-selloff-2026-11-05.mp4    -> out/market-selloff-2026-11-05-reels.mp4

The Shorts are already 1080x1920, but Instagram covers more of the frame: the "Reels" label and status
bar at the top, the username/caption/audio rows at the bottom, the like/comment column on the right,
and the main feed crops Reels to 4:5. This shrinks the whole video to 86% and sets it as a rounded card
on the brand's dark navy, so the header sits inside the 4:5 feed crop, the captions end about 75 px
above Instagram's bottom text, and no text reaches the button column. Audio is copied untouched.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

W, H = 1080, 1920
SCALE = 0.86
CW, CH = int(W * SCALE) // 2 * 2, int(H * SCALE) // 2 * 2   # 928 x 1650 card
X, Y = (W - CW) // 2, 150                   # 76 px sides, 150 px top: header lands at ~y 298
RADIUS = 44
BG = "0x070a13"                             # brand NAVY_LO


def masks(tmp):
    ss = 4                                  # draw large and downsample for smooth corners
    m = Image.new("L", (CW * ss, CH * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, CW * ss - 1, CH * ss - 1), radius=RADIUS * ss, fill=255)
    m.resize((CW, CH), Image.LANCZOS).save(os.path.join(tmp, "mask.png"))
    edge = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((X * ss, Y * ss, (X + CW) * ss - 1, (Y + CH) * ss - 1),
                                           radius=RADIUS * ss, outline=(255, 255, 255, 26), width=2 * ss)
    edge.resize((W, H), Image.LANCZOS).save(os.path.join(tmp, "edge.png"))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    dst = os.path.splitext(src)[0] + "-reels.mp4"
    with tempfile.TemporaryDirectory() as tmp:
        masks(tmp)
        graph = (f"color=c={BG}:s={W}x{H}:r=30[bg];"
                 f"[0:v]scale={CW}:{CH}:flags=lanczos,format=rgba[v];"
                 f"[1:v]format=gray[m];[v][m]alphamerge[card];"
                 f"[bg][card]overlay={X}:{Y}:shortest=1[a];"
                 f"[a][2:v]overlay=0:0:shortest=1,format=yuv420p[out]")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src,
                        "-loop", "1", "-i", os.path.join(tmp, "mask.png"),
                        "-loop", "1", "-i", os.path.join(tmp, "edge.png"),
                        "-filter_complex", graph, "-map", "[out]", "-map", "0:a",
                        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", "30",
                        "-c:a", "copy", "-shortest", "-movflags", "+faststart", dst], check=True)
    print("Done:", dst)


if __name__ == "__main__":
    main()
