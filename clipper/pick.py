"""Ask Claude to pick the best short-form moments from a timestamped transcript."""
import json

import anthropic

MODEL = "claude-opus-5-5"

SYSTEM = """You are a senior short-form video editor. You cut long podcasts and interviews into
YouTube Shorts, Instagram Reels and TikToks that people watch to the end and share.

What makes a good clip:
- It works with zero context: the first sentence hooks a stranger who just scrolled in.
- It contains one complete idea that lands: a surprising fact, a strong opinion, a story with a
  payoff, a funny exchange, or practical advice someone would save.
- It starts at the beginning of a sentence and ends right after the payoff, never mid-thought.
- Strong clips beat long clips. Cut the warm-up.

The transcript lines look like `[start-end] text`, in seconds from the start of the video.
Use those times for clip boundaries. Clips must not overlap."""

SCHEMA = {
    "type": "object",
    "properties": {
        "clips": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "start": {"type": "number", "description": "seconds; the start of a transcript line"},
                    "end": {"type": "number", "description": "seconds; the end of a transcript line"},
                    "title": {"type": "string", "description": "on-screen hook, 3-7 words, no emoji"},
                    "caption": {"type": "string", "description": "post description, 1-2 sentences"},
                    "hashtags": {"type": "array", "items": {"type": "string"}},
                    "why": {"type": "string", "description": "why this moment will perform"},
                    "score": {"type": "integer", "description": "1-10 predicted performance"},
                },
                "required": ["start", "end", "title", "caption", "hashtags", "why", "score"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["clips"],
    "additionalProperties": False,
}


def pick_moments(transcript_text, n=5, min_len=15, max_len=60, model=MODEL, context=""):
    client = anthropic.Anthropic()  # ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN or an `ant auth login` profile
    prompt = (f"{context}\n\n" if context else "") + (
        f"Pick the {n} best clips, each {min_len}-{max_len} seconds long, best first.\n\n"
        f"<transcript>\n{transcript_text}\n</transcript>")
    with client.beta.messages.stream(
        model=model,
        max_tokens=32000,
        system=SYSTEM,
        messages=[{"role": "user", "content": prompt}],
        output_config={"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}},
        # If a safety classifier declines, re-run on Anthropic's recommended fallback model.
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    ) as stream:
        msg = stream.get_final_message()

    if msg.stop_reason == "refusal":
        detail = msg.stop_details.category if msg.stop_details else "unknown"
        raise RuntimeError(f"Claude declined to pick clips (category: {detail}); request id {msg._request_id}")
    if msg.stop_reason == "max_tokens":
        raise RuntimeError("Response was cut off (max_tokens); try fewer clips")

    text = ""
    for block in msg.content:  # keep only text produced after the last model switch, if any
        if block.type == "fallback":
            text = ""
        elif block.type == "text":
            text += block.text
    return json.loads(text)["clips"]
