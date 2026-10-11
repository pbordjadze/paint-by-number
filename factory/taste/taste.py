"""The taste loop's deterministic half (first run: naming the panel, `factory/pieces/panel-name`): draw, prompts, Craft checks, slates, scoring, ledger.

Agents do only what needs taste (propose, judge); everything else is code, seeded, so a round
replays exactly from its files. Usage:
  taste.py draw N | proposals N | collect N | decide N | status
"""
import json, os, random, re, sys, unicodedata

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = "/home/user/paint-by-number"
RUN = os.environ.get("TASTE_RUN", os.path.join(REPO, "factory", "pieces", "panel-name"))
INCUMBENT = "Guardians of the Vibes"
JURY, PROPOSERS, PER_PROPOSER, CARRY = 6, 4, 3, 3

def load(p, default=None):
    return json.load(open(p)) if os.path.exists(p) else default

def save(p, obj):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(obj, open(p, "w"), indent=2, ensure_ascii=False)

def rdir(n): return os.path.join(RUN, "rounds", f"{n:03d}")

def charters():
    md = open(f"{REPO}/factory/GUARDIANS.md").read().split("## The panel", 1)[1]
    out = {}
    for chunk in re.split(r"^### ", md, flags=re.M)[1:]:
        lines = chunk.rstrip().splitlines()
        out[lines[0].strip()] = "\n".join(lines[1:]).strip()
    out["The jury › Originality"] = ("- **believes**: nothing we make should look like someone else's.\n"
        "- **guards against**: franchise look-alikes (anything that recalls Harry Potter, Disney, Marvel, "
        "Tolkien, Star Wars or another famous property); names of well-known existing groups or products; "
        "harmful caricature.\n- It can only veto. It never votes on taste.")
    return out

def guardians():
    panel = load(f"{REPO}/factory/panel.json")
    ch = charters()
    gs = []
    for g in panel["guardians"]:
        name = re.sub(r"\s*\(.*\)$", "", g["charter"].replace("The jury › ", ""))
        gs.append({**g, "name": name, "charter_text": ch[g["charter"]]})
    return gs

def believes(text):
    m = re.search(r"\*\*believes\*\*: (.+?)(?:\n- |\Z)", text, re.S)
    return " ".join(m.group(1).split()) if m else ""

def roster():
    return "\n".join(f"- {g['name']}: {believes(g['charter_text'])}" for g in guardians()
                     if g["active"] and not g.get("vetoOnly"))

def ledger(): return load(os.path.join(RUN, "ledger.json"), {"rounds": []})

def rounds_since_represented(gid, n):
    """Rounds since this guardian last found itself in a winner (0 before anyone has won)."""
    led = ledger()["rounds"]
    if not led: return 0
    for back, entry in enumerate(reversed(led)):
        if gid in entry["represented"]: return back
    return len(led)

def weight(g, n):
    return g.get("baseWeight", 1) * min(2.0, 1 + 0.5 * rounds_since_represented(g["id"], n))

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
    gs = [g for g in guardians() if g["active"]]
    rng = random.Random(f"draw-{n}")
    pool = [g for g in gs if not g.get("vetoOnly")]
    rng.shuffle(pool)  # seeded tie-break
    pool.sort(key=lambda g: -rounds_since_represented(g["id"], n))
    prev = load(os.path.join(rdir(n - 1), "draw.json"), {"jury": [], "proposers": []}) if n > 1 else {"jury": [], "proposers": []}
    recent = set(prev["jury"]) | set(prev["proposers"])
    # Least represented first; among equals, those who sat out last round first.
    pool.sort(key=lambda g: (-rounds_since_represented(g["id"], n), g["id"] in recent))
    jury = ["originality"] + [g["id"] for g in pool[:JURY - 1]]
    proposers = [g["id"] for g in pool[JURY - 1:JURY - 1 + PROPOSERS]]
    save(os.path.join(rdir(n), "draw.json"), {"round": n, "jury": jury, "proposers": proposers,
         "weights": {g["id"]: weight(g, n) for g in gs if g["id"] in jury}})
    print(json.dumps({"jury": jury, "proposers": proposers}))

BRIEF = """Medea is an iPhone and iPad app that turns a photo into a paint-by-numbers painting, made on the device, that you then paint with your finger or Apple Pencil. It is named for Medea of Colchis (today's western Georgia): a kind, helpful witch whose magic makes the old new. Its look should remind anyone who knows Georgia of Georgia, without being obviously Georgian (no flags, no Georgian letters as decoration, no tourist cliches). It must never look like Harry Potter, Disney or any other famous franchise.

Every design decision for the app (colors, logo, animations, words) is judged by a panel of guardians. Each guardian keeps one idea and judges every design for it; for each decision a jury of six is drawn from the panel. These are the guardians:
{roster}

The panel needs a name for itself: what the guardians are called together. The name appears on review pages and in the record of decisions ("This palette was chosen by ..."), and it may one day be seen by the app's users, so it should be beautiful, memorable and true to the panel."""

def guardian_by_id():
    return {g["id"]: g for g in guardians()}

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
    for gid in d["proposers"]:
        g = G[gid]
        out = os.path.join(rdir(n), "proposals", f"{gid}.json")
        text = f"""You are {g['name']}, one of the guardians on a design panel. Stay in character: you see everything through your idea.

{BRIEF.format(roster=roster())}

Your charter:
{g['charter_text']}

{context}

Your task: propose {PER_PROPOSER} names for the panel, each 1 to 4 words, letters and spaces only. Each should bring your idea into the name while serving the whole panel. Make them different from each other. Avoid the generic (council, collective, committee, guild of X) unless you make it sing.

Write this JSON, and nothing else, to the file {out} with the Write tool:
{{"proposals": [{{"name": "...", "why": "one sentence, in your voice"}}]}}

Then reply with only the word done."""
        p = os.path.join(rdir(n), "prompts", f"propose-{gid}.txt")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(text)
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
        slate.append({"name": name, "source": source, "why": why, "origin": origin or source})
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
    for gid in d["jury"]:
        g = G[gid]
        rng = random.Random(f"ballot-{n}-{gid}")
        order = list(range(len(slate))); rng.shuffle(order)
        letters = [chr(65 + i) for i in range(len(slate))]
        ballot = {letters[i]: slate[j]["name"] for i, j in enumerate(order)}
        save(os.path.join(rdir(n), "ballots", f"{gid}.json"), ballot)
        listing = "\n".join(f"[{L}] {nm}\n    " + "\n    ".join(in_context(nm)) for L, nm in ballot.items())
        out = os.path.join(rdir(n), "verdicts", f"{gid}.json")
        if g.get("vetoOnly"):
            task = f"""For each candidate, decide whether it must be vetoed: it recalls a famous franchise (Harry Potter, Disney, Marvel, Tolkien, Star Wars or similar), it is the name of a well-known existing group or product, or it caricatures a people or tradition. Veto only for a real problem; most names should pass.

Write this JSON, and nothing else, to the file {out} with the Write tool:
{{"candidates": {{"A": {{"veto": null}}, "B": {{"veto": "the reason"}}}}}}
(one entry per letter, every letter)"""
        else:
            task = f"""For each candidate say:
- lives: where your idea lives in it, in at most 15 words, or "absent";
- veto: null, or a reason, only if it truly betrays your idea (rare);
Then rank every candidate from best to worst for the panel, judging as yourself, and say in one sentence why your first choice is best.

Write this JSON, and nothing else, to the file {out} with the Write tool:
{{"candidates": {{"A": {{"lives": "...", "veto": null}}}}, "ranking": ["C", "A", "..."], "note": "..."}}
(one entry per letter; the ranking lists every letter exactly once)"""
        text = f"""You are {g['name']}, sitting on a jury of the design panel. Stay in character: you judge through your idea.

{BRIEF.format(roster=roster())}

Your charter:
{g['charter_text']}

The jury is choosing the panel's name. The candidates, each shown as it would read in use, in an order shuffled for you alone:

{listing}

{task}

Then reply with only the word done."""
        p = os.path.join(rdir(n), "prompts", f"judge-{gid}.txt")
        open(p, "w").write(text)
        print(p)
    print(f"slate {len(slate)}, rejected {len(rejected)}")

def decide(n):
    d = load(os.path.join(rdir(n), "draw.json"))
    G = guardian_by_id()
    slate = load(os.path.join(rdir(n), "slate.json"))["slate"]
    names = [s["name"] for s in slate]
    score = {nm: 0.0 for nm in names}; firsts = {nm: 0 for nm in names}
    vetoes = {nm: [] for nm in names}; notes = {nm: [] for nm in names}; lives = {nm: {} for nm in names}
    problems = []
    for gid in d["jury"]:
        ballot = load(os.path.join(rdir(n), "ballots", f"{gid}.json"))
        v = load(os.path.join(rdir(n), "verdicts", f"{gid}.json"))
        if v is None: problems.append(f"{gid}: no verdict"); continue
        for L, c in v.get("candidates", {}).items():
            if L not in ballot: continue
            nm = ballot[L]
            if c.get("veto"): vetoes[nm].append(f"{G[gid]['name']}: {c['veto']}")
            if c.get("lives"): lives[nm][gid] = c["lives"]
        if G[gid].get("vetoOnly"): continue
        rank = [L for L in v.get("ranking", []) if L in ballot]
        missing = [L for L in ballot if L not in rank]
        if missing or len(set(rank)) != len(rank): problems.append(f"{gid}: ranking incomplete or repeated ({len(set(rank))}/{len(ballot)})")
        rank = list(dict.fromkeys(rank)) + missing  # unranked go last, in letter order
        w = d["weights"][gid]
        for pos, L in enumerate(rank):
            score[ballot[L]] += w * (len(rank) - 1 - pos)
        firsts[ballot[rank[0]]] += 1
        if v.get("note"): notes[ballot[rank[0]]].append(f"{G[gid]['name']}: {v['note']}")
    champ = load(os.path.join(RUN, "champion.json"), {"name": INCUMBENT})["name"]
    alive = [nm for nm in names if not vetoes[nm]] or sorted(names, key=lambda nm: len(vetoes[nm]))[:1]
    order = sorted(names, key=lambda nm: (nm not in alive, -score[nm], -firsts[nm], nm != champ, nm))
    winner = order[0]
    absent = re.compile(r"^\s*absent\b", re.I)
    represented = [gid for gid, line in lives[winner].items() if not absent.match(line)]
    # Whoever proposed the winner lives in it too.
    origin = next(s.get("origin", s["source"]) for s in slate if s["name"] == winner)
    if origin in G and origin not in represented: represented.append(origin)
    standings = [{"name": nm, "score": round(score[nm], 2), "firsts": firsts[nm], "vetoed": vetoes[nm],
                  "notes": notes[nm], "lives": lives[nm],
                  "source": next(s["source"] for s in slate if s["name"] == nm),
                  "origin": next(s.get("origin", s["source"]) for s in slate if s["name"] == nm)} for nm in order]
    save(os.path.join(rdir(n), "decision.json"), {"round": n, "winner": winner, "standings": standings, "problems": problems})
    led = ledger(); led["rounds"] = [r for r in led["rounds"] if r["round"] != n]
    led["rounds"].append({"round": n, "winner": winner, "represented": represented,
                          "lines": {gid: lives[winner][gid] for gid in lives[winner]}})
    save(os.path.join(RUN, "ledger.json"), led)
    save(os.path.join(RUN, "champion.json"), {"name": winner, "round": n})
    for s in standings[:8]:
        print(f'{s["score"]:6.1f} {s["firsts"]}x1st {"VETO " if s["vetoed"] else ""}{s["name"]}  [{s["source"]}]')
    print("winner:", winner, "| represented:", represented, "| problems:", problems)

if __name__ == "__main__":
    cmd, *rest = sys.argv[1:]
    {"draw": draw, "proposals": proposals, "collect": collect, "decide": decide}[cmd](*(int(x) for x in rest))
