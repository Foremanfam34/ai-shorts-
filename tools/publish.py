#!/usr/bin/env python3
"""Put a finished Stock Geek Short on YouTube through Postiz, so the daily run can publish on its own.

    python3 tools/publish.py check                               # connected? which channel? its posting rules
    python3 tools/publish.py youtube EPISODE.json --at 19:00     # upload + schedule (time is US/Eastern)
    python3 tools/publish.py youtube EPISODE.json --dry-run      # run every check, post nothing
    python3 tools/publish.py hold POST_ID                        # pull a scheduled post back to draft
    python3 tools/publish.py release POST_ID                     # put a held post back on its schedule
    python3 tools/publish.py status --days 7 --views             # recent posts, their YouTube links and views

Needs the `postiz` CLI (setup.sh installs it) and POSTIZ_API_KEY (Postiz -> Settings -> Public API),
plus api.postiz.com allowed in the environment's network settings.

Nothing goes online unless every check passes: the render's QA report has no warnings, the file is a
1080x1920 video with sound, the video is newer than its episode file, the title fits, and this video
isn't already scheduled. Every scheduled post is logged in publish/log.jsonl.
"""
import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from zoneinfo import ZoneInfo

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ET = ZoneInfo("America/New_York")
LOG = os.path.join(ROOT, "publish", "log.jsonl")
BASE_TAGS = ["stocks", "stock market", "Stock Geek", "investing", "market news"]
NOT_CONNECTED, GATE_FAILED = 2, 5


class Problem(Exception):
    pass


# ---------------------------------------------------------------- Postiz CLI
def first_json(text):
    """The CLI prints a status line before its JSON; return the first JSON value in the output."""
    dec = json.JSONDecoder()
    for i, ch in enumerate(text):
        if ch in "[{":
            try:
                return dec.raw_decode(text[i:])[0]
            except json.JSONDecodeError:
                continue
    return None


def cli(*args):
    if not os.environ.get("POSTIZ_API_KEY"):
        raise Problem("POSTIZ_API_KEY isn't set, so Postiz isn't connected.")
    if not shutil.which("postiz"):
        raise Problem("The postiz CLI isn't installed. Run: npm install -g postiz")
    p = subprocess.run(["postiz", *args], capture_output=True, text=True, timeout=900)
    out = (p.stdout or "") + (p.stderr or "")
    if p.returncode != 0:
        if re.search(r"ECONNREFUSED|ENOTFOUND|fetch failed|tunnel|403 Forbidden|ECONNRESET", out):
            raise Problem("Can't reach api.postiz.com. Add it under Allowed domains in the environment's "
                          "network settings.\n" + out.strip()[-400:])
        raise Problem(f"postiz {args[0]} failed:\n{out.strip()[-800:]}")
    return first_json(p.stdout)


def items(data, *keys):
    if isinstance(data, list):
        return data
    for k in keys:
        if isinstance((data or {}).get(k), list):
            return data[k]
    return []


def youtube_channel():
    found = items(cli("integrations:list"), "integrations", "output")
    yt = [i for i in found if (i.get("identifier") or i.get("providerIdentifier")) == "youtube"
          and not i.get("disabled")]
    want = os.environ.get("POSTIZ_YOUTUBE_ID")
    if want:
        yt = [i for i in yt if i.get("id") == want]
    if not yt:
        raise Problem("No YouTube channel is connected in Postiz. In Postiz: Add Channel -> YouTube.")
    geek = [i for i in yt if "geek" in (i.get("name") or "").lower()]
    return (geek or yt)[0]


def post_settings(p):
    s = p.get("settings")
    if isinstance(s, str):
        try:
            s = json.loads(s)
        except json.JSONDecodeError:
            s = {}
    return s or {}


def utc(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def list_posts(start, end):
    return items(cli("posts:list", "--startDate", utc(start), "--endDate", utc(end)), "posts", "output")


# ---------------------------------------------------------------- checks + text
def clean(s):
    # YouTube rejects < and > anywhere in a title or description
    return (s or "").replace("<", "‹").replace(">", "›").strip()


def tag_list(post):
    seen, out, used = set(), [], 0
    for t in [h.lstrip("#").strip() for h in post.get("hashtags", [])] + BASE_TAGS:
        cost = len(t) + (2 if " " in t else 0) + 1   # YouTube quotes tags with spaces; +1 for the comma
        if not t or t.lower() in seen or used + cost > 450:
            continue
        seen.add(t.lower())
        out.append({"value": t, "label": t})
        used += cost
    return out


def build(ep, privacy):
    post = ep.get("post") or {}
    title = clean(post.get("title"))
    desc = clean(post.get("description"))
    if "ai voice" not in desc.lower():
        desc += "\n\nNarrated with an AI voice."
    if post.get("hashtags"):
        desc += "\n\n" + " ".join(post["hashtags"])
    settings = {"title": title, "type": privacy, "selfDeclaredMadeForKids": "no", "tags": tag_list(post)}
    return title, desc, settings


def gates(ep_path, ep, out_dir, title, desc, allow_warnings=False):
    slug = ep.get("slug") or f"congress-trades-{ep['id']}"
    video = os.path.join(out_dir, slug + ".mp4")
    qa_path = os.path.join(out_dir, slug + "-qa.json")
    bad = []
    if not os.path.exists(video):
        return video, [f"no video at {video}: render it first"]
    if not os.path.exists(qa_path):
        return video, [f"no QA report at {qa_path}: re-render with the current congress/render.py"]
    with open(qa_path) as f:
        qa = json.load(f)
    if qa.get("warnings") and not allow_warnings:
        bad += [f"render warning: {w}" for w in qa["warnings"]]
    if (qa.get("width"), qa.get("height")) != (1080, 1920):
        bad.append(f"video is {qa.get('width')}x{qa.get('height')}, not 1080x1920")
    if not qa.get("has_audio"):
        bad.append("video has no sound")
    if not 10 <= (qa.get("file_duration") or 0) <= 180:
        bad.append(f"video is {qa.get('file_duration')}s long (Shorts must be 10-180s)")
    if os.path.realpath(qa.get("episode", "")) != os.path.realpath(ep_path):
        bad.append("the QA report belongs to a different episode file")
    if os.path.getmtime(video) < os.path.getmtime(ep_path):
        bad.append("the episode file changed after the video was rendered: re-render it")
    if not 2 <= len(title) <= 100:
        bad.append(f"title is {len(title)} characters (YouTube allows 2-100)")
    if len(desc) > 4900:
        bad.append(f"description is {len(desc)} characters (YouTube allows 5000)")
    if not (ep.get("post") or {}).get("description"):
        bad.append("episode has no post description")
    return video, bad


def when(at, now=None):
    now = now or dt.datetime.now(ET)
    if at == "now":
        return now + dt.timedelta(minutes=3)
    m = re.fullmatch(r"(\d{1,2}):(\d{2})", at)
    if m:
        t = now.replace(hour=int(m[1]), minute=int(m[2]), second=0, microsecond=0)
        # past today's slot (a late run): go out shortly instead, still leaving a few minutes to hold it
        return max(t, now + dt.timedelta(minutes=10))
    t = dt.datetime.fromisoformat(at.replace("Z", "+00:00"))
    t = t if t.tzinfo else t.replace(tzinfo=ET)
    if t < now + dt.timedelta(minutes=2):
        raise Problem(f"--at {at} is in the past")
    return t


def nice(t):
    t = t.astimezone(ET)
    return t.strftime("%a %b %-d, %-I:%M %p ET")


def log(entry):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(dict(entry, logged_at=dt.datetime.now(ET).isoformat(timespec="seconds"))) + "\n")


# ---------------------------------------------------------------- commands
def cmd_check(_):
    ch = youtube_channel()
    print(f"Connected. YouTube channel: {ch.get('name')} (id {ch.get('id')})")
    info = cli("integrations:settings", ch["id"]) or {}
    out = info.get("output", info)
    if out.get("rules"):
        print("\nPostiz posting rules for this channel:\n" + str(out["rules"]).strip())
    props = ((out.get("settings") or {}).get("properties")) or {}
    for k, v in props.items():
        if isinstance(v, dict) and v.get("description"):
            print(f"  - {k}: {v['description']}")


def cmd_youtube(a):
    with open(a.episode, encoding="utf-8") as f:
        ep = json.load(f)
    title, desc, settings = build(ep, a.privacy)
    video, bad = gates(a.episode, ep, a.out, title, desc, a.allow_warnings)
    if bad:
        print("NOT POSTED. Fix these first:\n" + "\n".join(f"  - {b}" for b in bad))
        return GATE_FAILED
    go = when(a.at)
    plan = {"title": title, "privacy": a.privacy, "goes_live": nice(go), "goes_live_utc": utc(go),
            "video": video, "size_mb": round(os.path.getsize(video) / 1e6, 1),
            "tags": [t["label"] for t in settings["tags"]], "description": desc}
    if a.dry_run:
        print("DRY RUN: every check passed. Would post:")
        print(json.dumps(plan, indent=1, ensure_ascii=False))
        return 0
    ch = youtube_channel()
    for p in list_posts(go - dt.timedelta(days=4), go + dt.timedelta(days=4)):
        same_channel = ((p.get("integration") or {}).get("id") or ch["id"]) == ch["id"]
        if same_channel and post_settings(p).get("title") == title and not p.get("deletedAt"):
            print(f"NOT POSTED: this video is already in Postiz (post {p.get('id')}, "
                  f"{p.get('state') or p.get('status')}, {p.get('publishDate')}).")
            return GATE_FAILED
    media = cli("upload", video) or {}
    if not media.get("path"):
        raise Problem(f"Postiz upload returned no path: {media}")
    payload = {"type": "schedule", "creationMethod": "CLI", "date": utc(go), "shortLink": False, "tags": [],
               "posts": [{"integration": {"id": ch["id"]},
                          "value": [{"content": desc, "delay": 0,
                                     "image": [{"id": media.get("id") or os.path.basename(video),
                                                "path": media["path"]}]}],
                          "settings": settings}]}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    try:
        res = cli("posts:create", "--json", f.name)
    finally:
        os.unlink(f.name)
    ids = [x.get("postId") or x.get("id") for x in items(res, "posts", "output") if isinstance(x, dict)]
    if not ids and isinstance(res, dict):
        ids = [res.get("postId") or res.get("id")]
    ids = [i for i in ids if i]
    result = dict(plan, postiz_id=ids[0] if ids else None, channel=ch.get("name"))
    result.pop("description")
    log(dict(result, action="scheduled", episode=os.path.relpath(os.path.abspath(a.episode), ROOT)))
    print("SCHEDULED:")
    print(json.dumps(result, indent=1, ensure_ascii=False))
    return 0


def cmd_status(a):
    now = dt.datetime.now(ET)
    ch = youtube_channel()
    rows = []
    for p in list_posts(now - dt.timedelta(days=a.days), now + dt.timedelta(days=3)):
        if ((p.get("integration") or {}).get("id") or ch["id"]) != ch["id"] or p.get("deletedAt"):
            continue
        row = {"postiz_id": p.get("id"), "state": p.get("state") or p.get("status"),
               "publish_at": p.get("publishDate"), "title": post_settings(p).get("title"),
               "url": p.get("releaseURL") or "", "error": p.get("error") or ""}
        if a.views and row["url"]:
            try:
                for m in items(cli("analytics:post", row["postiz_id"], "-d", "7"), "output"):
                    if str(m.get("label", "")).lower() in ("views", "likes", "comments") and m.get("data"):
                        row[m["label"].lower()] = int(float(m["data"][-1].get("total") or 0))
            except (Problem, ValueError, TypeError) as e:
                row["views_error"] = str(e)[:200]
        rows.append(row)
    print(json.dumps(rows, indent=1, ensure_ascii=False))


def cmd_status_change(a, status):
    res = cli("posts:status", a.post_id, "--status", status)
    log({"action": "hold" if status == "draft" else "release", "postiz_id": a.post_id})
    print(("HELD (back to draft, will not publish): " if status == "draft" else "RELEASED: ") + a.post_id)
    if res:
        print(json.dumps(res, indent=1, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    y = sub.add_parser("youtube")
    y.add_argument("episode")
    y.add_argument("--at", default="19:00", help='"HH:MM" US/Eastern today, "now", or an ISO time')
    y.add_argument("--privacy", default="public", choices=["public", "unlisted", "private"])
    y.add_argument("--out", default=os.path.join(ROOT, "out"))
    y.add_argument("--dry-run", action="store_true")
    y.add_argument("--allow-warnings", action="store_true", help="manual use only, never in the daily run")
    s = sub.add_parser("status")
    s.add_argument("--days", type=int, default=7)
    s.add_argument("--views", action="store_true")
    for name in ("hold", "release"):
        sub.add_parser(name).add_argument("post_id")
    a = ap.parse_args()
    try:
        if a.cmd == "check":
            return cmd_check(a) or 0
        if a.cmd == "youtube":
            return cmd_youtube(a)
        if a.cmd == "status":
            return cmd_status(a) or 0
        return cmd_status_change(a, "draft" if a.cmd == "hold" else "schedule") or 0
    except Problem as e:
        print(f"NOT CONNECTED: {e}" if "isn't set" in str(e) else f"ERROR: {e}", file=sys.stderr)
        return NOT_CONNECTED if "isn't set" in str(e) else 1


if __name__ == "__main__":
    sys.exit(main())
