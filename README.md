# AI Shorts

Two automated short-form video pipelines. Everything except clip picking runs locally for free.

| Folder | What it makes |
|---|---|
| `congress/` | **Congress Trades**: Shorts built from real STOCK Act disclosures, with voiceover, animated charts, word-by-word captions, music and SFX. There are two formats: a weekly roundup (about 50 s) and a daily Spotlight on one disclosure (about 30 s). |
| `movers/` | **Daily Movers**: the day's biggest stock moves (regular session plus after-hours earnings reactions), found with Robinhood's scanner and rendered by the same engine: `python3 congress/render.py movers/episodes/<date>.json` |
| `clipper/` | **Clipper**: turns a long video (podcast, interview, stream) into vertical clips with a hook title, captions and a progress bar |
| `dashboard/` | **AI Shorts Studio**: the source of the hosted dashboard where you watch each video, copy its post text, and track status, views and revenue |
| `shortkit/` | Shared parts: local AI voice (Kokoro), transcription with word timings (Parakeet), caption builder, audio mixing |

Sample outputs are in `out/`:
- `congress-trades-2026-11-03.mp4` (weekly)
- `congress-trades-2026-11-04-pelosi-intel.mp4` (Spotlight)
- `clips/side-quest-ep12/` (clipper)

Dashboard: https://claude.ai/artifact/PkXcf4fxhp49R6wgKxe8mH (private to you).

## Setup

Needs Python 3.10+ and about 1.5 GB of disk space for models.

```bash
./setup.sh
```

---

## 1. Congress Trades

```bash
python3 congress/render.py congress/episodes/2026-11-03.json
```

Each run takes about 1 minute on a laptop CPU and writes three files to `out/`:
- the MP4 (1080×1920, 30 fps, −14 LUFS)
- a cover PNG
- `post.txt` (title, description, hashtags)

**Episode file:** one JSON per video. Each scene has a `type` (hook, trades, bars, chart, list, outro), a `say` line for the voiceover, and its on-screen data.
- `cue` words sync animations to the narration, for example a row lights up when its company is spoken.
- `say_as` fixes pronunciations, e.g. `"Rulli": "Roo lee"`.
- Spell numbers out in `say`. Captions show them as digits automatically ("$1.6 million", "19%").
- Every field is documented in `congress/EPISODES.md`, along with the two formats.

**Weekly automation:** a scheduled Claude task does the whole loop:
1. Pull the week's disclosures for a watchlist of tickers and politicians, plus prices, through the Robinhood connector.
2. Find the most interesting story and write the episode JSON.
3. Render the video.
4. Send you the video and post text for approval.

Keep the approval step. A wrong number in finance content costs you the channel.

**Built-in rules (keep them):**
- The source is on screen.
- Amounts are shown as the disclosed ranges, never exact figures.
- The video notes that disclosures can lag trades by up to 45 days.
- The video says it's "not financial advice / not evidence of wrongdoing".

Before you monetize, check whether Tip Ranks' terms allow use in commercial videos, or switch to the primary filings (House Clerk and Senate eFD), which are public records.

**How it makes money:** Shorts ad revenue is small. Use the channel to grow a weekly "Congress trades" newsletter, then earn from sponsors and affiliate links, with proper disclosures. Post 3–5 times a week: the weekly roundup plus single-trade spotlights.

---

## 2. Clipper

```bash
python3 clipper/clip.py all  my-podcast.mp4 --n 5                  # transcribe, pick, render
python3 clipper/clip.py render my-podcast.mp4 --moments picks.json   # use your own picks
python3 clipper/clip.py render my-podcast.mp4 --layout crop          # single centered speaker
```

The pipeline runs in three stages:
1. **Transcribe:** local, with word timestamps.
2. **Pick:** Claude acts as a short-form editor and returns JSON with start/end times, a hook title, a caption, hashtags and a score.
3. **Render:** cut each clip on word boundaries, lay it out 9:16, burn in the title and captions, normalize loudness, and write a cover image and post text.

`clips.json` indexes the results for an uploader.

**Picking with Claude** needs `ANTHROPIC_API_KEY` (or `ant auth login`). It uses Claude Opus 5.5 and costs roughly $0.10–0.50 per hour of source video. Without a key, write the picks file yourself; `clipper/demo/side-quest-moments.json` shows the format.

**Test video:** `python3 clipper/demo/make_sample_podcast.py` builds an original two-host episode to practice on.

**How it makes money:**
- **Clipping campaigns:** creators pay per 1,000 views on clips of their content. Follow each campaign's rules.
- **A clip service** for podcasters, coaches and agencies, e.g. a monthly package of 20–30 clips. Each clip costs you minutes, not hours.

**Only clip videos you own, have permission for, or are in a campaign for.**

---

## Voice and energy

The narrator is Kokoro's `am_michael`, a firm male voice that runs locally for free. Firm episodes use `"speed": 1.1` and `"pause_scale": 0.8` for a brisker read. To compare male voices, run `python3 tools/voice_audition.py --male`; `af_heart` is the warm female option. Three things make it sound human:

- **Delivery** (`say_natural`): it reads phrase by phrase, with breath-length pauses and tiny tempo changes, slightly slower on numbers. A `...` in a script line adds a dramatic beat before a reveal.
- **Warmth** (`voice_fx`): a broadcast chain with a little low-mid warmth, softer harsh and "s" sounds, gentle compression and a hint of room.
- **Energy:** a calm voice paired with an energetic edit. It comes from an upbeat groove at 116 BPM, risers and impacts with the music cutting out for a beat before each big reveal, zoom punches and flashes, and caption words that pop as they're spoken.

To compare narrators, run `python3 tools/voice_audition.py`. To pick one, set `"voice"` in the episode file.

**Better voices (paid):**
- **ElevenLabs:** the most natural option. It has a big library of calm female narrators, and its v3 model takes emotion tags. Its Voice Changer turns your own recorded read into any voice while keeping your human timing.
- **Hume Octave:** you describe the voice and the acting in plain words.
- **OpenAI's `gpt-4o-mini-tts`:** the cheapest, steered with instructions like "warm and calm".

Each of these needs its API host allowed in this environment's network settings, or the pipeline run on your own computer.

## Posting

Upload by hand for the first 2–3 weeks (YouTube Studio, TikTok, Instagram) to learn which hooks work. Then automate the upload step, for example with Postiz, which schedules posts to all three platforms.

## Known limits

- **Voice:** Kokoro is good, but paid voice APIs (e.g. ElevenLabs) are better. Swapping one in means changing `shortkit/tts.py`.
- **Captions:** rare words can be mis-transcribed, so skim captions before posting.
- **Music:** the bed is synthesized, so it's royalty-free. Swap in tracks from the YouTube Audio Library if you like.
- **Crop:** the crop layout is centered, not face-tracking.
