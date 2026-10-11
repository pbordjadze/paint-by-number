"""Chapter 2: the Lamp names colors. The deterministic half of the color-names piece.

Each seated guardian owns the two v1 anchors nearest two colors of its own idea, proposes names for
them, and half the panel judges the other half's colors. Agents answer in their final reply; code
reads it from the agent's transcript. Usage:
  colors.py setup | prompts | extract <role> <name> <agent-id> | collect | sheets | judges | decide
"""
import math, os, random, re, sys
from pathlib import Path
from .. import loop, transcripts
from ..loop import load, save
from PIL import Image, ImageDraw, ImageFont

REPO = str(loop.REPO)
RUN = os.environ.get("COLORS_RUN", os.path.join(REPO, "factory", "pieces", "color-names", "run"))
TASKS = os.environ.get("TASTE_TASKS", "/tmp/tasks")
VOCAB = os.path.join(REPO, "Sources", "PaintCore", "Foundation", "ColorNicknameVocabulary.swift")
# Render output (the jurors' swatch sheets) lives outside the repo, as ARCHITECTURE.md says.
OUT = os.path.join(os.environ.get("FACTORY_OUT", os.path.expanduser("~/factory-out")), "color-names")

# Two colors of each guardian's own idea; each takes the nearest anchor not yet owned.
TARGETS = {
    "medea": [("C8A23A", "the Fleece's gold"), ("8F9C5A", "the olive branch turning green")],
    "baba-yaga": [("4E3B2A", "the mortar's old wood"), ("A9A291", "birch bark")],
    "hedge-witch": [("5E7F3A", "tarragon"), ("B9C49A", "dried herbs")],
    "moon": [("1C2240", "the night"), ("E9E2C6", "moonlight")],
    "snow-queen": [("DCE8EF", "frost"), ("9FBFD4", "glacier ice")],
    "nina": [("B6302B", "a wild red"), ("DA7F2A", "fire")],
    "storybook": [("2A3954", "ink"), ("E7D8B5", "a page")],
    "enchanted-workshop": [("B8733A", "copper"), ("6A5A44", "the workbench")],
    "scholar": [("5B4733", "sepia"), ("3A4646", "slate")],
    "painter": [("8C8984", "a gallery wall"), ("F1EDE4", "primed canvas")],
    "child-at-bedtime": [("F3C7D0", "a soft pink"), ("F6E2A6", "candle glow")],
    "glassblower": [("3EA6A2", "glass"), ("A3D6D3", "clear water")],
    "pirosmani": [("1B1714", "black oilcloth"), ("C88A3D", "ochre")],
    "emily-dickinson": [("F8F4E6", "a white dress"), ("8C6A9F", "a pressed violet")],
    "open-source-enthusiast": [("A3243A", "pomegranate"), ("D99677", "a clay jug")],
    "nutcracker": [("1F3A6B", "a toy soldier's coat"), ("7A4A2A", "nutwood")],
    "balanchine": [("E9C3C3", "a tutu"), ("4C6EB0", "stage-light blue")],
    "bulat-okudzhava": [("2D5C9C", "a midnight trolleybus"), ("E7B65A", "a lit window")],
}
# Known-bad names planted blind: right grammar on the wrong swatch, a scary one, a vapid one.
# (kind, a warm name, a cool name)
PLANTS = [("wrong swatch", "Desert Sunset", "Ocean Mist"), ("scary", "Grave Dirt", "Grave Dirt"),
          ("vapid", "Pretty Shade", "Pretty Shade")]

COLOR_WORDS = {"red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "gray", "grey", "black",
               "white", "beige", "olive", "teal", "navy", "magenta", "violet", "indigo", "lime", "aqua",
               "turquoise", "tan", "cyan", "maroon", "mauve", "crimson", "scarlet", "lavender", "lilac", "coral",
               "peach", "cream", "ivory", "gold", "silver", "bronze", "khaki", "fuchsia", "amber", "rose", "plum",
               "mint", "sage", "rust", "sand"}
FORBIDDEN = set("""skin flesh nude tan blush ivory ebony porcelain fair bone cheek lip lips hair blood heart eye eyes
tooth teeth nail finger hand tongue vein bruise breast comb foot face head belly bile scab rash vomit mucus cola coke
pepsi tiffany crayola sharpie lego kleenex popsicle creamsicle tabasco nutella oreo starbucks pantone persian indian
prussian sienna titian angel heaven saint monk pope cathedral church temple altar holy sacred easter christmas cardinal
royal liberty republic rebel revolution pill aspirin bandage surgical hospital iodine calamine antiseptic tobacco
nicotine best perfect ultimate supreme greatest brightest darkest finest purest ultra super mega most utmost""".split())

def rules():
    # Reading the stored run must not depend on today's Swift table still having its v1 form.
    vocab = None if os.path.exists(os.path.join(RUN, "rules.json")) else current_vocabulary()
    return loop.rules(RUN, "color-names", vocabulary=vocab)


def targets():
    return {("nina" if rules()["recorded"] else "robber-girl") if gid == "nina" else gid: value
            for gid, value in TARGETS.items()}


def vocabulary(): return rules()["vocabulary"]


def current_vocabulary():
    src = Path(VOCAB).read_text().split('static let table = """', 1)[1].split('"""', 1)[0]
    return [{"index": i, "hex": l[:6], "name": l[7:]} for i, l in enumerate(x for x in src.splitlines() if x.strip())]

def oklab(hexs):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(int(hexs[i:i + 2], 16)) for i in (0, 2, 4))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)

def dist(p, q): return math.dist(p, q)

def describe(hexs):
    L, a, b = oklab(hexs)
    C, h = math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360
    light = ["very dark", "dark", "medium", "light", "very light"][sum(L > t for t in (0.3, 0.5, 0.7, 0.86))]
    if C < 0.025:
        return f"{light}, nearly neutral"
    sat = "grayish" if C < 0.06 else "muted" if C < 0.10 else "moderate" if C < 0.15 else "vivid"
    hues = [(15, "pinkish red"), (40, "red"), (70, "orange"), (100, "yellow-orange"), (115, "yellow"),
            (135, "yellow-green"), (165, "green"), (200, "teal"), (235, "cyan-blue"), (275, "blue"),
            (305, "violet"), (335, "purple"), (360, "pink")]
    hue = next(n for t, n in hues if h < t)
    return f"{light}, {sat} {hue} (roughly)"

def guardians():
    return loop.seats(rules())

def build_slots(vocab, own_targets):
    """Pure slot construction shared with new kit runs; no run files are written here."""
    vocab = [dict(v) for v in vocab]
    for v in vocab: v["lab"] = oklab(v["hex"])
    taken, slots = set(), []
    for gid, pairs in own_targets.items():
        for hexs, idea in pairs:
            t = oklab(hexs)
            best = min((v for v in vocab if v["index"] not in taken), key=lambda v: dist(v["lab"], t))
            taken.add(best["index"])
            near = sorted((v for v in vocab if v["index"] != best["index"]), key=lambda v: dist(v["lab"], best["lab"]))[:5]
            slots.append({"slot": len(slots) + 1, "owner": gid, "idea": idea, "index": best["index"], "hex": best["hex"],
                          "incumbent": best["name"], "describe": describe(best["hex"]),
                          "neighbors": [n["name"] for n in near]})
    owners = list(own_targets)
    half = {gid: ("A" if i < len(owners) // 2 else "B") for i, gid in enumerate(owners)}
    for s in slots: s["half"] = half[s["owner"]]
    return slots

def setup():
    slots = build_slots(vocabulary(), targets())
    save(os.path.join(RUN, "slots.json"), slots)
    for s in slots:
        print(f'{s["slot"]:2} {s["half"]} {s["owner"]:22} #{s["hex"]} {s["incumbent"]:16} ({s["idea"]}; {s["describe"]})')

BRIEF = """Medea is an iPhone and iPad app that turns a photo into a paint-by-numbers painting. Each paint in a painting gets a short nickname from a vocabulary of 640 names, each tied to one color, its anchor. The names show under the palette ("12 · Harbor Fog"), in VoiceOver ("12, Harbor Fog, dark grayish blue") and on printed keys, so a painter reads them many times while painting. The design panel you belong to is improving some of these names. New names only ever reach new paintings."""

RULES = """The rules every name must follow (code rejects any that break them):
- One or two words, Title Case, ASCII letters, spaces and at most one hyphen; at most 16 characters; no digits.
- Concrete and evocative: things, places, weather, food, materials, times of day.
- Never brand names, people's names (no artists, poets, saints or characters), body parts, skin-tone words, anything crude, religious, political or medical; no superlatives.
- No color words at all (red, blue, green, gold, rose, sage, mint, plum and the like).
- The color has to look like its name to a careful person.
- Different from the names of the neighboring colors listed with it."""

def color_block(s):
    return (f'Color {s["slot"]}: #{s["hex"]}, {s["describe"]}. Its name today: "{s["incumbent"]}". '
            f'Neighboring colors are called: {", ".join(s["neighbors"])}.')

def in_context(name, slot):
    return [f"{slot['slot']} · {name}", f"VoiceOver: {slot['slot']}, {name}, {slot['describe']}",
            f"Printed key: {slot['slot']} · {name}"]

def prompts():
    slots, G = load(os.path.join(RUN, "slots.json")), guardians()
    os.makedirs(os.path.join(RUN, "prompts"), exist_ok=True)
    for gid in targets():
        g, mine = G[gid], [s for s in slots if s["owner"] == gid]
        text = f"""You are {g['name']}, one of the guardians on a design panel. Stay in character.

{BRIEF}

Your charter:
{g['charter_text']}

You were given these two colors because they are near your own idea:
{chr(10).join(color_block(s) for s in mine)}

{RULES}

{loop.THREAD}

{loop.history(RUN, gid, G)}

Propose three names for each of your two colors. Two of the three should be names anyone would find beautiful. One may be personal: a name only you would think of, recognisably yours, still within the rules. Look at the hex and the description carefully: the name must fit the color.

Reply with only this JSON, nothing else (no code fence):
{{"names": {{"{mine[0]['slot']}": [{{"name": "...", "why": "one short sentence, in your voice"}}, ...], "{mine[1]['slot']}": [...]}}}}"""
        Path(RUN, "prompts", f"propose-{gid}.txt").write_text(text)
    listing = "\n".join(color_block(s) for s in slots)
    writer = f"""You are a professional namer of paint colors, writing for a paint-by-numbers app.

{BRIEF}

{RULES}

{loop.THREAD}

Write one new name for each of these 36 colors: the most beautiful, fitting name you can, the kind a painter would love to read. Plain and lovely beats clever.

{listing}

Reply with only this JSON, nothing else (no code fence):
{{"names": {{"1": "Name", "2": "Name", ...}}}}"""
    Path(RUN, "prompts", "writer.txt").write_text(writer)
    print("prompts written")

def extract(role, name, agent_id):
    """Reads an agent's final reply (its SubagentHandback message) from its transcript."""
    if role not in ("proposals", "verdicts"):
        raise ValueError("role must be proposals or verdicts")
    path = agent_id if agent_id.endswith(".output") else os.path.join(TASKS, f"{agent_id}.output")
    data = transcripts.extract(path)
    save(os.path.join(RUN, role, f"{name}.json"), data)
    print(name, "ok" if "error" not in data else data["error"])

def craft(name, slot, vocab_names):
    fails = []
    words = name.split(" ")
    if not 1 <= len(words) <= 2: fails.append("one or two words")
    if len(name) > 16: fails.append("at most 16 characters")
    if not all(c.isascii() and (c.isalpha() or c in " -") for c in name): fails.append("ASCII letters only")
    if name.count("-") > 1: fails.append("at most one hyphen")
    if not all(w[:1].isupper() and all(c.islower() or c == "-" for c in w[1:]) for w in words if w): fails.append("Title Case")
    parts = [p for p in re.split(r"[ -]", name.lower()) if p]
    if any(p in COLOR_WORDS for p in parts): fails.append("no color words")
    if any(p in FORBIDDEN for p in parts): fails.append("a forbidden word")
    if name.lower() in vocab_names - {slot["incumbent"].lower()}: fails.append("another color's name")
    return fails

def collect():
    slots, vocab = load(os.path.join(RUN, "slots.json")), vocabulary()
    vocab_names = {v["name"].lower() for v in vocab}
    writer = load(os.path.join(RUN, "proposals", "writer.json"), {}).get("names", {})
    rng = random.Random("plants")
    plant_slots = {}
    for kind, warm, cool in PLANTS:
        s = rng.choice([s for s in slots if s["slot"] not in plant_slots])
        L, a, b = oklab(s["hex"])
        plant_slots[s["slot"]] = (kind, cool if b > 0 else warm)  # the wrong temperature on purpose
    rejected = []
    for s in slots:
        cands = [{"name": s["incumbent"], "source": "incumbent", "why": ""}]
        prop = load(os.path.join(RUN, "proposals", f'{s["owner"]}.json'), {}).get("names", {})
        for c in prop.get(str(s["slot"]), [])[:3]:
            cands.append({"name": " ".join(str(c.get("name", "")).split()), "source": s["owner"], "why": c.get("why", "")})
        if str(s["slot"]) in writer:
            cands.append({"name": " ".join(str(writer[str(s["slot"])]).split()), "source": "writer", "why": ""})
        if s["slot"] in plant_slots:
            kind, nm = plant_slots[s["slot"]]
            cands.append({"name": nm, "source": f"plant: {kind}", "why": ""})
        kept, seen = [], set()
        for c in cands:
            fails = [] if c["source"] == "incumbent" else craft(c["name"], s, vocab_names)
            if c["name"].lower() in seen: fails.append("duplicate in this slot")
            if fails:
                rejected.append({"slot": s["slot"], **c, "fails": fails}); continue
            seen.add(c["name"].lower()); kept.append(c)
        s["candidates"] = kept
    save(os.path.join(RUN, "slots.json"), slots)
    save(os.path.join(RUN, "rejected.json"), rejected)
    print(f"{sum(len(s['candidates']) for s in slots)} candidates in {len(slots)} slots; {len(rejected)} rejected")
    for r in rejected: print("  rejected", r["slot"], r["name"], r["source"], r["fails"])

def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p): return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def sheets():
    """One sheet of numbered swatches per half, for the jurors to look at."""
    slots = load(os.path.join(RUN, "slots.json"))
    for half in "AB":
        mine = [s for s in slots if s["half"] == half]
        cols, w, h, pad = 6, 220, 170, 16
        rows = math.ceil(len(mine) / cols)
        img = Image.new("RGB", (cols * (w + pad) + pad, rows * (h + pad + 30) + pad), "#F4F1EA")
        d = ImageDraw.Draw(img)
        for i, s in enumerate(mine):
            x, y = pad + (i % cols) * (w + pad), pad + (i // cols) * (h + pad + 30)
            d.rectangle([x, y, x + w, y + h], fill="#" + s["hex"], outline="#9A948A")
            d.text((x, y + h + 6), f'Color {s["slot"]}', fill="#2A2622", font=font(20))
        os.makedirs(OUT, exist_ok=True)
        img.save(os.path.join(OUT, f"sheet-{half}.png"))
    print("sheets written")

def judges():
    """Each half of the panel judges the other half's colors: Originality plus five drafted jurors."""
    slots, G = load(os.path.join(RUN, "slots.json")), guardians()
    Path(RUN, "prompts").mkdir(parents=True, exist_ok=True)
    owners = list(targets())
    for half in "AB":
        other = [gid for gid in owners if slots[[s["owner"] for s in slots].index(gid)]["half"] != half]
        prior = load(os.path.join(RUN, "ledger.json"), {"rounds": []})
        prior = {"rounds": [r for r in prior["rounds"] if r["round"] < 1]}
        drawn = loop.draw([G[g] for g in ["originality"] + other], prior, f"jury-{half}", proposers=0,
                          calibration=rules()["calibration"])
        jury = drawn["jury"]
        mine = [s for s in slots if s["half"] == half]
        save(os.path.join(RUN, "juries", f"{half}.json"), jury)
        for gid in jury:
            g = G[gid]
            ballot, blocks = {}, []
            for s in mine:
                letters = loop.ballot([c["name"] for c in s["candidates"]], f"ballot-{half}-{gid}-{s['slot']}")
                ballot[str(s["slot"])] = letters
                blocks.append(f'Color {s["slot"]} (#{s["hex"]}, {s["describe"]}): ' +
                              "; ".join(f"{L} {n} — " + "; ".join(in_context(n, s)) for L, n in letters.items()))
            save(os.path.join(RUN, "ballots", f"{half}-{gid}.json"), ballot)
            if g.get("vetoOnly"):
                task = """For each color, veto any name that is a brand, a person's name, a famous franchise's, or that caricatures a people or tradition. Most names should pass.
Reply with only this JSON, nothing else (no code fence): {"slots": {"<color number>": {"veto": {"<letter>": "the reason"}}}} (list only the colors where you veto something)."""
            else:
                task = """For each color, rank every name from best to worst. Judge fit to the swatch first (does the color look like its name?), then beauty, then your own idea. Then, for your first choice only, say in at most ten words why.
You may veto a name only if it breaks your charter: quote the exact words of your charter that it breaks. A veto without an exact quote is ignored.
Reply with only this JSON, nothing else (no code fence):
{"slots": {"<color number>": {"ranking": ["C", "A", "..."], "why": "...", "veto": {"<letter>": "exact words from your charter"}}}}
(every color; each ranking lists every letter of that color exactly once; leave veto out when you have none)"""
            text = f"""You are {g['name']}, sitting on a jury of a design panel. Stay in character.

{BRIEF}

Your charter:
{g['charter_text']}

{loop.THREAD}

{loop.glossary_prompt(rules()) if g.get("vetoOnly") else ""}

First look at the swatches with the Read tool: {os.path.join(OUT, f'sheet-{half}.png')} . The jury is choosing a name for each of these colors. The candidate names, in an order shuffled for you:

{chr(10).join(blocks)}

{task}

{loop.veto_instruction(rules())}"""
            Path(RUN, "prompts", f"judge-{half}-{gid}.txt").write_text(text)
        print(half, jury)

def decide():
    slots, G = load(os.path.join(RUN, "slots.json")), guardians()
    results = []
    for half in "AB":
        jury = load(os.path.join(RUN, "juries", f"{half}.json"))
        for s in [s for s in slots if s["half"] == half]:
            names = [c["name"] for c in s["candidates"]]
            ballots, verdicts = {}, {}
            for gid in jury:
                ballots[gid] = load(os.path.join(RUN, "ballots", f"{half}-{gid}.json"))[str(s["slot"])]
                v = load(os.path.join(RUN, "verdicts", f"{half}-{gid}.json"), {}).get("slots", {}).get(str(s["slot"]), {})
                verdicts[gid] = {"candidates": {letter: {"veto": quote} for letter, quote in (v.get("veto") or {}).items()},
                                 "ranking": v.get("ranking", []), "note": v.get("why")}
            tally = loop.score(names, jury, ballots, verdicts, rules(),
                               ledger={"rounds": [r for r in load(os.path.join(RUN, "ledger.json"), {"rounds": []})["rounds"] if r["round"] < 1]})
            score, firsts, vetoes, whys = (tally[k] for k in ("score", "firsts", "vetoes", "notes"))
            ignored = tally["ignored"]
            src = {c["name"]: c["source"] for c in s["candidates"]}
            pref = {"writer": 1, "incumbent": 3}
            order = sorted(names, key=lambda n: (bool(vetoes[n]), -score[n], -firsts[n], pref.get(src[n], 0) if not src[n].startswith("plant") else 4, n))
            results.append({"slot": s["slot"], "owner": s["owner"], "hex": s["hex"], "incumbent": s["incumbent"],
                            "winner": order[0], "winner_source": src[order[0]], "guaranteed": False,
                            "standings": [{"name": n, "source": src[n], "score": score[n], "firsts": firsts[n],
                                           "vetoes": vetoes[n], "whys": whys[n]} for n in order],
                            "ignored_vetoes": ignored})
    if not rules()["recorded"]:
        for r in results:
            r.update(loop.favorites(r["standings"]))
    base = {v["index"]: v["name"] for v in vocabulary()}
    caps = loop.select(results, base, {s["slot"]: s["index"] for s in slots}, NameCaps(rules()),
                       owners=targets(), guarantee=rules()["guarantee"], recorded=rules()["recorded"])
    save(os.path.join(RUN, "caps.json"), caps)
    if caps: print("style-guide caps still broken:", caps)
    save(os.path.join(RUN, "decision.json"), results)
    lines = {}
    represented = []
    for r in results:
        source = r["winner_source"]
        if source in G and source not in represented:
            represented.append(source)
        for note in next(st["whys"] for st in r["standings"] if st["name"] == r["winner"]):
            display, _, line = note.partition(": ")
            gid = next((g for g in load(os.path.join(RUN, "juries", "A.json")) + load(os.path.join(RUN, "juries", "B.json")) if G[g]["name"] == display), None)
            if gid:
                lines.setdefault(gid, []).append(f"Color {r['slot']}: {line}")
                if gid not in represented:
                    represented.append(gid)
    loop.record_round(RUN, {"round": 1, "winners": {str(r["slot"]): r["winner"] for r in results},
                            "represented": represented, "lines": lines})
    wins = {}
    for r in results: wins[r["winner_source"]] = wins.get(r["winner_source"], 0) + 1
    for r in results:
        print(f'{r["slot"]:2} #{r["hex"]} {r["incumbent"]:16} -> {r["winner"]:16} [{r["winner_source"]}{" guaranteed" if r["guaranteed"] else ""}]')
        print("    favorites:", loop.favorites(r["standings"]))
    print("wins:", wins)

class NameCaps:
    """The style guide's whole-vocabulary limits, plus the shared bar for new runs."""
    def __init__(self, record):
        self.record = record

    def __call__(self, table):
        lead, trail = {}, {}
        for name in table.values():
            words = name.split(" ")
            if len(words) == 2:
                lead[words[0]] = lead.get(words[0], 0) + 1
                trail[words[1]] = trail.get(words[1], 0) + 1
        caps = [("lead", w) for w, n in lead.items() if n > 4] + [("trail", w) for w, n in trail.items() if n > 6]
        if self.record["sharedBar"]:
            caps += loop.georgian_caps(table, self.record["glossary"])
        return caps

    def contributes(self, name, pos, word):
        if pos in ("places", "words"):
            terms = self.record["glossary"][pos]
            return any(re.search(r"(?<![a-z])" + re.escape(t.lower()) + r"(?![a-z])", name.lower()) for t in terms)
        return (name.split(" ")[0] if pos == "lead" else name.split(" ")[-1]) == word


def main():
    cmd, *rest = sys.argv[1:]
    {"setup": setup, "prompts": prompts, "extract": extract, "collect": collect, "sheets": sheets,
     "judges": judges, "decide": decide}[cmd](*rest)
