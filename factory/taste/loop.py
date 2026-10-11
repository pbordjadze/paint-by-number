"""The deterministic half of a taste run.

Pieces supply candidates, prompts, tie preferences and a whole-set caps hook. The loop owns
draws, blind ballots, weighted Borda scoring, vetoes, selection and the representation ledger.
rules.json snapshots the rules and seats before a run starts; replay never reads today's panel.
The two migrated runs retain their historical output schemas and Originality's v2 exemption.
New v2 runs require a guards-against quote from every seat, including Originality.
"""
import json
import os
import random
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def load(path, default=None):
    path = Path(path)
    return json.loads(path.read_text()) if path.exists() else default


def save(path, obj):
    write_atomic(path, json.dumps(obj, indent=2, ensure_ascii=False))


def write_atomic(path, text):
    """Readers poll for these files (jobs, replies), so one must never see a half-written file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_text(text)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def charter_line(text, field):
    match = re.search(r"\*\*" + re.escape(field) + r"\*\*: (.+?)(?:\n- |\Z)", text, re.S)
    return " ".join(match.group(1).split()) if match else ""


def charters():
    md = (REPO / "factory/GUARDIANS.md").read_text().split("## The panel", 1)[1]
    out = {}
    for chunk in re.split(r"^### ", md, flags=re.M)[1:]:
        lines = chunk.rstrip().splitlines()
        out[lines[0].strip()] = "\n".join(lines[1:]).strip()
    out["The jury › Originality"] = (
        "- **believes**: nothing we make should look like someone else's.\n"
        "- **guards against**: franchise look-alikes (anything that recalls Harry Potter, Disney, Marvel, "
        "Tolkien, Star Wars or another famous property); names of well-known existing groups or products; "
        "harmful caricature.\n- It can only veto. It never votes on taste.")
    return out


def guardians():
    ch = charters()
    return [{**g, "name": re.sub(r"\s*\(.*\)$", "", g["charter"].replace("The jury › ", "")),
             "charter_text": ch[g["charter"]]}
            for g in load(REPO / "factory/panel.json")["guardians"]]


def fresh_rules(piece, *, version=2, recorded=False, vocabulary=None):
    record = {"version": version, "piece": piece, "recorded": recorded,
              "originalityFreeVeto": recorded and version == 2,
              "sharedBar": not recorded, "guarantee": piece == "color-names",
              "calibration": {}, "guardians": guardians(),
              "glossary": load(REPO / "factory/taste/glossary.json")}
    if vocabulary is not None:
        record["vocabulary"] = vocabulary
    return record


def rules(run, piece, *, version=2, recorded=False, vocabulary=None):
    """Create once, then always use the stored rule set. Unknown versions fail closed."""
    path = Path(run) / "rules.json"
    record = load(path)
    if record is None:
        record = fresh_rules(piece, version=version, recorded=recorded, vocabulary=vocabulary)
        save(path, record)
    if record["version"] not in (1, 2):
        raise ValueError(f"unsupported taste rules v{record['version']}")
    if record["piece"] != piece:
        raise ValueError(f"rules are for {record['piece']}, not {piece}")
    return record


def seats(record):
    """Aliases resolve old IDs without changing the keys written to historical artifacts."""
    out = {}
    for guardian in record["guardians"]:
        out[guardian["id"]] = guardian
        for alias in guardian.get("aliases", []):
            out[alias] = guardian
    return out


def canonical(gid, gs):
    return gs.get(gid, {}).get("id", gid)


def rounds_since_represented(gid, ledger, gs=None):
    gs = gs or {}
    gid = canonical(gid, gs)
    for back, entry in enumerate(reversed(ledger["rounds"])):
        if gid in [canonical(g, gs) for g in entry["represented"]]:
            return back
    return len(ledger["rounds"])


def weight(guardian, ledger, calibration=None, gs=None):
    boost = min(2.0, 1 + 0.5 * rounds_since_represented(guardian["id"], ledger, gs))
    return guardian.get("baseWeight", 1) * boost * (calibration or {}).get(guardian["id"], 1)


def draw(gs, ledger, seed, *, jury_size=6, proposers=4, recent=(), calibration=None):
    """Least represented first; seed breaks ties, then seats that sat out go first."""
    by_id = seats({"guardians": gs})
    pool = [g for g in gs if g["active"] and not g.get("vetoOnly")]
    random.Random(seed).shuffle(pool)
    recent = {canonical(g, by_id) for g in recent}
    pool.sort(key=lambda g: (-rounds_since_represented(g["id"], ledger, by_id), g["id"] in recent))
    jury = [g["id"] for g in gs if g["active"] and g.get("vetoOnly")]
    count = jury_size - len(jury)
    if count < 0 or len(pool) < count + proposers:
        raise ValueError("not enough seats for a disjoint jury and proposers")
    jury += [g["id"] for g in pool[:count]]
    return {"jury": jury, "proposers": [g["id"] for g in pool[count:count + proposers]],
            "weights": {g["id"]: weight(g, ledger, calibration, by_id)
                        for g in gs if g["id"] in jury}}


def ballot(names, seed):
    order = list(range(len(names)))
    random.Random(seed).shuffle(order)
    return {chr(65 + i): names[j] for i, j in enumerate(order)}


def score(names, jury, ballots, verdicts, record, *, weights=None, ledger=None):
    """Verdicts use candidates/ ranking/ note; adapters translate a piece's agent format."""
    gs = seats(record)
    scores = {n: 0.0 for n in names}
    firsts = {n: 0 for n in names}
    vetoes = {n: [] for n in names}
    notes = {n: [] for n in names}
    lives = {n: {} for n in names}
    ignored, problems = [], []
    method = record.get("scoring", "borda")
    if method not in ("borda", "approval", "copeland"):
        raise ValueError(f"unknown scoring method: {method}")
    pairs = {a: {b: 0.0 for b in names if b != a} for a in names}
    for gid in jury:
        b, v, g = ballots[gid], verdicts.get(gid), gs[gid]
        if v is None:
            problems.append(f"{gid}: no verdict")
            continue
        for letter, candidate in v.get("candidates", {}).items():
            if letter not in b:
                continue
            name, quote = b[letter], candidate.get("veto")
            if quote:
                q = " ".join(str(quote).split()).lower().strip('".')
                guards = charter_line(g["charter_text"], "guards against").lower()
                policy = record.get("vetoPolicy", "free" if record["version"] == 1 else "quote")
                accepted = (policy == "free" or
                            (g.get("vetoOnly") and record.get("originalityFreeVeto", False)) or
                            (q and q in guards))
                if policy == "off":
                    pass
                elif accepted:
                    vetoes[name].append(f"{g['name']}: {quote}")
                else:
                    ignored.append(f"{g['name']} on {name}: {quote}")
            if candidate.get("lives"):
                lives[name][gid] = candidate["lives"]
        if g.get("vetoOnly"):
            continue
        rank = [letter for letter in v.get("ranking", []) if letter in b]
        missing = [letter for letter in b if letter not in rank]
        if missing or len(set(rank)) != len(rank):
            problems.append(f"{gid}: ranking incomplete or repeated ({len(set(rank))}/{len(b)})")
        rank = list(dict.fromkeys(rank)) + missing
        if not rank:
            continue
        w = (weights[gid] if weights is not None else
             weight(g, ledger or {"rounds": []}, record.get("calibration"), gs))
        for pos, letter in enumerate(rank):
            if method == "borda":
                scores[b[letter]] += w * (len(rank) - 1 - pos)
            elif method == "approval":
                scores[b[letter]] += w * (letter in v.get("approval", []))
            else:
                for later in rank[pos + 1:]:
                    pairs[b[letter]][b[later]] += w
        firsts[b[rank[0]]] += 1
        if v.get("note"):
            notes[b[rank[0]]].append(f"{g['name']}: {v['note']}")
    if method == "copeland":
        scores = {a: sum(1 if support > pairs[b][a] else 0.5 if support == pairs[b][a] else 0
                         for b, support in pairs[a].items()) for a in names}
    return {"score": scores, "firsts": firsts, "vetoes": vetoes, "notes": notes,
            "lives": lives, "ignored": ignored, "problems": problems}


def favorites(standings, veto_key="vetoes"):
    eligible = [s for s in standings if not s[veto_key]]
    return {"broad_favorite": max(eligible, key=lambda s: s["score"])["name"] if eligible else None,
            "most_loved": max(eligible, key=lambda s: (s["firsts"], s["score"]))["name"] if eligible else None}


def record_round(run, entry):
    ledger = load(Path(run) / "ledger.json", {"rounds": []})
    ledger["rounds"] = [r for r in ledger["rounds"] if r["round"] != entry["round"]]
    ledger["rounds"].append(entry)
    ledger["rounds"].sort(key=lambda r: r["round"])
    save(Path(run) / "ledger.json", ledger)


def history(run, gid, gs):
    """The proposer's past names and their measured reception, across this run."""
    lines = []
    for path in sorted(Path(run).glob("rounds/*/decision.json")):
        dec = load(path)
        if "results" in dec:
            for result in dec["results"]:
                for standing in result["standings"]:
                    if canonical(standing["source"], gs) == canonical(gid, gs):
                        lines.append(f"- Round {dec['round']}, slot {result['slot']}: {standing['name']} — "
                                     f"{standing['score']} points, {standing['firsts']} first places" +
                                     ("; vetoed" if standing["vetoes"] else "") +
                                     ("; won" if standing["name"] == result["winner"] else ""))
            continue
        for standing in dec["standings"]:
            if canonical(standing.get("origin", standing["source"]), gs) == canonical(gid, gs):
                lines.append(f"- Round {dec['round']}: {standing['name']} — {standing['score']} points, "
                             f"{standing['firsts']} first places" +
                             ("; vetoed" if standing.get("vetoed") else "") +
                             ("; won" if standing["name"] == dec["winner"] else ""))
    color_dec = load(Path(run) / "decision.json", [])
    if isinstance(color_dec, list):
        for result in color_dec:
            for standing in result["standings"]:
                if canonical(standing["source"], gs) == canonical(gid, gs):
                    lines.append(f"- Color {result['slot']}: {standing['name']} — {standing['score']} points, "
                                 f"{standing['firsts']} first places" +
                                 ("; vetoed" if standing["vetoes"] else "") +
                                 ("; won" if standing["name"] == result["winner"] else ""))
    return "Your past names and how they fared:\n" + ("\n".join(lines) or "None yet.")


def glossary_prompt(record):
    glossary = record["glossary"]
    return "Georgian glossary (ordinary cultural words, not franchise references):\n" + "\n".join(
        f"- {word}: {meaning}" for word, meaning in glossary["words"].items())


def veto_instruction(record):
    if record.get("vetoPolicy") == "off":
        return "Vetoes are off: every veto must be null."
    if record.get("vetoPolicy") == "free":
        return "Veto only for a real problem and give its reason."
    if record["version"] == 1:
        return "Veto only for a real problem and give its reason."
    exemption = "Originality may give a reason instead." if record.get("originalityFreeVeto") else "This includes Originality."
    return "Every veto must quote exact words from your charter's guards against line. " + exemption


THREAD = ("The Georgian thread is felt, not named: use materials, light, gardens and habits. "
          "Across the whole set, at most one name in fifty uses a Georgian place name, "
          "and at most one in thirty uses a Georgian word.")


def georgian_caps(table, glossary):
    """Count names, not occurrences; match whole terms (including multiword places)."""
    def contains(name, terms):
        return any(re.search(r"(?<![a-z])" + re.escape(term.lower()) + r"(?![a-z])", name.lower())
                   for term in terms)
    names = list(table.values())
    return [(kind, "Georgian " + kind) for kind, terms, denominator in
            (("places", glossary["places"], 50), ("words", glossary["words"], 30))
            if sum(contains(n, terms) for n in names) > len(names) // denominator]


def select(results, base, slot_keys, caps_hook, *, owners=(), guarantee=False, recorded=False, identity=str.casefold):
    """Unique names, then whole-set caps, then an optional owner guarantee.

    The caps hook returns violations as (kind, word) pairs. The piece supplies which winners
    contribute to each violation and the identity hook used for all name comparisons. A guarantee never relaxes vetoes, uniqueness or caps.
    If no legal assignment is available, report failure instead of silently breaking a rule.
    """
    def table(skip=None, name=None):
        t = dict(base)
        for r in results:
            t[slot_keys[r["slot"]]] = name if r is skip else r["winner"]
        return t

    def fits(r, name, caps=True):
        t = table(r, name)
        return sum(identity(value) == identity(name) for value in t.values()) == 1 and not (caps and caps_hook(t))

    def take(r, st, note):
        r.setdefault("notes", []).append(note)
        r.update(winner=st["name"], winner_source=st["source"])

    def winner_score(r):
        return next(st["score"] for st in r["standings"] if identity(st["name"]) == identity(r["winner"]))

    for r in sorted(results, key=winner_score):
        if sum(identity(value) == identity(r["winner"]) for value in table().values()) > 1:
            st = next((st for st in r["standings"] if not st["vetoes"] and fits(r, st["name"], caps=False)), None)
            if st:
                take(r, st, f'{r["winner"]} was won by a higher-scoring color too')
    # v2's recorded run limited this repair to ten substitutions.
    seen = set()
    for _ in range(10 if recorded else sum(len(r["standings"]) for r in results) + 1):
        broken = caps_hook(table())
        state = tuple(identity(r["winner"]) for r in results)
        if not broken or state in seen:
            break
        seen.add(state)
        pos, word = broken[0]
        culprits = [r for r in results if r["winner_source"] != "incumbent" and
                    caps_hook.contributes(r["winner"], pos, word)]
        if not culprits:
            break
        r = min(culprits, key=winner_score)
        st = next((st for st in r["standings"] if not st["vetoes"] and identity(st["name"]) != identity(r["winner"]) and fits(r, st["name"])), None)
        if not st:
            break
        take(r, st, f'{r["winner"]} would make too many names {"start" if pos == "lead" else "end"} with {word}')
    if guarantee:
        for gid in owners:
            mine = [r for r in results if r["owner"] == gid]
            if any(r["winner_source"] == gid for r in mine):
                continue
            best = None
            for r in mine:
                st = next((st for st in r["standings"] if st["source"] == gid and not st["vetoes"] and fits(r, st["name"])), None)
                if st:
                    gap = r["standings"][0]["score"] - st["score"]
                    if best is None or gap < best[0]:
                        best = (gap, r, st)
            if best:
                _, r, st = best
                take(r, st, f"guaranteed: {gid} had no color")
                r["guaranteed"] = True
    # Greedy substitutions preserve the recorded run. For new runs, interacting caps or
    # guarantees may need more than one change at once; search only if the greedy set is illegal.
    if not recorded:
        values = [identity(value) for value in table().values()]
        missing = [gid for gid in owners if not any(r["winner_source"] == gid for r in results)] if guarantee else []
        vetoed = any(next(st for st in r["standings"] if identity(st["name"]) == identity(r["winner"]))["vetoes"] for r in results)
        if caps_hook(table()) or len(set(values)) != len(values) or missing or vetoed:
            assignment = legal_assignment(results, base, slot_keys, caps_hook, owners if guarantee else (), identity=identity)
            if assignment is not None:
                for r in results:
                    st = assignment[r["slot"]]
                    if identity(st["name"]) != identity(r["winner"]):
                        take(r, st, "selected to satisfy uniqueness, caps and representation together")
                        r["guaranteed"] = guarantee and st["source"] == r["owner"]
    caps = [f"{word} ({pos})" for pos, word in caps_hook(table())]
    if not recorded:
        values = [identity(value) for value in table().values()]
        if caps or len(set(values)) != len(values):
            raise ValueError(f"no legal name set: caps={caps}, duplicates={len(values) - len(set(values))}")
        if any(next(st for st in r["standings"] if identity(st["name"]) == identity(r["winner"]))["vetoes"] for r in results):
            raise ValueError("no unvetoed winner available")
        if guarantee:
            missing = [gid for gid in owners if not any(r["winner_source"] == gid for r in results)]
            if missing:
                raise ValueError(f"no legal guaranteed slot for {missing}")
    return caps


def legal_assignment(results, base, slot_keys, caps_hook, owners, *, identity=str.casefold):
    """Deterministic fallback for interacting constraints; caps must count monotonically.

    Unassigned slots contain unique, non-word placeholders, keeping the whole-set size fixed
    for fractional caps. The most constrained slot goes first; current winners are tried first.
    """
    table = {key: value for key, value in base.items() if key not in slot_keys.values()}
    if len({identity(value) for value in table.values()}) != len(table):
        return None
    placeholders = {slot: object() for slot in slot_keys}
    for slot, key in slot_keys.items():
        table[key] = placeholders[slot]

    def partial_caps():
        return caps_hook({key: value if isinstance(value, str) else f"\0{key}" for key, value in table.items()})

    choices = {r["slot"]: sorted([s for s in r["standings"] if not s["vetoes"]],
                                 key=lambda s: identity(s["name"]) != identity(r["winner"])) for r in results}
    assigned = {}

    def search(remaining):
        represented = {s["source"] for s in assigned.values()}
        if not remaining:
            return set(owners) <= represented and not partial_caps()
        viable = {}
        for slot in remaining:
            key = slot_keys[slot]
            viable[slot] = []
            for candidate in choices[slot]:
                table[key] = candidate["name"]
                if sum(isinstance(value, str) and identity(value) == identity(candidate["name"]) for value in table.values()) == 1 and not partial_caps():
                    viable[slot].append(candidate)
            table[key] = placeholders[slot]
            if not viable[slot]:
                return False
        forced = {}
        for owner in owners:
            if owner in represented:
                continue
            available = [slot for slot in remaining if any(s["source"] == owner for s in viable[slot])]
            if not available:
                return False
            if len(available) == 1:
                slot = available[0]
                if slot in forced and forced[slot] != owner:
                    return False
                forced[slot] = owner
        slot = next(iter(forced)) if forced else min(remaining, key=lambda slot: len(viable[slot]))
        key = slot_keys[slot]
        for candidate in viable[slot]:
            if slot in forced and candidate["source"] != forced[slot]:
                continue
            assigned[slot] = candidate
            table[key] = candidate["name"]
            if search([s for s in remaining if s != slot]):
                return True
        assigned.pop(slot, None)
        table[key] = placeholders[slot]
        return False

    return assigned if search([r["slot"] for r in results]) else None


def second_jury(run, finalists, gs, ledger, *, seed="finalists", jury_size=6, calibration=None):
    """Write a separate blind finalist round. Agents supply verdicts; no agents run here."""
    folder = Path(run) / "finalists"
    d = draw(gs, ledger, seed, jury_size=jury_size, proposers=0, calibration=calibration)
    save(folder / "draw.json", d)
    save(folder / "slate.json", finalists)
    for gid in d["jury"]:
        save(folder / "ballots" / f"{gid}.json", ballot(finalists, f"{seed}-{gid}"))
    return d
