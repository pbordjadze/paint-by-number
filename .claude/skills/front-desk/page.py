#!/usr/bin/env python3
"""Apply "decision answered" (or "decision asked") to the status page's cards in one step.

    page.py <decisions.json> drop <id> [<id> ...]
    page.py <decisions.json> add <card.json>
    page.py <decisions.json> check

<decisions.json> is the front desk's hand-written file behind the page's `datasets/decisions`
(SKILL.md › The status page). `drop` removes the answered cards, `add` appends a card (or a list
of them) and replaces any card with the same id, `check` only validates. Every command checks
the cards: each has an id, a title and one question (`ask`, at most one "?"), its `options`
are lettered ("a. …", "b. …"; `drop` and `add` letter unlettered labels in order) and an `image` is a
`data:image/…` URL under 150 KB with its `image_alt`. A card about how something looks needs
an image; mark it `"looks": true` and the check holds it to that.

After a change it prints the calls that publish it, which only the session can make (MCP tools):
the asset upload, the dataset update and the delete of the upload it replaced.
"""

import json
import os
import string
import sys

PAGE = "https://claude.ai/artifact/HWcNT2WZkA4kxvtGqyMbmo"
IMAGE_LIMIT = 150_000


def problems(cards):
    found, seen = [], set()
    for card in cards:
        name = card.get("id") or card.get("title") or "?"
        for key in ("id", "title", "ask"):
            if not card.get(key):
                found.append(f"{name}: no {key}")
        if card.get("id") in seen:
            found.append(f"{name}: id used twice")
        seen.add(card.get("id"))
        if str(card.get("ask", "")).count("?") > 1:
            found.append(f"{name}: asks more than one question; split the card")
        image = card.get("image")
        if image and not str(image).startswith("data:image/"):
            found.append(f"{name}: image is not a data:image/ URL (the page shows only those)")
        if image and len(image) > IMAGE_LIMIT:
            found.append(f"{name}: image is {len(image) // 1000} KB, over {IMAGE_LIMIT // 1000} KB")
        if image and not card.get("image_alt"):
            found.append(f"{name}: image has no image_alt")
        if card.get("looks") and not image:
            found.append(f"{name}: a card about looks needs an image")
    return found


def letter(cards):
    for card in cards:
        for n, option in enumerate(card.get("options") or []):
            mark = f"{string.ascii_lowercase[n]}. "
            if not str(option.get("label", "")).startswith(mark):
                option["label"] = mark + str(option.get("label", ""))


def main():
    if len(sys.argv) < 3 or sys.argv[2] not in ("drop", "add", "check"):
        sys.exit(__doc__)
    path, command, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    cards = json.load(open(path, encoding="utf-8"))
    before = json.dumps(cards)

    if command == "drop":
        missing = set(args) - {c.get("id") for c in cards}
        if missing:
            sys.exit(f"no card with id {', '.join(sorted(missing))}")
        cards = [c for c in cards if c.get("id") not in args]
    elif command == "add":
        new = json.load(open(args[0], encoding="utf-8"))
        new = new if isinstance(new, list) else [new]
        ids = {c.get("id") for c in new}
        cards = [c for c in cards if c.get("id") not in ids] + new
    if command != "check":
        letter(cards)

    found = problems(cards)
    for problem in found:
        print(f"problem: {problem}", file=sys.stderr)
    if found:
        sys.exit(1)
    if command == "check" or json.dumps(cards) == before:
        print(f"{len(cards)} cards, nothing changed")
        return
    with open(path, "w", encoding="utf-8") as out:
        json.dump(cards, out, indent=1, ensure_ascii=False)
        out.write("\n")

    print(f"{len(cards)} cards written. Now:")
    print(f"1. Artifact publish  url={PAGE}  file_path={os.path.abspath(path)}  asset=true  -> new url")
    print("2. ArtifactData get   collection=datasets doc_id=decisions (note its version and the old"
          " source.url)")
    print("3. ArtifactData update collection=datasets doc_id=decisions"
          " with that version: source.url = <new url>, updated = {at: <now>, by: \"front desk\"}")
    print(f"4. Artifact delete   url={PAGE}  path=<the 32 hex after _blob/ in the old source.url>")


if __name__ == "__main__":
    main()
