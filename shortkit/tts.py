"""Local text-to-speech: Kokoro v1.0 (via sherpa-onnx) with an espeak-ng fallback for unknown words.

Kokoro's lexicon silently drops words it doesn't know (names, tickers, new words), so before
building the engine we phonemize every out-of-lexicon word with espeak-ng and add it to an
extra lexicon. `say_as` lets you fix pronunciations with a respelling, e.g. {"Rulli": "Roo lee"}.
"""
import functools
import hashlib
import os
import re
import subprocess

import numpy as np
import sherpa_onnx

from . import CACHE, MODELS

KOKORO = os.path.join(MODELS, "kokoro-multi-lang-v1_0")
SAMPLE_RATE = 24000

# Speaker ids in kokoro-multi-lang-v1_0
VOICES = {
    "af_bella": 2, "af_heart": 3, "af_nicole": 6, "af_nova": 7, "af_sarah": 9,
    "am_adam": 11, "am_echo": 12, "am_eric": 13, "am_fenrir": 14, "am_liam": 15,
    "am_michael": 16, "am_onyx": 17, "am_puck": 18,
    "bf_emma": 21, "bm_george": 26, "bm_lewis": 27,
}

# espeak-ng IPA -> Kokoro (misaki) phoneme symbols. Longest patterns first.
_E2K = [("ɜːɹ", "ɜɹ"), ("eɪ", "A"), ("aɪ", "I"), ("oʊ", "O"), ("ɔɪ", "Y"), ("aʊ", "W"),
        ("dʒ", "ʤ"), ("tʃ", "ʧ"), ("ɜː", "ɜɹ"), ("ɚ", "əɹ"), ("ɝ", "ɜɹ"), ("ɐ", "ə"),
        ("ː", ""), ("r", "ɹ"), ("ɬ", "l"), ("x", "k"), ("ç", "k")]
_WORD = re.compile(r"[A-Za-z][A-Za-z']*")


@functools.lru_cache(maxsize=1)
def _lexicon_words():
    with open(os.path.join(KOKORO, "lexicon-us-en.txt"), encoding="utf-8") as f:
        return {line.split(" ", 1)[0] for line in f}


@functools.lru_cache(maxsize=1)
def _token_set():
    toks = set()
    with open(os.path.join(KOKORO, "tokens.txt"), encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line:
                toks.add(line.rsplit(" ", 1)[0])
    return toks


def espeak_phonemes(text):
    ipa = subprocess.run(["espeak-ng", "-q", "--ipa", "-v", "en-us", text],
                         capture_output=True, text=True, check=True).stdout
    ipa = ipa.strip().replace("\n", " ")
    for a, b in _E2K:
        ipa = ipa.replace(a, b)
    toks = _token_set()
    return [c for c in ipa if c in toks and not c.isspace()]


def clean(text):
    """Normalize text the way the engine will see it (hyphens split words)."""
    return re.sub(r"(?<=\w)-(?=\w)", " ", text)


class Voice:
    """Build once with every line you plan to speak, so unknown words get pronunciations."""

    def __init__(self, texts, say_as=None, threads=4):
        for t in texts:
            if re.search(r"\d", t):
                raise ValueError(f"Spell out numbers in spoken text (TTS can't read digits): {t!r}")
        lex = _lexicon_words()
        say_as = {k.lower(): v for k, v in (say_as or {}).items()}
        extra = {}
        for t in texts:
            for w in _WORD.findall(clean(t)):
                lw = w.lower()
                if lw in extra:
                    continue
                if lw in say_as:
                    extra[lw] = espeak_phonemes(say_as[lw])
                elif lw not in lex:
                    extra[lw] = espeak_phonemes(w)
        self.oov = sorted(extra)
        lexicons = [os.path.join(KOKORO, "lexicon-us-en.txt")]
        if extra:
            key = hashlib.md5(repr(sorted(extra.items())).encode()).hexdigest()[:12]
            path = os.path.join(CACHE, f"extra-lexicon-{key}.txt")
            with open(path, "w", encoding="utf-8") as f:
                for w, ph in extra.items():
                    if ph:
                        f.write(f"{w} {' '.join(ph)}\n")
            lexicons.insert(0, path)
        cfg = sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                    model=os.path.join(KOKORO, "model.onnx"),
                    voices=os.path.join(KOKORO, "voices.bin"),
                    tokens=os.path.join(KOKORO, "tokens.txt"),
                    data_dir=os.path.join(KOKORO, "espeak-ng-data"),
                    dict_dir=os.path.join(KOKORO, "dict"),
                    lexicon=",".join(lexicons),
                    lang="en-us"),
                num_threads=threads),
            max_num_sentences=1)
        self.engine = sherpa_onnx.OfflineTts(cfg)

    def say(self, text, voice="am_michael", speed=1.0):
        """Return float32 mono samples at SAMPLE_RATE."""
        a = self.engine.generate(clean(text), sid=VOICES[voice], speed=speed)
        samples = np.array(a.samples, dtype=np.float32)
        if samples.size == 0:
            raise RuntimeError(f"TTS produced no audio for: {text!r}")
        return samples

    def say_natural(self, text, voice="af_heart", speed=1.0, seed=0, pause_scale=1.0):
        """Read a line the way a person would: phrase by phrase, with breath-length pauses,
        a beat before reveals ("..."), a touch slower on numbers, and tiny tempo changes so
        consecutive sentences don't share the exact same rhythm."""
        rng = np.random.default_rng(seed)
        out = []
        chunks = phrases(text)
        for i, (phrase, pause) in enumerate(chunks):
            sp = speed * (1 + rng.uniform(-0.03, 0.03))
            if _FACTY.search(phrase):
                sp *= 0.94
            out.append(trim(self.say(phrase, voice, sp)))
            if i < len(chunks) - 1:
                p = pause * pause_scale * (1 + rng.uniform(-0.15, 0.15))
                out.append(np.zeros(int(p * SAMPLE_RATE), dtype=np.float32))
        return np.concatenate(out)


_FACTY = re.compile(r"\b(million|billion|thousand|hundred|percent|dollars?)\b", re.I)
_PHRASE = re.compile(r"(.+?)(\.\.\.|…|[.!?]+(?=\s|$)|$)\s*", re.S)
_PAUSES = {"...": 0.62, "?": 0.42, "!": 0.36, ".": 0.32}


def phrases(text):
    """Split a line into (phrase, pause after it in seconds). "..." marks a dramatic beat."""
    out = []
    for m in _PHRASE.finditer(text.strip()):
        body, end = m.group(1).strip(), m.group(2)
        if not body:
            continue
        if end in ("...", "…"):
            out.append((body.rstrip(",") + ",", _PAUSES["..."]))  # keeps a continuing intonation
        else:
            out.append((body + end, _PAUSES.get(end[:1], 0.3)))
    return out


def trim(a, thresh=0.006, pad=0.035):
    """Cut the engine's leading/trailing silence so we control every pause ourselves."""
    idx = np.flatnonzero(np.abs(a) > thresh)
    if not idx.size:
        return a
    p = int(pad * SAMPLE_RATE)
    return a[max(0, idx[0] - p): min(len(a), idx[-1] + p)]
