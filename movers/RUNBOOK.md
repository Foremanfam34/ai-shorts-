# Daily Movers runbook

Each weekday after the close, make one Stock Geek "Daily Movers" Short and check it.
- **If Postiz is connected and every check passes:** schedule it on YouTube for 7:00 pm ET (step 7). The owner can stop it until then.
- **Otherwise:** leave it in the dashboard for the owner to post.

**Never post anywhere except YouTube. Never post a video that failed a check.**

> **Auto-posting is paused** (the owner's call, Nov 5). Skip step 7 and leave every video for the owner to post, until they say to turn it back on.

## 0. Setup
- Work in `/home/user/ai-shorts-` (the `Foremanfam34/ai-shorts-` repo) and run `git pull`.
- If `models/` is missing, run `./setup.sh`. It downloads about 1.5 GB of voice and transcription models and installs the `postiz` CLI.
- **Catch up on earlier posts.** If `POSTIZ_API_KEY` is set, run `python3 tools/publish.py status --days 7 --views`. For each post that has a `url`, update its dashboard row (match on the title):
  - `platforms.youtube`: set `posted: true`, `url`, `views`
  - set `status: "posted"`

  Any post with an `error`: tell the owner in one line.

## 1. Is there a session to cover?
- Get SPY from `get_equity_quotes`. The market was open today if `quote.venue_last_trade_time` (the last regular-session trade) is today, at 3:59 pm ET or later. If it isn't, it was a holiday or weekend: stop and send one line saying so.
- Don't test `close.date` for this. Robinhood publishes the official close late in the evening, so at 5:15 pm it still shows yesterday.

## 2. Find the moves (Robinhood connector)
- **Regular session:** run `preview_scan` with these filters:
  - `FILTER_TYPE_INSTRUMENT_TYPE` `=` `STOCK`
  - `FILTER_TYPE_MARKET_CAP` `>` `15000000000`
  - expression `changeFromPrevDayRatio(session="regular")`, `OUTSIDE ["-0.06","0.06"]`

  Add `price(session="regular")` as a column. The result is large, so parse the saved file with Python.

  The scanner's daily candles roll over late in the evening. Until then, `close(candleCount=1, …)` is still yesterday's close, so a candle-to-candle expression shows yesterday's moves. If the expression above returns nothing (it can late at night), use `close(candleCount=1, candlePeriod="1d", session="regular") / close(candleCount=2, candlePeriod="1d", session="regular") - 1` instead.
- **Verify every stock you'll show** with `get_equity_quotes`, then recompute every % yourself:
  - **Previous close:** `quote.adjusted_previous_close`, the official close. The scanner's candle close can be off by cents to dimes.
  - **Today's close:** official only. Take it from today's day bar: `get_equity_historicals`, interval `day`, start today at 00:00Z, no end time. That bar appears after 7 pm ET, and its close is the official close. `close.price` also works once `close.date` is today, but that can take until the next morning.
  - **Never use `quote.last_trade_price` as the close.** It misses the closing auction: on Nov 5 AMD's last trade was $402.51, but its official close was $404.40.
  - If today's bar isn't there yet, wait for it. Don't publish with provisional numbers.
  - **If some of today's bars are still missing** (normal: on Nov 6, only 5 of 13 were out by 9:46 pm, and all of them by 7:30 am the next day):
    1. Finish everything that doesn't depend on them: the story, the narration draft, the earnings checks, and the after-hours numbers with their time.
    2. Schedule a follow-up check with `send_later` at the next of these times: 7:05 pm, 8:15 pm, 9:45 pm, then 7:30 am the next day. Give it the missing tickers and the closes you already have.
    3. At each check, fetch only the missing bars. Once every close is official, render, check, publish and send. Otherwise schedule the next check.
    4. Tell the owner in one line when the video will be late.
  - **Keeping info current:** if official closes later differ from anything already sent (a rounding change counts), re-render, replace the dashboard video and post text, and tell the owner exactly what changed.
  - **Chart history:** `get_equity_historicals` day bars. Ignore bars marked `interpolated: true`.
- **After the bell:**
  - Run `get_earnings_calendar` for today with `filter: high_market_cap` and keep the `pm` reporters.
  - Scan only those names: expression `symbol` `ANY_OF` [their tickers], market cap `> 10000000000`, and expression `tradeAllDay.price / price(session="regular") - 1` `OUTSIDE ["-0.05","0.05"]`.
  - Confirm the picks with quotes. The after-hours % is `last_non_reg_trade_price` against today's official close. Record the quote time.
  - On Fridays there are usually no big after-hours reports. Use the list scene for something else that's verified, such as a two-day scorecard.
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
- **Post text** (`post` in the episode). `movers/episodes/2026-11-04.json` is the model to follow.
  - `title`: the hook, 60 characters or less, e.g. "Datadog Beat Earnings… and Still Fell 14% 📉". Never promise a reason ("why…") the video doesn't give.
  - `description`, in this order:
    1. One or two sentences with the headline fact.
    2. "Thursday's big movers:" (use the right weekday), then one line per stock in on-screen order: `📈 Name (TICKER) +x.x%`.
    3. "After the bell (as of h:mm pm ET):", then each after-hours stock with its EPS vs expected.
    4. "S&P 500 (SPY): ±x.x%".
    5. The outro's comment question, then "Subscribe for the market's biggest moves every trading day."
    6. "After-hours prices can change by the open. Data: Robinhood. Narrated with an AI voice. Not financial advice."
  - `hashtags`: five tags: #stocks #stockmarket #earnings, the headline company, then #investing.
  - Every number in the description must match the video.
- Re-check every number in the file against your verified data with a quick Python script before rendering.

## 5. Render and check
- Run `python3 congress/render.py movers/episodes/YYYY-MM-DD.json`. It takes about 2 minutes.
- Read the "heard:" lines. Fix any name the voice misreads with `say_as`, and any caption wording with `caption_fix`.
- Fix any "cue not heard" warning by choosing a non-number cue word.
- The render writes `out/market-movers-YYYY-MM-DD-qa.json`. The auto-poster refuses any video whose report lists warnings, so fix them and re-render.
- Pull four or five frames with ffmpeg and look at them: the hook, bars, chart, list and outro. Check that nothing overlaps, every number matches your verified data, and the captions are spelled right.

## 6. Dashboard
The dashboard is https://claude.ai/artifact/PkXcf4fxhp49R6wgKxe8mH.
- Upload the MP4 and the cover as assets.
- Add a `videos/mm-YYYY-MM-DD` row:
  - `show: "Market Movers"`, `series: "movers"`, `status: "review"`, `created` (today), `duration`, `video`, `cover`
  - `post_title` (a YouTube title of 100 characters or less), `post_text`, `hashtags`
  - `checks`: post before the next open if it uses after-hours numbers; watch for caption errors; turn on the AI label
  - `platforms`: `youtube`, `tiktok` and `instagram`, each `{posted: false, url: "", views: 0}`
- Update `automations/daily-movers` with `last_run` (today) and `status: "active"`. Re-read each document first and pin `if_version`.

## 7. Publish to YouTube (only when every check passed)
**Go/no-go:** go only if all of these passed:
- the number re-check in step 4
- the frame check in step 5
- no QA warnings

If any failed and you can't fix it in this run, don't publish. Leave the row at `review` and tell the owner what's wrong.

Run `python3 tools/publish.py youtube movers/episodes/YYYY-MM-DD.json --at 19:00`. It runs its own checks (QA report, 1080×1920 with sound, video newer than the episode file, title length, not already scheduled), then uploads and schedules the post.

What to do with the result:
- **`SCHEDULED` (exit 0):**
  - Set the row to `status: "scheduled"`.
  - Set `platforms.youtube` to `{posted: false, scheduled_for: <goes_live_utc>, postiz_id: <postiz_id>, url: "", views: 0}`.
  - Run `python3 tools/publish.py status --days 1` and confirm the post is listed with the right time. If it isn't, run `hold` on it and tell the owner.
- **`NOT CONNECTED` (exit 2):** Postiz isn't connected in this session. Leave the row at `review` for the owner to post.
- **`NOT POSTED` (exit 5):** a check failed. Fix and re-render if you can (then run it again). Otherwise leave the row at `review` and pass the reasons on.
- **`ERROR` (exit 1):** leave the row at `review` and pass the error on. Don't retry more than once.

**Stopping a post:** if the owner replies "hold", "stop" or similar before it goes live, run `python3 tools/publish.py hold <postiz_id>` and set the row back to `review`. If they then say "post it", run `release <postiz_id>`.

**TikTok and Instagram:** never post there, even though Postiz could.

## 8. Save and report
- Commit the episode JSON and `publish/log.jsonl` (if it changed), using the commit attribution lines, and push to `main`.
- Send the owner the MP4 with a one-line summary of the story. Add the YouTube title and the full description (hashtags at the end), each in its own code block so it's easy to copy on a phone. Then one of:
  - "Goes live on YouTube at 7:00 PM ET. Reply **hold** to stop it."
  - "Ready for you to post. It's in the dashboard." Add the reason it wasn't auto-posted.
- **Fridays:** compare views on the week's posts (`status --days 7 --views`). In `movers/LEARNINGS.md`, add three lines: which hook style did best, which did worst, and what to try next week. Read that file before you write each hook.
