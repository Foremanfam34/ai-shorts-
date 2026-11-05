#!/usr/bin/env python3
"""Long video -> vertical Shorts / Reels / TikToks with a hook title and word-by-word captions.

    python3 clipper/clip.py all VIDEO [--n 5]           transcribe, let Claude pick moments, render
    python3 clipper/clip.py transcribe VIDEO            -> .cache/clipper/<name>/transcript.{json,txt}
    python3 clipper/clip.py pick VIDEO [--n 5]          -> .cache/clipper/<name>/moments.json (Claude API)
    python3 clipper/clip.py render VIDEO [--moments FILE] [--layout fill|crop]

`fill` (default) keeps the whole 16:9 frame over a blurred copy of itself, which works for any
video. `crop` cuts a centered 9:16 window, best for a single speaker framed in the middle.
Only clip videos you own or have permission to use.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
from shortkit import FONT_DIR, ROOT, audio, captions  # noqa: E402

W, H = 1080, 1920
YELLOW_BGR = "&H000AD6FF"  # #FFD60A


def workdir(video):
    stem = os.path.splitext(os.path.basename(video))[0]
    d = os.path.join(ROOT, ".cache", "clipper", stem)
    os.makedirs(d, exist_ok=True)
    return stem, d


def probe(video):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height:format=duration", "-of", "json", video],
                         capture_output=True, text=True, check=True).stdout
    j = json.loads(out)
    return j["streams"][0]["width"], j["streams"][0]["height"], float(j["format"]["duration"])


def sentences(words, max_len=18.0, max_gap=0.7):
    """Group words into sentence-sized transcript lines (what the editor model reads)."""
    out, cur = [], []
    for w in words:
        if cur and (w["start"] - cur[-1]["end"] > max_gap or w["end"] - cur[0]["start"] > max_len):
            out.append(cur)
            cur = []
        cur.append(w)
        if w["w"][-1:] in ".?!":
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return [{"start": c[0]["start"], "end": c[-1]["end"], "text": " ".join(x["w"] for x in c)} for c in out]


def cmd_transcribe(video):
    from shortkit.asr import Transcriber, load_audio
    stem, wd = workdir(video)
    print(f"[transcribe] {video}")
    samples = load_audio(video)
    words, _ = Transcriber().transcribe(
        samples, progress=lambda i, n: print(f"\r  speech segment {i}/{n}", end="", flush=True))
    print()
    lines = sentences(words)
    with open(os.path.join(wd, "transcript.json"), "w") as f:
        json.dump({"words": words, "lines": lines}, f, indent=1)
    with open(os.path.join(wd, "transcript.txt"), "w") as f:
        for s in lines:
            f.write(f"[{s['start']:.1f}-{s['end']:.1f}] {s['text']}\n")
    print(f"  {len(words)} words, {len(lines)} lines -> {wd}/transcript.txt")


def cmd_pick(video, n, context):
    from pick import pick_moments
    stem, wd = workdir(video)
    if not os.path.exists(os.path.join(wd, "transcript.txt")):
        cmd_transcribe(video)
    with open(os.path.join(wd, "transcript.txt")) as f:
        transcript = f.read()
    print(f"[pick] asking Claude for the {n} best moments…")
    clips = pick_moments(transcript, n=n, context=context)
    with open(os.path.join(wd, "moments.json"), "w") as f:
        json.dump(clips, f, indent=2)
    for c in clips:
        print(f"  {c['score']:>2}/10  {c['start']:7.1f}-{c['end']:7.1f}  {c['title']}")


def snap(clip, words, total, pad_in=0.12, pad_out=0.45):
    """Snap the editor's times to word boundaries so clips never start or end mid-word."""
    inside = [w for w in words if w["start"] >= clip["start"] - 0.3 and w["end"] <= clip["end"] + 0.3]
    if not inside:
        raise ValueError(f"no words between {clip['start']} and {clip['end']}")
    return max(0.0, inside[0]["start"] - pad_in), min(total, inside[-1]["end"] + pad_out)


def run(cmd):
    subprocess.run(cmd, check=True)


def cmd_render(video, moments_path, layout, outdir):
    stem, wd = workdir(video)
    with open(os.path.join(wd, "transcript.json")) as f:
        words = json.load(f)["words"]
    with open(moments_path or os.path.join(wd, "moments.json")) as f:
        clips = json.load(f)
    vw, vh, total = probe(video)
    os.makedirs(outdir, exist_ok=True)

    if layout == "crop":
        title_y, cap_y = 330, 1350
        base_filter = f"[0:v]crop=ih*9/16:ih:(iw-ow)/2:0,scale={W}:{H},setsar=1[v1]"
    else:
        fg_h = int(round(W * vh / vw / 2) * 2)
        fg_y = 860 - fg_h // 2
        title_y, cap_y = fg_y - 150, fg_y + fg_h + 170
        base_filter = (f"[0:v]split=2[a][b];[a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
                       f"boxblur=30:3,eq=brightness=-0.18:saturation=1.25[bg];[b]scale={W}:{fg_h},setsar=1[fg];"
                       f"[bg][fg]overlay=0:{fg_y}[v1]")
    title_style = (f"Style: Title,Inter Black,62,&H00141110,&H00141110,{YELLOW_BGR},{YELLOW_BGR},0,0,0,0,"
                   f"100,100,0,0,3,18,0,5,90,90,0,1")

    index = []
    for k, c in enumerate(clips, 1):
        s, e = snap(c, words, total)
        dur = e - s
        cw = [dict(w, start=round(w["start"] - s, 3), end=round(w["end"] - s, 3))
              for w in words if w["start"] >= s and w["end"] <= e + 0.05]
        name = f"{stem}-clip{k:02d}"
        base = os.path.join(outdir, name)
        ass = os.path.join(wd, f"clip{k:02d}.ass")
        title = captions.escape(c["title"].upper())
        captions.write_ass(cw, ass, y=cap_y, styles=[title_style],
                           extra_events=[(0, dur, "Title", f"{{\\an5\\pos({W // 2},{title_y})}}{title}")])
        raw, norm = os.path.join(wd, f"clip{k:02d}-raw.wav"), os.path.join(wd, f"clip{k:02d}.wav")
        run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", f"{s:.3f}", "-t", f"{dur:.3f}", "-i", video,
             "-vn", "-ac", "2", "-ar", "48000", raw])
        audio.loudnorm(raw, norm)
        graph = (f"{base_filter};color=c=0xFFD60A:s={W}x10:d={dur:.3f}[pb];"
                 f"[v1][pb]overlay=x='-w+w*t/{dur:.3f}':y=0:shortest=1,ass={ass}:fontsdir={FONT_DIR}[v]")
        print(f"[render] clip {k}: {s:.1f}-{e:.1f}s ({dur:.0f}s)  {c['title']}")
        run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", f"{s:.3f}", "-t", f"{dur:.3f}", "-i", video,
             "-i", norm, "-filter_complex", graph, "-map", "[v]", "-map", "1:a", "-r", "30",
             "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
             "-movflags", "+faststart", "-c:a", "aac", "-b:a", "192k", "-shortest", base + ".mp4"])
        run(["ffmpeg", "-v", "error", "-y", "-ss", "1.0", "-i", base + ".mp4", "-frames:v", "1", base + "-cover.png"])
        tags = " ".join(t if t.startswith("#") else "#" + t for t in c.get("hashtags", []))
        with open(base + "-post.txt", "w", encoding="utf-8") as f:
            f.write(f"{c['title']}\n\n{c['caption']}\n\n{tags}\n")
        index.append({"file": name + ".mp4", "start": round(s, 2), "end": round(e, 2), **c})
    with open(os.path.join(outdir, "clips.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=2)
    print(f"Done: {len(index)} clips in {outdir}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["all", "transcribe", "pick", "render"])
    ap.add_argument("video")
    ap.add_argument("--n", type=int, default=5, help="number of clips to pick")
    ap.add_argument("--context", default="", help="who/what the video is, to help the editor")
    ap.add_argument("--moments", help="use this moments JSON instead of moments.json")
    ap.add_argument("--layout", choices=["fill", "crop"], default="fill")
    ap.add_argument("--out", help="output folder (default out/clips/<video name>)")
    a = ap.parse_args()
    out = a.out or os.path.join(ROOT, "out", "clips", workdir(a.video)[0])
    if a.command in ("all", "transcribe"):
        cmd_transcribe(a.video)
    if a.command in ("all", "pick"):
        cmd_pick(a.video, a.n, a.context)
    if a.command in ("all", "render"):
        cmd_render(a.video, a.moments, a.layout, out)


if __name__ == "__main__":
    main()
