"""Word-by-word 'viral style' captions as an ASS subtitle file (burned in by ffmpeg/libass)."""
import difflib
import re

_NUMERIC = re.compile(r"[\d$%]")
_NUMBER_WORDS = set("""zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen
fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty ninety hundred
thousand million billion trillion point percent dollar dollars first second third fourth fifth sixth seventh
eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth
nineteenth twentieth thirtieth fortieth fiftieth sixtieth seventieth eightieth ninetieth hundredth""".split())


def _norm(s):
    return re.sub(r"[^a-z0-9']", "", s.lower())


def fix_phrases(words, fixes):
    """Rewrite caption phrases, e.g. [["S and P500", "S&P 500"]], keeping their timing."""
    for old, new in fixes or []:
        o, nw = [_norm(x) for x in old.split()], new.split()
        i = 0
        while i <= len(words) - len(o):
            if [_norm(w["w"]) for w in words[i:i + len(o)]] == o:
                t0, t1 = words[i]["start"], words[i + len(o) - 1]["end"]
                step = (t1 - t0) / len(nw)
                trail = re.sub(r"^.*?([.,!?;:]*)$", r"\1", words[i + len(o) - 1]["w"])
                rep = [{"w": x, "start": round(t0 + k * step, 3), "end": round(t0 + (k + 1) * step, 3)}
                       for k, x in enumerate(nw)]
                rep[-1]["w"] += trail
                words[i:i + len(o)] = rep
                i += len(nw)
            else:
                i += 1
    return words


def align_to_script(words, script):
    """Fix mis-heard words (names, tickers) using the script, but keep the recognizer's number
    formatting ("$1.6 million", "19%") which reads better on screen than spelled-out numbers."""
    sw = script.split()
    a, b = [_norm(w["w"]) for w in words], [_norm(x) for x in sw]
    out = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == "equal":
            out += [dict(words[i1 + k], w=sw[j1 + k]) for k in range(i2 - i1)]
        elif op == "replace":
            heard = words[i1:i2]
            # keep the recognizer's digits only where the script really says a number
            # ("fourteen percent" -> "14%"), not for homophones ("beat too" -> "beat 2")
            if any(_NUMERIC.search(w["w"]) for w in heard) and any(x in _NUMBER_WORDS for x in b[j1:j2]):
                out += heard
            else:  # spread the script's words over the time span of what was heard
                t0, t1 = heard[0]["start"], heard[-1]["end"]
                lens = [len(x) + 1 for x in sw[j1:j2]]
                t = t0
                for x, n in zip(sw[j1:j2], lens):
                    d = (t1 - t0) * n / sum(lens)
                    out.append({"w": x, "start": round(t, 3), "end": round(t + d, 3)})
                    t += d
        elif op == "delete":
            out += words[i1:i2]
    return out


def chunk(words, max_words=3, max_chars=15, max_gap=0.35):
    chunks, cur = [], []
    for w in words:
        if cur:
            text_len = sum(len(x["w"]) + 1 for x in cur) + len(w["w"])
            ends_sentence = cur[-1]["w"][-1:] in ".?!,;:"
            if (len(cur) >= max_words or text_len > max_chars or ends_sentence
                    or w["start"] - cur[-1]["end"] > max_gap):
                chunks.append(cur)
                cur = []
        cur.append(w)
    if cur:
        chunks.append(cur)
    return chunks


def _ass_time(t):
    t = max(0.0, t)
    h, m, s = int(t // 3600), int(t % 3600 // 60), t % 60
    return f"{h}:{m:02d}:{s:05.2f}"


def _esc(s):
    return s.replace("\\", "").replace("{", "(").replace("}", ")")


escape = _esc


def _bgr(hex_rgb):
    r, g, b = hex_rgb[1:3], hex_rgb[3:5], hex_rgb[5:7]
    return f"&H00{b}{g}{r}".upper()


def write_ass(words, path, width=1080, height=1920, y=1450, font="Inter Black", size=84,
              color="#FFFFFF", highlight="#FFD60A", outline=7, uppercase=True,
              max_words=3, max_chars=15, extra_events=(), styles=()):
    """`extra_events`: raw (start, end, style, text) tuples, e.g. a title bar for clips."""
    hl = _bgr(highlight)
    base = _bgr(color)
    lines = [
        "[Script Info]", "ScriptType: v4.00+", f"PlayResX: {width}", f"PlayResY: {height}",
        "WrapStyle: 0", "ScaledBorderAndShadow: yes", "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
        "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, "
        "Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: Cap,{font},{size},{base},{base},&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,"
        f"{outline},3,5,120,120,0,1",
        *styles, "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    chunks = chunk(words, max_words, max_chars)
    for ci, ch in enumerate(chunks):
        nxt = chunks[ci + 1][0]["start"] if ci + 1 < len(chunks) else None
        chunk_end = ch[-1]["end"] + 0.12
        if nxt is not None and nxt - ch[-1]["end"] < 0.6:
            chunk_end = nxt
        # trailing commas/periods look like noise in big captions; keep ? and ! (they carry tone)
        texts = [_esc(re.sub(r"[.,;:]+$", "", w["w"]) or w["w"]) for w in ch]
        texts = [t.upper() if uppercase else t for t in texts]
        for i, w in enumerate(ch):
            start = ch[0]["start"] if i == 0 else w["start"]
            end = ch[i + 1]["start"] if i + 1 < len(ch) else chunk_end
            if end <= start:
                continue
            # the spoken word lights up and pops slightly larger, then settles
            parts = [f"{{\\c{hl}&\\fscx112\\fscy112\\t(0,120,\\fscx106\\fscy106)}}{t}{{\\c{base}&\\fscx100\\fscy100}}"
                     if k == i else t for k, t in enumerate(texts)]
            pop = "{\\fscx82\\fscy82\\t(0,90,\\fscx100\\fscy100)}" if i == 0 else ""
            lines.append(f"Dialogue: 1,{_ass_time(start)},{_ass_time(end)},Cap,,0,0,0,,"
                         f"{{\\an5\\pos({width // 2},{y})}}{pop}{' '.join(parts)}")
    for start, end, style, text in extra_events:
        lines.append(f"Dialogue: 2,{_ass_time(start)},{_ass_time(end)},{style},,0,0,0,,{text}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path
