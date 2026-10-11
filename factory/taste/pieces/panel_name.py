"""The taste loop's deterministic half (first run: naming the panel, `factory/pieces/panel-name`): draw, prompts, Craft checks, slates, scoring, ledger.

Agents do only what needs taste (propose, judge); everything else is code, seeded, so a round
replays exactly from its files. Usage:
  taste.py draw N | proposals N | collect N | decide N | status
"""
import json, os, re, sys, unicodedata
from pathlib import Path
from .. import loop, transcripts
from ..loop import load, save

REPO = str(loop.REPO)

RUN = os.environ.get("TASTE_RUN", os.path.join(REPO, "factory", "pieces", "panel-name"))
INCUMBENT = "Guardians of the Vibes"
JURY, PROPOSERS, PER_PROPOSER, CARRY = 6, 4, 3, 3


def rules(): return loop.rules(RUN, "panel-name")

def guardians(): return rules()["guardians"]

def guardian_by_id(): return loop.seats(rules())

def roster():
    return "\n".join(f"- {g['name']}: {loop.charter_line(g['charter_text'], 'believes')}"
                     for g in guardians() if g["active"] and not g.get("vetoOnly"))

def ledger(): return load(os.path.join(RUN, "ledger.json"), {"rounds": []})

def rdir(n): return os.path.join(RUN, "rounds", f"{n:03d}")

# Rendering a name "in context": the text renderer for this piece.
def in_context(name):
    inner = "the " + name[4:] if name.startswith("The ") else name
    return [f"Medea · {name}", f"This palette was chosen by {inner}.", f"A jury of six from {inner} meets each round."]

FRANCHISE = ["phoenix", "hogwarts", "galaxy", "avengers", "justice league", "fellowship", "x-men",
             "watchmen", "jedi", "sith", "wizengamot", "dumbledore", "death eaters", "round table", "illuminati"]

def craft(name, taken):
    """Code checks a candidate must pass before any juror sees it; returns the failures."""
    fails = []
    words = name.split()
    if not 1 <= len(words) <= 4: fails.append("1 to 4 words")
    if len(name) > 32: fails.append("at most 32 characters")
    if any("Ⴀ" <= c <= "ჿ" or "Ა" <= c <= "Ჿ" for c in name): fails.append("no Georgian letters as ornament")
    if any(unicodedata.category(c)[0] not in "LZ" and c not in "'’-·&." for c in name): fails.append("letters only")
    if any(f in name.lower() for f in FRANCHISE): fails.append("names a famous franchise")
    key = re.sub(r"[^a-z]", "", unicodedata.normalize("NFKD", name.lower()).encode("ascii", "ignore").decode())
    key = key[3:] if key.startswith("the") else key
    if key in taken: fails.append("duplicate")
    return fails, key

def draw(n):
    rules()
    prev = load(os.path.join(rdir(n - 1), "draw.json"), {"jury": [], "proposers": []})
    # Only earlier entries count, even when replaying a completed run.
    prior = {"rounds": [r for r in ledger()["rounds"] if r["round"] < n]}
    d = loop.draw(guardians(), prior, f"draw-{n}", jury_size=JURY, proposers=PROPOSERS,
                  recent=prev["jury"] + prev["proposers"], calibration=rules()["calibration"])
    d = {"round": n, **d}
    save(os.path.join(rdir(n), "draw.json"), d)
    print(json.dumps({"jury": d["jury"], "proposers": d["proposers"]}))

BRIEF = """Medea is an iPhone and iPad app that turns a photo into a paint-by-numbers painting, made on the device, that you then paint with your finger or Apple Pencil. It is named for Medea of Colchis (today's western Georgia): a kind, helpful witch whose magic makes the old new. Its look should remind anyone who knows Georgia of Georgia, without being obviously Georgian (no flags, no Georgian letters as decoration, no tourist cliches). It must never look like Harry Potter, Disney or any other famous franchise.

Every design decision for the app (colors, logo, animations, words) is judged by a panel of guardians. Each guardian keeps one idea and judges every design for it; for each decision a jury of six is drawn from the panel. These are the guardians:
{roster}

The panel needs a name for itself: what the guardians are called together. The name appears on review pages and in the record of decisions ("This palette was chosen by ..."), and it may one day be seen by the app's users, so it should be beautiful, memorable and true to the panel."""

def proposals(n):
    d = load(os.path.join(rdir(n), "draw.json"))
    G = guardian_by_id()
    champ = load(os.path.join(RUN, "champion.json"), {"name": INCUMBENT, "notes": []})
    context = f'The panel\'s current working name is "{champ["name"]}".'
    if n > 1:
        dec = load(os.path.join(rdir(n - 1), "decision.json"))
        tops = dec["standings"][:CARRY]
        context = f'After round {n - 1}, the jury\'s favorites are:\n' + "\n".join(
            (f'- "{t["name"]}" (jurors said: ' + "; ".join(t["notes"][:3]) + ")" if t["notes"]
             else f'- "{t["name"]}" (ranked well by several jurors; no one\'s first choice)') for t in tops) + \
            "\nPropose names that could beat them. Don't resubmit them."
        favorites = loop.favorites(dec["standings"], "vetoed")
        context += (f"\nBroad favorite: {favorites['broad_favorite']}. "
                    f"Most-loved (most first places): {favorites['most_loved']}.")
    for gid in d["proposers"]:
        g = G[gid]
        out = os.path.join(rdir(n), "proposals", f"{gid}.json")
        text = f"""You are {g['name']}, one of the guardians on a design panel. Stay in character: you see everything through your idea.

{BRIEF.format(roster=roster())}

Your charter:
{g['charter_text']}

{context}

{loop.THREAD}

{loop.history(RUN, gid, G)}

Your task: propose {PER_PROPOSER} names for the panel, each 1 to 4 words, letters and spaces only. Each should bring your idea into the name while serving the whole panel. Make them different from each other. Avoid the generic (council, collective, committee, guild of X) unless you make it sing.

Reply with only this JSON, nothing else (no code fence):
{{"proposals": [{{"name": "...", "why": "one sentence, in your voice"}}]}}

"""
        p = os.path.join(rdir(n), "prompts", f"propose-{gid}.txt")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        Path(p).write_text(text)
        print(p)

def collect(n):
    d = load(os.path.join(rdir(n), "draw.json"))
    G = guardian_by_id()
    taken, slate, rejected = {}, [], []
    def add(name, source, why, origin=None):
        fails, key = craft(name, taken)
        if fails:
            rejected.append({"name": name, "source": source, "fails": fails}); return
        taken[key] = True
        candidate = {"name": name, "source": source, "why": why}
        if n >= rules().get("slateOriginsFromRound", 1):
            candidate["origin"] = origin or source
        slate.append(candidate)
    if n == 1:
        add(INCUMBENT, "incumbent", "")
    else:
        dec = load(os.path.join(rdir(n - 1), "decision.json"))
        for t in dec["standings"][:CARRY]:
            add(t["name"], "carried", "", t.get("origin"))
    for gid in d["proposers"]:
        p = os.path.join(rdir(n), "proposals", f"{gid}.json")
        try:
            for c in load(p)["proposals"][:PER_PROPOSER]:
                add(" ".join(c["name"].split()), gid, c.get("why", ""))
        except Exception as e:
            rejected.append({"name": None, "source": gid, "fails": [f"unreadable proposal: {e}"]})
    save(os.path.join(rdir(n), "slate.json"), {"slate": slate, "rejected": rejected})
    os.makedirs(os.path.join(rdir(n), "prompts"), exist_ok=True)
    for gid in d["jury"]:
        g = G[gid]
        ballot = loop.ballot([s["name"] for s in slate], f"ballot-{n}-{gid}")
        save(os.path.join(rdir(n), "ballots", f"{gid}.json"), ballot)
        listing = "\n".join(f"[{L}] {nm}\n    " + "\n    ".join(in_context(nm)) for L, nm in ballot.items())
        out = os.path.join(rdir(n), "verdicts", f"{gid}.json")
        if g.get("vetoOnly"):
            task = f"""For each candidate, decide whether it must be vetoed: it recalls a famous franchise (Harry Potter, Disney, Marvel, Tolkien, Star Wars or similar), it is the name of a well-known existing group or product, or it caricatures a people or tradition. Veto only for a real problem; most names should pass.

Reply with only this JSON, nothing else (no code fence):
{{"candidates": {{"A": {{"veto": null}}, "B": {{"veto": "the reason"}}}}}}
(one entry per letter, every letter)"""
        else:
            task = f"""For each candidate say:
- lives: where your idea lives in it, in at most 15 words, or "absent";
- veto: null, or a reason, only if it truly betrays your idea (rare);
Then rank every candidate from best to worst for the panel, judging as yourself, and say in one sentence why your first choice is best.

Reply with only this JSON, nothing else (no code fence):
{{"candidates": {{"A": {{"lives": "...", "veto": null}}}}, "ranking": ["C", "A", "..."], "note": "..."}}
(one entry per letter; the ranking lists every letter exactly once)"""
        text = f"""You are {g['name']}, sitting on a jury of the design panel. Stay in character: you judge through your idea.

{BRIEF.format(roster=roster())}

Your charter:
{g['charter_text']}

{loop.THREAD}

{loop.glossary_prompt(rules()) if g.get("vetoOnly") else ""}

The jury is choosing the panel's name. The candidates, each shown as it would read in use, in an order shuffled for you alone:

{listing}

{task}

{loop.veto_instruction(rules())}

"""
        p = os.path.join(rdir(n), "prompts", f"judge-{gid}.txt")
        Path(p).write_text(text)
        print(p)
    print(f"slate {len(slate)}, rejected {len(rejected)}")

def decide(n):
    d = load(os.path.join(rdir(n), "draw.json"))
    G = guardian_by_id()
    slate = load(os.path.join(rdir(n), "slate.json"))["slate"]
    names = [s["name"] for s in slate]
    tally = loop.score(names, d["jury"],
                       {gid: load(os.path.join(rdir(n), "ballots", f"{gid}.json")) for gid in d["jury"]},
                       {gid: load(os.path.join(rdir(n), "verdicts", f"{gid}.json")) for gid in d["jury"]},
                       rules(), weights=d["weights"])
    score, firsts, vetoes, notes, lives = (tally[k] for k in ("score", "firsts", "vetoes", "notes", "lives"))
    problems = tally["problems"]
    champ = load(os.path.join(RUN, "champion.json"), {"name": INCUMBENT})["name"]
    alive = [nm for nm in names if not vetoes[nm]] or sorted(names, key=lambda nm: len(vetoes[nm]))[:1]
    order = sorted(names, key=lambda nm: (nm not in alive, -score[nm], -firsts[nm], nm != champ, nm))
    winner = order[0]
    if not rules()["recorded"]:
        result = {"slot": 1, "owner": "panel", "winner": winner,
                  "winner_source": next(s["source"] for s in slate if s["name"] == winner),
                  "standings": [{"name": name, "source": next(s["source"] for s in slate if s["name"] == name),
                                 "score": score[name], "vetoes": vetoes[name]} for name in order]}
        loop.select([result], {0: champ}, {1: 0}, PanelCaps(rules()))
        winner = result["winner"]
    absent = re.compile(r"^\s*absent\b", re.I)
    represented = [gid for gid, line in lives[winner].items() if not absent.match(line)]
    # Whoever proposed the winner lives in it too.
    origin = next(s.get("origin", s["source"]) for s in slate if s["name"] == winner)
    if origin in G and origin not in represented: represented.append(origin)
    standings = [{"name": nm, "score": round(score[nm], 2), "firsts": firsts[nm], "vetoed": vetoes[nm],
                  "notes": notes[nm], "lives": lives[nm],
                  "source": next(s["source"] for s in slate if s["name"] == nm),
                  "origin": next(s.get("origin", s["source"]) for s in slate if s["name"] == nm)} for nm in order]
    decision = {"round": n, "winner": winner, "standings": standings, "problems": problems}
    if not rules()["recorded"]:
        decision.update(loop.favorites(standings, "vetoed"))
        decision["ignored_vetoes"] = tally["ignored"]
        if vetoes[winner]:
            raise ValueError("no unvetoed panel name")
    save(os.path.join(rdir(n), "decision.json"), decision)
    loop.record_round(RUN, {"round": n, "winner": winner, "represented": represented,
                            "lines": lives[winner]})
    save(os.path.join(RUN, "champion.json"), {"name": winner, "round": n})
    for s in standings[:8]:
        print(f'{s["score"]:6.1f} {s["firsts"]}x1st {"VETO " if s["vetoed"] else ""}{s["name"]}  [{s["source"]}]')
    print("winner:", winner, "| represented:", represented, "| problems:", problems)
    print("favorites:", loop.favorites(standings, "vetoed"))

def status():
    print(json.dumps(ledger(), indent=2, ensure_ascii=False))


def finalists(n):
    dec = load(os.path.join(rdir(n), "decision.json"))
    names = [s["name"] for s in dec["standings"] if not s["vetoed"]][:CARRY]
    d = loop.second_jury(rdir(n), names, guardians(), ledger(), seed=f"finalists-{n}")
    write_finalist_prompts(n, d)


def write_finalist_prompts(n, draw):
    folder = os.path.join(rdir(n), "finalists")
    for gid in draw["jury"]:
        g = guardian_by_id()[gid]
        b = load(os.path.join(folder, "ballots", f"{gid}.json"))
        listing = "\n".join(f"[{letter}] {name}\n" + "\n".join(in_context(name)) for letter, name in b.items())
        text = (f"You are {g['name']}.\n{BRIEF.format(roster=roster())}\nYour charter:\n{g['charter_text']}\n"
                f"{loop.THREAD}\n" + (loop.glossary_prompt(rules()) if g.get("vetoOnly") else "") +
                f"\nFinalists:\n{listing}\nReply with candidates (lives, veto), ranking and note as JSON. " +
                loop.veto_instruction(rules()) + " Originality only vetoes.")
        path = os.path.join(folder, "prompts", f"{gid}.txt")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Path(path).write_text(text)


def decide_finalists(n):
    folder = os.path.join(rdir(n), "finalists")
    d = load(os.path.join(folder, "draw.json"))
    names = load(os.path.join(folder, "slate.json"))
    result = loop.score(names, d["jury"],
                        {g: load(os.path.join(folder, "ballots", f"{g}.json")) for g in d["jury"]},
                        {g: load(os.path.join(folder, "verdicts", f"{g}.json")) for g in d["jury"]},
                        rules(), weights=d["weights"])
    order = sorted(names, key=lambda name: (bool(result["vetoes"][name]), -result["score"][name], -result["firsts"][name], name))
    if not order or result["vetoes"][order[0]]:
        raise ValueError("no unvetoed finalist")
    save(os.path.join(folder, "decision.json"), {"winner": order[0], "tally": result})


class PanelCaps:
    def __init__(self, record):
        self.record = record

    def __call__(self, table):
        return loop.georgian_caps(table, self.record["glossary"]) if self.record["sharedBar"] else []

    def contributes(self, name, pos, word):
        return bool(loop.georgian_caps({0: name}, self.record["glossary"]))


def main():
    cmd, *rest = sys.argv[1:]
    if cmd == "extract":
        # extract <round> <proposals|verdicts> <seat> <transcript.output>
        n, role, gid, path = rest
        if role not in ("proposals", "verdicts"):
            raise ValueError("role must be proposals or verdicts")
        save(os.path.join(rdir(int(n)), role, f"{gid}.json"), transcripts.extract(path))
    else:
        {"draw": draw, "proposals": proposals, "collect": collect, "decide": decide,
         "status": status, "finalists": finalists, "decide-finalists": decide_finalists}[cmd](*(int(x) for x in rest))
