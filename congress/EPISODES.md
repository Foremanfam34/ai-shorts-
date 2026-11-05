# Episode files

One JSON file per video in `congress/episodes/`. Render with:

```bash
python3 congress/render.py congress/episodes/<file>.json
```

The renderer writes three files to `out/`: the MP4, a cover PNG and `post.txt`.

## Formats

| Format | Length | Scenes | Cadence |
|---|---|---|---|
| `weekly` | 45–55 s | hook → trades → bars → chart → list → outro | Mondays |
| `spotlight` | 25–30 s | hook → trades → chart → outro | Weekdays, one disclosure |

## Top-level fields

| Field | Meaning |
|---|---|
| `id` | Used in output file names, e.g. `2026-11-04-pelosi-intel` |
| `format` | `weekly` or `spotlight` (informational) |
| `series`, `badge` | Header pill text; `badge` adds a yellow pill, e.g. `SPOTLIGHT` |
| `week_label`, `source_line` | Header text, top right, and the source line under the header |
| `voice`, `speed` | Kokoro voice (`af_heart` is the warm female narrator) and speed (around 1.06) |
| `natural` | `true` (default): phrase-by-phrase delivery with human pauses. `false`: one flat read |
| `voice_fx` | `true` (default): warmth, de-essing, compression and room on the voice |
| `music` | `groove` (default): upbeat track with risers, impacts and zoom punches on reveals. `ambient`: the original slow bed |
| `say_as` | Pronunciation fixes as respellings: `{"Rulli": "Roo lee"}` |
| `post` | `title`, `description`, `hashtags` for `post.txt` |

## Scenes

Every scene has a `type` and a `say` line.

**Writing `say` lines:**
- Spell numbers out: "thirteen million dollars", not "$13M". Captions turn spoken numbers back into digits automatically.
- A `cue` is a word from that scene's `say` line. The matching animation fires when the narrator says it.
- Write the way a person talks. Open with a reaction ("Okay, this one's wild."), ask the viewer questions ("So how did those stocks do after?"), and use short fragments for punch ("In one day.").
- Put `...` before a reveal for a dramatic beat.
- End with a question for the comments.

**Scene types and their fields:**

| Type | Fields |
|---|---|
| `hook` | `line1`, `big` (`{lo, hi}` in $K, shown as a range) or `big_text`, `big_color`, `line2`, `pill`, `pill_color`, `pill_cue` |
| `trades` | `who`, `sub`, and `rows` of `{ticker, name, side: BUY\|SELL, range, cue?}`. With cues, each row lights up when it's named. |
| `bars` | `title`, `sub`, and `rows` of `{ticker, from, to, cue?}`. The % change is computed from `from` and `to`. |
| `chart` | `who`, `sub`, `series` (`[[date, close], ...]`), `markers` (`[{date, label, cue?, color?, below?}]`), `drop` (`{date, label, cue}`, the one-day move shown in red), `stat` (`{value, label, cue}`) |
| `list` | `title`, and `rows` of `{who, ticker, side, range, dates, cue}`. Rows appear as they're named. |
| `outro` | `notes` (3 lines), `cta`, `cta_cue`, `credits` |

## Rules every episode follows

- Amounts are always the disclosed ranges, never exact figures.
- Every episode notes the disclosure lag and says it's "not financial advice / not evidence of wrongdoing".
- Prices come from official closes. For the latest session, use `get_equity_quotes` rather than the last historical bar.
- Check every trade against the primary filing before posting. The Robinhood ticker filter can return fewer rows than the unfiltered politician query.

## Adding a video to the dashboard

1. Upload the MP4 and the cover to the dashboard artifact as assets.
2. Add a row to the `videos` collection with:
   - `title`, `show`, `series`, `created`, `order`, `duration`
   - `video` and `cover` (the asset ids)
   - `post_title`, `post_text`, `hashtags`
   - `status: "review"` and `checks` (a list of `{text, done}`)
   - `platforms`: `youtube`, `tiktok` and `instagram`, each `{posted, url, views}`
