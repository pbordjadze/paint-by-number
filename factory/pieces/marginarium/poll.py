#!/usr/bin/env python3
"""A one-question poll of the whole Lamp: does it like the word "Marginarium", and for what?

  poll.py setup   writes prompts/<guardian>.md (options shuffled per guardian, seeded)
  poll.py tally   reads replies/<guardian>.json, writes tally.json and prints the summary

Advisory: nothing is decided here. The Lamp's own name stays the Lamp's call; anything else is Paul's.
"""
import json, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", ".."))
from factory.taste import loop  # noqa: E402

WORD = "Marginarium"
OPTIONS = {
    "A": "The Lamp's own name, in place of A Lamp Left Burning.",
    "B": "The place in the app where the Lamp lives: its members, the story of its work told in chapters, "
         "and the gallery of the colors it named.",
    "C": "The palette gallery alone: every color the Lamp named, who picked it and what the others said, "
         "released a few at a time.",
    "D": "The margins of each decision: the vetoes, runners-up and jurors' notes kept beside every choice.",
    "E": "The factory: the whole machine that proposes, renders, judges and keeps the ledger.",
    "F": "The chapters: the written story of how the Lamp made each decision.",
    "O": "Something else (say what).",
    "N": "Nothing: it shouldn't name anything.",
}
ORIGINALITY = """- **believes**: nothing we make should look like someone else's.
- **guards against**: franchise look-alikes (anything that recalls Harry Potter, Disney, Marvel, Tolkien, Star Wars or another famous property); names of well-known existing groups or products; harmful caricature.
- It can only veto. It never votes on taste."""

def shared_bar():
    text = (loop.REPO / "factory" / "GUARDIANS.md").read_text()
    return text.split("## The shared bar: Georgia\n", 1)[1].split("\n## ", 1)[0].strip()

INTRO = """You are {name}, one guardian of A Lamp Left Burning ("the Lamp"), the design panel of Medea, an iPhone and iPad app that turns a photo into a paint-by-numbers painting. Each guardian keeps one idea. Yours is below: answer as that guardian, in its voice, and only for its idea.

## Your charter

{charter}

## The shared bar

{bar}

## The question

A word has been put to the Lamp: **{word}**.

It is not a dictionary word. It is built like herbarium or planetarium: a place for marginalia, the notes and little drawings in a book's margins.
"""

VOTER = INTRO + """
Do you like it? As the Lamp's own name, or as the name of something else? These are the things it could name, in an order shuffled for you:

{options}

Your name, A Lamp Left Burning, was the Lamp's own choice in its first run, and it changes only if the Lamp wants it to. Everything else is Paul's to decide: your answers advise him.

## Answer

Write exactly this JSON to `{reply}` with the Write tool, then reply with the one word `done`. Do not search the web and read nothing else.

{{
  "guardian": "{id}",
  "score": 1 to 5 (1 dislike, 3 indifferent, 5 love),
  "lives": "where your idea lives in this word, or that it doesn't (one sentence)",
  "favorite": "the letter of the one thing it should name most",
  "approve": ["letters of any other options you would also be glad of"],
  "other": "if you chose O, what it should name; otherwise empty",
  "veto": null,
  "line": "one line in your own voice, at most 25 words, that could be quoted in the Lamp's story"
}}

A veto is {{"option": a letter, or "all" for the word itself, "quote": your guards-against line word for word, "why": one sentence}}. It must quote your **guards against** line and say how the word, or that use of it, betrays it. Merely disliking the word is a low score, not a veto.
"""

CHECKER = INTRO + """
You can only veto; you never vote on taste. Search the web for existing uses of the word: a product, app, brand, studio, book, band, shop or franchise called {word}, or something it would be mistaken for. Say what you find, with links.

## Answer

Write exactly this JSON to `{reply}` with the Write tool, then reply with the one word `done`.

{{
  "guardian": "{id}",
  "found": "what already uses this word, and how well known each is (two or three sentences)",
  "sources": ["links"],
  "veto": null,
  "line": "one line in your own voice, at most 25 words, that could be quoted in the Lamp's story"
}}

A veto is {{"option": "all", "quote": your guards-against line word for word, "why": one sentence}}: only when the word is already a well-known product, group or franchise, or caricatures someone. Most words pass.
"""

def voters():
    return [g for g in loop.guardians() if g["active"]]

def setup():
    os.makedirs(os.path.join(HERE, "prompts"), exist_ok=True)
    os.makedirs(os.path.join(HERE, "replies"), exist_ok=True)
    bar = shared_bar()
    for g in voters():
        reply = os.path.join(HERE, "replies", f"{g['id']}.json")
        if g.get("vetoOnly"):
            text = CHECKER.format(name=g["name"], charter=ORIGINALITY, bar=bar, word=WORD, reply=reply, id=g["id"])
        else:
            order = list(OPTIONS)
            random.Random(f"marginarium-{g['id']}").shuffle(order)
            opts = "\n".join(f"- **{k}**: {OPTIONS[k]}" for k in order)
            charter = g["charter_text"].strip()
            text = VOTER.format(name=g["name"], charter=charter, bar=bar, word=WORD, options=opts, reply=reply, id=g["id"])
        with open(os.path.join(HERE, "prompts", f"{g['id']}.md"), "w") as f:
            f.write(text)
        print(g["id"])

def tally():
    out = {"word": WORD, "options": OPTIONS, "replies": {}, "missing": []}
    favorite, approve, scores, vetoes = {}, {}, [], []
    for g in voters():
        p = os.path.join(HERE, "replies", f"{g['id']}.json")
        if not os.path.exists(p):
            out["missing"].append(g["id"]); continue
        r = json.load(open(p))
        out["replies"][g["id"]] = r
        v = r.get("veto")
        if v:
            quote = " ".join(str(v.get("quote", "")).split()).strip('"“” .')
            charter = ORIGINALITY if g.get("vetoOnly") else g["charter_text"]
            line = " ".join(charter.split("**guards against**:", 1)[1].split("\n- ", 1)[0].split())
            v["valid"] = bool(quote) and quote.rstrip(".") in line
            vetoes.append({"guardian": g["id"], **v})
        if g.get("vetoOnly"):
            continue
        scores.append(r["score"])
        fav = str(r.get("favorite", "")).strip().upper()[:1]
        favorite[fav] = favorite.get(fav, 0) + 1
        for k in {fav, *(str(a).strip().upper()[:1] for a in r.get("approve", []))}:
            approve[k] = approve.get(k, 0) + 1
    out["mean_score"] = round(sum(scores) / len(scores), 2) if scores else None
    out["scores"] = {str(s): scores.count(s) for s in range(1, 6)}
    out["favorite"] = dict(sorted(favorite.items(), key=lambda kv: (-kv[1], kv[0])))
    out["approve"] = dict(sorted(approve.items(), key=lambda kv: (-kv[1], kv[0])))
    out["vetoes"] = vetoes
    json.dump(out, open(os.path.join(HERE, "tally.json"), "w"), indent=2, ensure_ascii=False)
    print(json.dumps({k: out[k] for k in ("mean_score", "scores", "favorite", "approve", "missing")}, indent=1))
    for v in vetoes:
        print("veto", v["guardian"], v.get("option"), "valid" if v["valid"] else "INVALID", "-", v.get("why"))
    for gid, r in out["replies"].items():
        print(f"{gid:22} {r.get('score', '-')!s:2} {r.get('favorite', '-')!s:2} {r.get('line', '')}")

if __name__ == "__main__":
    {"setup": setup, "tally": tally}[sys.argv[1]]()
