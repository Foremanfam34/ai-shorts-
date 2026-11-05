"""Local speech-to-text with word timestamps: NVIDIA Parakeet TDT 0.6B (via sherpa-onnx) + Silero VAD."""
import os
import subprocess

import numpy as np
import sherpa_onnx

from . import MODELS

PARAKEET = os.path.join(MODELS, "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8")
VAD_MODEL = os.path.join(MODELS, "silero_vad.onnx")
SR = 16000


def load_audio(path, sr=SR):
    """Decode any audio/video file to mono float32 at `sr` using ffmpeg."""
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vn", "-ac", "1",
                          "-ar", str(sr), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def _tokens_to_words(tokens, starts, durations, offset):
    words, cur = [], None
    for tok, st, du in zip(tokens, starts, durations):
        if tok.startswith(" ") or cur is None:
            if cur and cur["w"]:
                words.append(cur)
            cur = {"w": tok.strip(), "start": offset + st, "end": offset + st + du}
        else:
            if not cur["w"]:
                cur["start"] = offset + st
            cur["w"] += tok
            cur["end"] = offset + st + du
    if cur and cur["w"]:
        words.append(cur)
    for w in words:
        w["start"], w["end"] = round(w["start"], 3), round(max(w["end"], w["start"] + 0.08), 3)
    return words


class Transcriber:
    def __init__(self, threads=4):
        self.rec = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=os.path.join(PARAKEET, "encoder.int8.onnx"),
            decoder=os.path.join(PARAKEET, "decoder.int8.onnx"),
            joiner=os.path.join(PARAKEET, "joiner.int8.onnx"),
            tokens=os.path.join(PARAKEET, "tokens.txt"),
            model_type="nemo_transducer", num_threads=threads)

    def words(self, samples, sr=SR, offset=0.0):
        """Transcribe a short clip (< ~30 s). Returns [{w, start, end}]."""
        s = self.rec.create_stream()
        s.accept_waveform(sr, samples)
        self.rec.decode_stream(s)
        r = s.result
        return _tokens_to_words(r.tokens, r.timestamps, r.durations, offset)

    def transcribe(self, samples, sr=SR, progress=None):
        """Transcribe long audio by splitting on silence first. Returns (words, segments)."""
        cfg = sherpa_onnx.VadModelConfig()
        cfg.silero_vad.model = VAD_MODEL
        cfg.silero_vad.threshold = 0.5
        cfg.silero_vad.min_silence_duration = 0.35
        cfg.silero_vad.min_speech_duration = 0.25
        cfg.silero_vad.max_speech_duration = 25
        cfg.sample_rate = sr
        vad = sherpa_onnx.VoiceActivityDetector(cfg, buffer_size_in_seconds=120)
        win = cfg.silero_vad.window_size
        segs = []

        def drain():
            while not vad.empty():
                segs.append((vad.front.start / sr, np.array(vad.front.samples, dtype=np.float32)))
                vad.pop()

        for i in range(0, len(samples), win):
            vad.accept_waveform(samples[i:i + win])
            drain()
        vad.flush()
        drain()

        words, segments = [], []
        for n, (start, seg) in enumerate(segs):
            pad = np.zeros(int(0.1 * sr), dtype=np.float32)  # small pad helps the first/last word
            ws = self.words(np.concatenate([pad, seg, pad]), sr, offset=start - 0.1)
            if ws:
                words.extend(ws)
                segments.append({"start": ws[0]["start"], "end": ws[-1]["end"],
                                 "text": " ".join(w["w"] for w in ws)})
            if progress:
                progress(n + 1, len(segs))
        return words, segments
