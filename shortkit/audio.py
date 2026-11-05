"""Tiny procedural audio: a royalty-free music bed, transition whooshes, UI pops, and a mixer.
Everything is synthesized, so there are no copyright claims. Swap in licensed music any time."""
import numpy as np
import soundfile as sf

SR = 24000


def _midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def music_bed(duration, sr=SR, bpm=96, seed=7):
    """Moody minor-key loop (Am-F-C-G): soft pad, sub bass, kick, ticking hats."""
    n = int(duration * sr) + sr
    t = np.arange(n) / sr
    out = np.zeros(n, dtype=np.float64)
    beat = 60 / bpm
    bar = beat * 4
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]
    for ci in range(int(duration / bar) + 2):
        notes = chords[ci % 4]
        s, e = int(ci * bar * sr), min(n, int(((ci + 1) * bar + 0.6) * sr))
        if s >= n:
            break
        tt = t[s:e] - t[s]
        env = np.clip(tt / 0.9, 0, 1) * np.clip((bar + 0.6 - tt) / 0.6, 0, 1)
        for note in notes:
            f = _midi(note)
            for h, amp in ((1, 1.0), (2, 0.3), (3, 0.12)):
                out[s:e] += 0.05 * amp * np.sin(2 * np.pi * f * h * tt + h) * env
        out[s:e] += 0.10 * np.sin(2 * np.pi * _midi(notes[0] - 24) * tt) * env
    # kick on every beat, with the pad ducked underneath (pumping feel)
    kl = int(0.32 * sr)
    kt = np.arange(kl) / sr
    kick = np.sin(2 * np.pi * np.cumsum(45 + 95 * np.exp(-kt * 28)) / sr) * np.exp(-kt * 10)
    duck = np.ones(n)
    for b in np.arange(0, duration + bar, beat):
        s = int(b * sr)
        if s >= n:
            break
        m = min(kl, n - s)
        out[s:s + m] = out[s:s + m] * (0.55 + 0.45 * (1 - np.exp(-kt[:m] * 12))) + 0.28 * kick[:m]
    # hats on the off-beats
    rng = np.random.default_rng(seed)
    hl = int(0.035 * sr)
    for b in np.arange(beat / 2, duration + bar, beat):
        s = int(b * sr)
        if s + hl >= n:
            break
        noise = np.diff(rng.standard_normal(hl + 1)) * np.exp(-np.arange(hl) / sr * 110)
        out[s:s + hl] += 0.03 * noise
    out = out[: int(duration * sr)] * duck[: int(duration * sr)]
    fade = int(1.5 * sr)
    out[-fade:] *= np.linspace(1, 0, fade)
    return (out / (np.abs(out).max() + 1e-9) * 0.5).astype(np.float32)


def _env(n, attack, decay, sr=SR):
    t = np.arange(n) / sr
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t * decay)


def _lowpass(x, alpha):
    """One-pole low-pass, alpha in (0, 1] (smaller = darker)."""
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def music_groove(duration, sr=SR, bpm=116, seed=11):
    """Warm, upbeat loop: four-on-the-floor kick, claps on 2 and 4, swung hats, a sub bass
    pumping under the kick, and FM electric-piano chords (Am9 - Fmaj7 - C - G6)."""
    rng = np.random.default_rng(seed)
    n = int(duration * sr) + sr
    beat = 60 / bpm
    bar = beat * 4
    music = np.zeros(n)
    drums = np.zeros(n)
    chords = [(57, 60, 64, 67, 71), (53, 57, 60, 64), (48, 55, 60, 64, 74), (55, 59, 62, 64)]
    roots = [45, 41, 48, 43]

    def put(buf, sig, at):
        s = int(at * sr)
        if s >= n:
            return
        m = min(len(sig), n - s)
        buf[s:s + m] += sig[:m]

    # FM electric piano hits on 1, the "and" of 2, and 4
    def epiano(f, length=1.1, vel=1.0):
        t = np.arange(int(length * sr)) / sr
        index = 2.0 * np.exp(-t * 5)
        y = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * t)) + 0.25 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 7)
        return y * _env(len(t), 0.004, 2.6) * vel

    kick_t = np.arange(int(0.3 * sr)) / sr
    kick = np.sin(2 * np.pi * np.cumsum(48 + 110 * np.exp(-kick_t * 32)) / sr) * np.exp(-kick_t * 11)
    clap = np.zeros(int(0.25 * sr))
    for off in (0.0, 0.012, 0.024):  # three quick bursts = a clap
        s = int(off * sr)
        burst = rng.standard_normal(len(clap) - s) * _env(len(clap) - s, 0.001, 38 if off < 0.024 else 14)
        clap[s:] += burst
    clap = np.diff(np.concatenate([[0], _lowpass(clap, 0.5)]))  # band-limit
    hat = np.diff(rng.standard_normal(int(0.05 * sr) + 1)) * _env(int(0.05 * sr), 0.0005, 95)
    open_hat = np.diff(rng.standard_normal(int(0.22 * sr) + 1)) * _env(int(0.22 * sr), 0.001, 16)

    nbars = int(duration / bar) + 2
    for b in range(nbars):
        t0 = b * bar
        ci = b % 4
        for hit, vel in ((0.0, 1.0), (1.5, 0.75), (3.0, 0.85)):
            for note in chords[ci]:
                put(music, 0.055 * epiano(440 * 2 ** ((note - 69) / 12), vel=vel), t0 + hit * beat)
        for k in range(4):
            put(drums, 0.55 * kick, t0 + k * beat)
            if k in (1, 3):
                put(drums, 0.22 * clap, t0 + k * beat)
            for h in (0.0, 0.5):  # swung 8th-note hats, accented off-beats
                swing = 0.06 * beat if h else 0.0
                put(drums, (0.05 if h else 0.03) * hat, t0 + (k + h) * beat + swing)
        put(drums, 0.035 * open_hat, t0 + 3.5 * beat + 0.06 * beat)
        # sub bass: 8th notes on the root, warmed with soft saturation
        f = 440 * 2 ** ((roots[ci] - 69) / 12)
        for e in range(8):
            ln = int(beat / 2 * sr * 0.9)
            tt = np.arange(ln) / sr
            note = np.tanh(1.6 * np.sin(2 * np.pi * f * tt)) * _env(ln, 0.005, 6)
            put(music, 0.16 * note, t0 + e * beat / 2)

    # sidechain: music dips under every kick (the "pump" that makes it feel alive)
    pump = np.ones(n)
    for b in np.arange(0, duration + bar, beat):
        s = int(b * sr)
        ln = min(int(0.28 * sr), n - s)
        if ln <= 0:
            break
        pump[s:s + ln] = np.minimum(pump[s:s + ln], 0.45 + 0.55 * (np.arange(ln) / ln) ** 1.5)
    mix = music * pump + drums
    mix = mix[: int(duration * sr)]
    intro = int(min(2 * bar, duration / 3) * sr)  # filtered-in intro so the hook isn't a wall of sound
    mix[:intro] *= np.linspace(0.55, 1.0, intro)
    fade = int(1.2 * sr)
    mix[-fade:] *= np.linspace(1, 0, fade)
    return (mix / (np.abs(mix).max() + 1e-9) * 0.55).astype(np.float32)


def riser(sr=SR, dur=1.1, seed=5):
    """Filtered noise + rising tone that builds into a reveal (place it to END on the reveal)."""
    rng = np.random.default_rng(seed)
    n = int(dur * sr)
    t = np.arange(n) / sr
    noise = rng.standard_normal(n)
    y = np.zeros(n)
    acc, cut = 0.0, np.linspace(0.01, 0.5, n) ** 1.5
    for i in range(n):
        acc += cut[i] * (noise[i] - acc)
        y[i] = acc
    tone = np.sin(2 * np.pi * np.cumsum(220 + 900 * (t / dur) ** 2) / sr) * 0.25
    out = (y + tone) * (t / dur) ** 2.2
    return (out / (np.abs(out).max() + 1e-9) * 0.6).astype(np.float32)


def impact(sr=SR, dur=0.9, seed=9):
    """A deep hit for the moment the number lands."""
    rng = np.random.default_rng(seed)
    n = int(dur * sr)
    t = np.arange(n) / sr
    boom = np.sin(2 * np.pi * np.cumsum(30 + 90 * np.exp(-t * 14)) / sr) * np.exp(-t * 4.5)
    crack = _lowpass(rng.standard_normal(n), 0.35) * np.exp(-t * 18) * 0.6
    out = np.tanh(1.4 * (boom + crack))
    return (out / (np.abs(out).max() + 1e-9) * 0.9).astype(np.float32)


def voice_fx(samples, sr=SR):
    """Broadcast warmth: gentle high-pass, low-mid warmth, tamed harshness and sibilance, light
    compression, and a hint of room so the voice doesn't sound like it's in a vacuum."""
    import os
    import subprocess
    import tempfile
    chain = ("highpass=f=75,equalizer=f=210:t=q:w=1.0:g=2.5,equalizer=f=3600:t=q:w=1.4:g=-2,"
             "deesser=i=0.35,acompressor=threshold=0.1:ratio=2.5:attack=6:release=130:makeup=1.6,"
             "aecho=0.92:0.6:21|37:0.06|0.04")
    with tempfile.TemporaryDirectory() as d:
        src, dst = os.path.join(d, "in.wav"), os.path.join(d, "out.wav")
        sf.write(src, samples.astype(np.float32), sr)
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-af", chain, "-ar", str(sr),
                        "-ac", "1", "-c:a", "pcm_f32le", dst], check=True)
        out, _ = sf.read(dst, dtype="float32")
    out = out[: len(samples)]
    if len(out) < len(samples):
        out = np.pad(out, (0, len(samples) - len(out)))
    rms_in = np.sqrt(np.mean(samples ** 2)) + 1e-9
    rms_out = np.sqrt(np.mean(out ** 2)) + 1e-9
    return (out * (rms_in / rms_out)).astype(np.float32)


def whoosh(sr=SR, dur=0.45, seed=1):
    rng = np.random.default_rng(seed)
    n = int(dur * sr)
    x = rng.standard_normal(n)
    env = np.concatenate([np.linspace(0, 1, int(n * 0.6)) ** 2, np.linspace(1, 0, n - int(n * 0.6)) ** 1.5])
    y = np.zeros(n)
    acc = 0.0
    cut = np.linspace(0.02, 0.35, n)  # one-pole low-pass sweeping open
    for i in range(n):
        acc += cut[i] * (x[i] - acc)
        y[i] = acc
    y *= env
    return (y / (np.abs(y).max() + 1e-9) * 0.6).astype(np.float32)


def pop(sr=SR, dur=0.07):
    t = np.arange(int(dur * sr)) / sr
    f = 1400 - 600 * t / dur
    y = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t * 55)
    return (y * 0.5).astype(np.float32)


def place(track, clip, at, gain=1.0, sr=SR):
    s = int(at * sr)
    if s >= len(track) or s < 0:
        return
    m = min(len(clip), len(track) - s)
    track[s:s + m] += clip[:m] * gain


def duck_under(bed, voice, sr=SR, amount=0.45):
    """Lower the bed while someone is speaking."""
    win = int(0.15 * sr)
    env = np.convolve(np.abs(voice), np.ones(win) / win, mode="same")
    active = (env > 0.01).astype(np.float64)
    smooth = np.convolve(active, np.ones(int(0.25 * sr)) / int(0.25 * sr), mode="same")
    return bed * (1 - amount * smooth).astype(np.float32)


def write(path, samples, sr=SR):
    sf.write(path, np.clip(samples, -1, 1).astype(np.float32), sr)


def loudnorm(src, dst, target=-14.0, true_peak=-1.5, lra=11.0):
    """Two-pass EBU R128 normalization (platforms play back at about -14 LUFS)."""
    import json
    import subprocess
    f = f"loudnorm=I={target}:TP={true_peak}:LRA={lra}"
    r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-i", src, "-af", f + ":print_format=json",
                        "-f", "null", "-"], capture_output=True, text=True, check=True)
    m = json.loads(r.stderr[r.stderr.rindex("{"): r.stderr.rindex("}") + 1])
    f2 = (f"{f}:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:"
          f"measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-af", f2, "-ar", "48000", dst],
                   check=True)
    return dst
