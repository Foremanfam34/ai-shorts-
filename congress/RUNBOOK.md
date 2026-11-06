# Congress Trades runbook

Every weekday morning, make one Stock Geek Congress Short and leave it in the dashboard for the owner to post. **Never post anything.**
- **Monday:** the weekly roundup of the last seven days' disclosures. Copy `congress/episodes/2026-11-03.json`.
- **Tuesday to Friday:** a Spotlight on one disclosure. Copy `congress/episodes/2026-11-04-pelosi-intel.json`.

## 0. Setup
- Work in `/home/user/ai-shorts-` (the `Foremanfam34/ai-shorts-` repo) and run `git pull`.
- If `models/` is missing, run `./setup.sh`.
- Read `congress/USED.md`, the trades already featured. **Never feature one of them again.**
- Read **Leads** at the bottom of this file. Use the oldest lead first, then delete it.

## 1. Find candidates (Robinhood `get_politician_trades`)
**Search by name.** The name lookup lists a politician's trades completely. The ticker lookup returns only one page of all politicians' trades, so use it to discover names, not as the record.

Names that trade often:
- Nancy Pelosi
- Michael T. McCaul
- Ro Khanna
- Josh Gottheimer
- Cleo Fields
- Robert Bresnahan
- Pete Sessions
- Michael A. Rulli
- Sheldon Whitehouse
- Tommy Tuberville
- Rick Scott
- Lisa C. McClain
- John McGuire
- Julie Johnson
- Jared Moskowitz

Use full names: a partial name like "Moore" or "Sen." matches many people and the lookup refuses it.

Also check who traded these, then look those people up by name: NVDA, AAPL, MSFT, AMZN, GOOGL, META, TSLA, AVGO, PLTR, AMD.

**Keep** only `EQUITY` or `OPTION` trades that have a ticker. Skip `UNSPECIFIED` rows and blank symbols.

**What makes a good Spotlight**, in order:
1. A well-known name or a well-known stock.
2. A big disclosed range: $250K or more at the top, or several trades in the same stock.
3. A big price move since the trade, 10% or more either way. The story is "what happened next".
4. Disclosed recently. A trade disclosed in the last 14 days beats an older one.

## 2. Verify
- Take each trade exactly as the name lookup lists it: date, buy or sell, shares or options, range. If anything disagrees between lookups, leave that trade out.
- **Trade-day price:** the close on the transaction date, from `get_equity_historicals` (day bars). Skip interpolated bars.
- **Latest price:** `close.price` from `get_equity_quotes`. Its `close.date` must be the last session. Recompute every % yourself.
- **Reasons:** only from `get_earnings_results` (report date, EPS vs estimate). Otherwise give no reason.

## 3. Rules for every Congress video (keep them)
- **Amounts** are the disclosed ranges ("$1M–$5M"). For a total, say "up to" the sum of the tops, and give the full range in the description.
- **Dates:** show both the trade date and the disclosure date. Say that filings can lag up to 45 days.
- **Ownership:** say "her/his filings show". Many trades are a spouse's. Never say the politician still holds the stock; you can't know that.
- **No implication of wrongdoing.** Never use "insider", "suspicious", "perfect timing", "knew", or "right before the news/earnings". Describe what the stock did afterward, neutrally.
- **Outro:** "not evidence of wrongdoing" and "not financial advice".
- **Source on screen:** "Source: STOCK Act disclosures via Tip Ranks".

## 4. Write the episode
- Name the file `congress/episodes/YYYY-MM-DD-<lastname>-<ticker>.json`, with a matching `id`.
- Keep the voice settings (`am_michael`, speed 1.1, pause_scale 0.8), `music: groove`, and the outro's Subscribe call to action.
- In `say` lines, spell numbers out. Say dates as words ("July twenty third").
- **Post text** (`post`):
  - `title`: 60 characters or less, a fact that makes people curious, e.g. "Pelosi's Intel buys vs. Intel's 29% one-day crash".
  - `description`, in this order:
    1. One sentence with the headline fact.
    2. Each trade on its own line: `Jul 23 · Shares · BUY · $1M–$5M`.
    3. "Disclosed <date>."
    4. What the stock did since, using closing prices with dates.
    5. The comment question, then "Subscribe for a new Congress trade every weekday."
    6. "Source: STOCK Act filings via Tip Ranks; prices via Robinhood. Amounts are disclosed ranges. Narrated with an AI voice. Not financial advice and not an allegation of wrongdoing."
  - `hashtags`: #congresstrades #stocks #stockmarket, then the politician's last name and the company, e.g. #pelosi #intel.
- Re-check every number in the file against your verified data with a quick Python script.

## 5. Render and check
- Run `python3 congress/render.py congress/episodes/<file>.json`.
- Read the "heard:" lines. Fix names with `say_as` and captions with `caption_fix`.
- Fix any QA warning in `out/<slug>-qa.json` by picking a non-number cue word, then re-render.
- Pull four frames with ffmpeg (hook, trades, chart, outro) and look at them. Check that nothing overlaps, every number matches, and names are spelled right.

## 6. Dashboard
The dashboard is https://claude.ai/artifact/PkXcf4fxhp49R6wgKxe8mH.
- Upload the MP4 and cover as assets.
- Add a `videos/ct-<episode id>` row:
  - `show: "Congress Trades"`, `series` (`spotlight` or `weekly`), `status: "review"`, `created`, `duration`, `video`, `cover`
  - `post_title`, `post_text`, `hashtags`
  - `checks`: watch for name and caption errors; turn on the platform's AI label
  - `platforms`: `youtube`, `tiktok` and `instagram`, each `{posted: false, url: "", views: 0}`
- Update `automations/daily-spotlight` (Tuesday to Friday) or `automations/weekly-congress` (Monday) with `last_run` and `status: "active"`. Re-read each document first and pin `if_version`.

## 7. Save and report
- Add the featured trades to `congress/USED.md`.
- Commit the episode and `USED.md`, using the commit attribution lines, and push to `main`.
- Send the owner the MP4 with a one-line summary. Add the YouTube title and the full description (hashtags at the end), each in its own code block, then "Ready for you to post. It's in the dashboard."

## Leads
None right now. To add one, write `- **<date>: <who> × <company> (<ticker>).**` and follow it with the trades, the closes and any caution.
