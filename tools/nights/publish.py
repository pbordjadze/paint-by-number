#!/usr/bin/env python3
"""Keeps Tonight's Picture's schedule (painting-company row 368): decides the nights, opens and closes
the painters' ballots, and lays out what the app downloads.

    tools/nights/publish.py STATE_DIR [--pool tools/nights/pool.json] [--relay URL] [--now ISO]

STATE_DIR is a checkout of the `nights` branch (empty the first time), which the Nights workflow
(.github/workflows/nights.yml) commits back as one orphan commit each run, so the branch holds only
what the app needs now. The app reads
https://raw.githubusercontent.com/pbordjadze/paint-by-number/nights/nights.json and the pictures it
names beside it.

A night is a calendar date, the same picture everywhere on that date (the night turns at each
painter's own midnight). Night D's picture is chosen on a ballot of three from the pool, open to
painters for the 24 hours before it closes at D-1 08:00 UTC, which is before D begins anywhere on
Earth (UTC+14 begins D at D-1 10:00 UTC). The relay counts the votes (feedback-relay/worker.js,
GET /v1/ballots/<D>); the most votes win, a tie or no vote at all goes to the earliest choice. A
picture is used once: the losers go back to the pool, so a later ballot can offer them again.
The first run seeds the 30 nights before today straight from the pool, so Earlier Nights starts full.

Writes into STATE_DIR:
  nights.json   {"format": 1, "generated", "pictures": {id: record}, "nights": [{"date", "picture"}],
                 "ballots": [{"night", "opens", "closes", "choices": [id, id, id]}]}
                The nights of the last 31 days and those already decided (up to tomorrow), the
                ballots still to close; a record is pool.json's, with "image" and "thumb" (paths
                beside nights.json, 2048 and 640 px on the long edge, sRGB JPEG) and "sha256" (of
                the image file).
  history.json  every night ever decided, oldest first: [{"date", "picture", "votes"}]
  pictures/, thumbs/  the files the window needs, nothing else.
"""
import argparse
import datetime as dt
import hashlib
import io
import json
import shutil
import sys
import time
import urllib.request
from pathlib import Path

from PIL import Image, ImageOps

UA = "PaintByMoonlight-nights/1.0 (open-access pictures)"
CLOSE_HOUR = 8
WINDOW_DAYS = 31
BALLOTS_AHEAD = 3
LONG_EDGE, THUMB_EDGE = 2048, 640


def closes_at(night):
    return dt.datetime.combine(night - dt.timedelta(days=1), dt.time(CLOSE_HOUR), dt.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def get(url, tries=6):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read(), r.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None, ""
            time.sleep(2 << attempt)
        except Exception:
            time.sleep(2 << attempt)
    raise RuntimeError(f"giving up on {url}")


def tally(relay, night):
    """The votes for night D's ballot, {picture id: count}; {} without a relay or an answer."""
    if not relay:
        return {}
    try:
        body, _ = get(f"{relay.rstrip('/')}/v1/ballots/{night.isoformat()}", tries=3)
        return json.loads(body).get("votes", {}) if body else {}
    except Exception as e:
        print(f"tally for {night}: {e}", file=sys.stderr)
        return {}


def prepare(record, state):
    """Downloads and sizes a picture's files once; later runs find them in the branch."""
    image = state / "pictures" / f"{record['id']}.jpg"
    thumb = state / "thumbs" / f"{record['id']}.jpg"
    if not image.exists() or not thumb.exists():
        body, kind = get(record["download"])
        if not body or not kind.startswith("image/"):
            raise RuntimeError(f"{record['id']}: no image at {record['download']} ({kind})")
        im = ImageOps.exif_transpose(Image.open(io.BytesIO(body))).convert("RGB")
        if "crop" in record and isinstance(record["crop"], list):
            im = im.crop(tuple(record["crop"]))
        for path, edge, quality in ((image, LONG_EDGE, 86), (thumb, THUMB_EDGE, 80)):
            copy = im.copy()
            copy.thumbnail((edge, edge), Image.Resampling.LANCZOS)
            path.parent.mkdir(parents=True, exist_ok=True)
            copy.save(path, "JPEG", quality=quality, optimize=True, progressive=False)
    out = {k: v for k, v in record.items() if k not in ("download", "crop")}
    out["image"] = f"pictures/{record['id']}.jpg"
    out["thumb"] = f"thumbs/{record['id']}.jpg"
    out["sha256"] = hashlib.sha256(image.read_bytes()).hexdigest()
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("state", type=Path)
    ap.add_argument("--pool", type=Path, default=Path(__file__).with_name("pool.json"))
    ap.add_argument("--relay", default="")
    ap.add_argument("--now", help="an ISO time in UTC, for a dry run")
    a = ap.parse_args()
    now = dt.datetime.fromisoformat(a.now.replace("Z", "+00:00")) if a.now else dt.datetime.now(dt.timezone.utc)
    today = now.date()
    pool = json.loads(a.pool.read_text())
    by_id = {r["id"]: r for r in pool}
    state = a.state
    state.mkdir(parents=True, exist_ok=True)
    hist_path, nights_path = state / "history.json", state / "nights.json"
    history = json.loads(hist_path.read_text()) if hist_path.exists() else []
    old = json.loads(nights_path.read_text()) if nights_path.exists() else {}
    ballots = [b for b in old.get("ballots", [])]
    used = {h["picture"] for h in history}

    def offered():
        return {c for b in ballots for c in b["choices"]}

    def take(n):
        busy = used | offered()
        picks = [r["id"] for r in pool if r["id"] not in busy][:n]
        if len(picks) < n:
            raise SystemExit("the pool has run out: add pictures to pool.json")
        return picks

    def decide(night, picture, votes=None):
        history.append({"date": night.isoformat(), "picture": picture, "votes": votes or {}})
        used.add(picture)

    if not history:
        for back in range(WINDOW_DAYS - 1, -1, -1):
            decide(today - dt.timedelta(days=back), take(1)[0])

    # Close the ballots whose time has come, oldest first.
    for b in sorted(ballots, key=lambda b: b["night"]):
        night = dt.date.fromisoformat(b["night"])
        if closes_at(night) <= now:
            votes = tally(a.relay, night)
            winner = max(b["choices"], key=lambda c: (votes.get(c, 0), -b["choices"].index(c)))
            ballots.remove(b)
            if b["night"] not in {h["date"] for h in history}:
                decide(night, winner, votes)

    # Every night that must be known by now has a picture, even if a run was missed.
    last = dt.date.fromisoformat(history[-1]["date"])
    while closes_at(last + dt.timedelta(days=1)) <= now:
        last += dt.timedelta(days=1)
        stale = next((b for b in ballots if b["night"] == last.isoformat()), None)
        if stale:
            ballots.remove(stale)
        decide(last, (stale["choices"][0] if stale else take(1)[0]))

    # Ballots for the nights after, opening a day before they close.
    night = last
    while len(ballots) < BALLOTS_AHEAD:
        night += dt.timedelta(days=1)
        if any(b["night"] == night.isoformat() for b in ballots):
            continue
        close = closes_at(night)
        ballots.append({"night": night.isoformat(), "opens": iso(close - dt.timedelta(days=1)),
                        "closes": iso(close), "choices": take(3)})
    ballots.sort(key=lambda b: b["night"])

    first = today - dt.timedelta(days=WINDOW_DAYS)
    window = [h for h in history if dt.date.fromisoformat(h["date"]) >= first]
    needed = {h["picture"] for h in window} | offered()
    pictures = {}
    for pid in sorted(needed):
        record = by_id.get(pid)
        if record is None:
            raise SystemExit(f"{pid} is scheduled but no longer in the pool")
        pictures[pid] = prepare(record, state)
    for folder in ("pictures", "thumbs"):
        for f in (state / folder).glob("*.jpg"):
            if f.stem not in needed:
                f.unlink()
    nights_path.write_text(json.dumps({
        "format": 1, "generated": iso(now), "pictures": pictures,
        "nights": [{"date": h["date"], "picture": h["picture"]} for h in window],
        "ballots": ballots,
    }, ensure_ascii=False, indent=1) + "\n")
    hist_path.write_text(json.dumps(history, ensure_ascii=False, indent=1) + "\n")
    tonight = window[-1]
    print(f"{len(window)} nights through {tonight['date']} ({by_id[tonight['picture']]['title']}); "
          f"ballots for {', '.join(b['night'] for b in ballots)}; {len(pictures)} pictures", file=sys.stderr)


if __name__ == "__main__":
    main()
