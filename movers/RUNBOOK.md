# Daily Movers runbook

Each weekday after the close, make one Stock Geek "Daily Movers" Short and leave it in the dashboard for review. **Never post anything.** The owner reviews and posts.

## 0. Setup
- Work in `/home/user/ai-shorts-` (the `Foremanfam34/ai-shorts-` repo) and run `git pull`.
- If `models/` is missing, run `./setup.sh`, which downloads about 1.5 GB of voice and transcription models.

## 1. Is there a session to cover?
- Get SPY from `get_equity_quotes`. If `close.date` is not today (US/Eastern), the market was closed (a holiday or weekend). Stop and send one line saying so.

## 2. Find the moves (Robinhood connector)
- **Regular session:** run `preview_scan` with these filters:
  - asset type `STOCK`
  - market cap `> 15000000000`
  - expression `close(candleCount=1, candlePeriod="1d", session="regular") / close(candleCount=2, candlePeriod="1d", session="regular") - 1`, `OUTSIDE ["-0.06","0.06"]`

  Add those two closes as columns. The result is large, so parse the saved file with Python.
- **Verify every stock you'll show:**
  - Today's close is `close.price` from `get_equity_quotes`, and its date must be today.
  - The previous close comes from the previous non-interpolated bar in `get_equity_historicals` (day interval).
  - Recompute the % change yourself. Ignore bars marked `interpolated: true`.
- **After the bell:**
  - Run `get_earnings_calendar` for today with `filter: high_market_cap` and keep the `pm` reporters.
  - Get their quotes. The after-hours % is `last_non_reg_trade_price` against today's official close.
  - Keep only moves of 5% or more, and record the quote time.
- **Why it moved:** use `get_earnings_results` for each featured stock (report date, EPS actual vs estimate). If you can't verify a reason, **give none**. Never guess at news, and never imply wrongdoing.
- **Market context:** SPY today vs the previous close, labelled "S&P 500 (SPY)".

## 3. Pick the story (about 40 seconds)
- **Hook:** the most surprising verified fact, such as "beat earnings and still fell 14%", or the biggest move by a well-known name.
- **Bars:** six movers (up and down), cued in the order the narration names them.
- **Chart:** the headline stock over roughly 6–8 weeks of daily closes. Mark the day's drop or jump, and add a stat such as "−32% in five trading days" if it's true.
- **List:** two or three after-the-bell earnings reactions with EPS vs estimate, labelled "After hours".
- **Outro:** after-hours prices can change, not financial advice, a question for the comments, and the Subscribe call to action.

## 4. Write the episode
- Copy the newest file in `movers/episodes/` to `movers/episodes/YYYY-MM-DD.json` and edit it. Keep the voice settings (`am_michael`, speed 1.1, pause_scale 0.8), the `caption_fix` entries, `music: groove`, and the `slug` pattern `market-movers-YYYY-MM-DD`.
- In `say` lines, spell numbers out ("fourteen percent") and say the weekday ("on Thursday") rather than "today", so the video still reads right the next morning.
- On screen, use the date ("NOV 5") rather than "TODAY".
- Re-check every number in the file against your verified data with a quick Python script before rendering.

## 5. Render and check
- Run `python3 congress/render.py movers/episodes/YYYY-MM-DD.json`. It takes about 2 minutes.
- Read the "heard:" lines. Fix any name the voice misreads with `say_as`, and any caption wording with `caption_fix`.
- Fix any "cue not heard" warning by choosing a non-number cue word.
- Pull four or five frames with ffmpeg and look at them: the hook, bars, chart, list and outro.

## 6. Dashboard
The dashboard is https://claude.ai/artifact/PkXcf4fxhp49R6wgKxe8mH.
- Upload the MP4 and the cover as assets.
- Add a `videos/mm-YYYY-MM-DD` row:
  - `show: "Market Movers"`, `series: "movers"`, `status: "review"`, `created` (today), `duration`, `video`, `cover`
  - `post_title` (a YouTube title of 100 characters or less), `post_text`, `hashtags`
  - `checks`: post before the next open if it uses after-hours numbers; watch for caption errors; turn on the AI label
  - `platforms`: `youtube`, `tiktok` and `instagram`, each `{posted: false, url: "", views: 0}`
- Update `automations/daily-movers` with `last_run` (today) and `status: "active"`. Re-read each document first and pin `if_version`.

## 7. Save and report
- Commit the episode JSON, using the commit attribution lines, and push to `main`.
- Send the MP4 to the owner with a one-line summary of the story and "ready for review in the dashboard".
