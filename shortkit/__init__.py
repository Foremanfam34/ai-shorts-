"""Shared building blocks for the AI Shorts pipelines: voice, transcription, captions, audio."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.environ.get("SHORTKIT_MODELS", os.path.join(ROOT, "models"))
CACHE = os.path.join(ROOT, ".cache")
os.makedirs(CACHE, exist_ok=True)


def _font_dir():
    for d in (os.environ.get("SHORTKIT_FONTS"), os.path.join(ROOT, "fonts"), "/usr/share/fonts/opentype/inter"):
        if d and os.path.exists(os.path.join(d, "Inter-Black.otf")):
            return d
    raise SystemExit("Inter font not found - run ./setup.sh (it downloads Inter into ./fonts)")


FONT_DIR = _font_dir()  # Inter OTFs; also handed to libass for the captions
