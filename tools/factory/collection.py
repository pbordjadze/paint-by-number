"""Builds the Lamp's collection page from factory/GUARDIANS.md and factory/panel.json.
Available pet atlases are embedded in the page, including Pip and Colophon.

  collection.py <repo> <out.html> <template.html> [--pets <dir>]
  Without --pets, sheets come from factory/pets/<id>/spritesheet.webp.
  Write the page outside the repo.
"""
import argparse, base64, html, json, re, sys
from pathlib import Path
from output_paths import outside_repo

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("template", type=Path)
    parser.add_argument("--pets", type=Path, help="read <dir>/<id>/spritesheet.webp")
    args = parser.parse_args()
    from PIL import Image
    try:
        args.out = outside_repo(args.out, args.repo)
    except ValueError as error:
        parser.error(str(error))
    repo, out = args.repo, args.out
    pets_dir = args.pets if args.pets is not None else repo / "factory" / "pets"
    md = open(f"{repo}/factory/GUARDIANS.md").read()
    panel = json.load(open(f"{repo}/factory/panel.json"))

    PETS = {
        "originality": "A small magnifying glass with one raised eyebrow, checking that everything is truly our own.",
        "medea": "A small golden ram whose soft fleece glints like old Colchian gold, carrying a sprig of fresh herbs. Kind eyes; when it's happy, the dry twig on its back sprouts green leaves.",
        "baba-yaga": "A tiny wooden hut on two chicken legs, with a roof patterned like a kerchief and a little broom by the door. It hops about curiously and sweeps its own footprints away.",
        "hedge-witch": "A mossy little mushroom with a tarragon sprig for a hat feather and a basket of herbs. Cozy and sleepy; it smells like a kitchen garden.",
        "moon": "A small crescent moon carrying a warm lantern. It glows quietly while it waits and brightens when a task is done.",
        "snow-queen": "A small white ermine wearing a crown of frost crystals. Elegant and still; it leaves a faint glimmer of frost where it steps.",
        "robber-girl": "A spirited reindeer calf in a felt blanket stitched with bold mountain embroidery. Mischievous and loyal; it stamps a hoof when something needs you.",
        "storybook": "A little book that flaps its covers like wings, its pages full of ink drawings that change as it flies.",
        "dinotopia": "Paul's own Dino, made in the Codex app: a teal long-necked dinosaur with a cream belly and a sly, friendly grin.",
        "bartimaeus": "A little ink asterisk with six stubby arms and two dot feet, drawn in brown ink as if someone stamped it there by hand. When a reader taps a word, it tugs the word's sleeve, hops down beside the note looking pleased to have the last word, then waves the reader back up to where they left off.",
        "enchanted-workshop": "A paintbrush with tiny legs and a determined face, carrying a paint jar and doing small jobs all on its own.",
        "scholar": "A tiny inkpot wearing round spectacles, a quill tucked behind it like a pencil behind an ear. It nods thoughtfully and underlines things.",
        "painter": "A small wooden palette with a brush for a tail and dabs of warm paint for spots. It sits back quietly so the painting gets the attention.",
        "child-at-bedtime": "A sleepy lamb in a striped nightcap holding a tiny candle. When idle it curls up and hums a lullaby.",
        "glassblower": "A clear glass droplet with a soft inner glow, calm and smooth; light passes through it like a window.",
        "pirosmani": "A gentle giraffe in flat warm colors on a black ground, with big sincere eyes, as if painted by hand on oilcloth.",
        "emily-dickinson": "A small bee in a tiny white collar carrying a pressed flower. Quiet and precise; it writes one short line and flies off.",
        "open-source-enthusiast": "A little pomegranate that splits open to share its seeds with everyone nearby. Generous, cheerful, proud of who helped it grow.",
        "nutcracker": "A tiny wooden nutcracker soldier with a clockwork key in its back. Courteous and brave; it salutes when a task finishes.",
        "balanchine": "A small tuning fork that dances en pointe, ringing one clear note with each perfect turn.",
        "bulat-okudzhava": "A little blue trolleybus with warm lit windows, rolling slowly down a night street, a guitar resting on one seat.",
        "bible-school-teacher": "A small clay oil lamp with a kind glow and a curl of grapevine around its handle.",
        "sen-no-rikyu": "A small black tea bowl, shaped by hand and a little uneven, with one morning glory resting on its rim. It sits very still, and when something is finished it tips the flower toward you.",
        "lotte-reiniger": "A little bird cut from black paper, its wings joined with tiny wire hinges. When it flies you can see light through the lace of holes cut in its feathers.",
        "astrologer": "A small brass sundial with a dewy moth asleep on its pointer, one tiny star painted on the moth's wing. When idle its shadow slowly creeps round the dial, and when something is finished the moth wakes, flutters once, and the star glints.",
        "madeleine-lengle": "A round little mug of cocoa, its steam curling up into a tiny spiral of stars. When idle it sits warm and quiet, stars drifting slowly; when something is finished, the steam swirls into a small bright galaxy and settles.",
    }
    COLORS = ["#C8963E", "#5E7F4A", "#8E3B2E", "#5D7186", "#B86A6A", "#B59A3A", "#3F6E68", "#9A7BA6"]

    # create-pet 0.1.6, references/animation-rows.md (v2, rows 3 and 8).
    MAKERS = (
        ("pip", "Pip", "Codex's teapot. A plain white teapot, a little lopsided, with no face. Lift the lid and there is a blue dot underneath.",
         "Pip, Codex's teapot. Tap to lift the lid.", 3, (140, 140, 140, 280)),
        ("colophon", "Colophon", "Claude's moth. A small round moth with pale page wings. It circles the lamp once, at a safe distance, and lands beside the words like a bookmark.",
         "Colophon, Claude's moth. Tap to fold the wings flat.", 8, (150, 150, 150, 150, 150, 280)),
    )

    def atlas_style(pet_id):
        atlas = pets_dir / pet_id / "spritesheet.webp"
        if not atlas.is_file():
            return None
        with Image.open(atlas) as image:
            width, height = image.size
        if (width, height) not in ((1536, 1872), (1536, 2288)):
            sys.exit(f"collection: unsupported atlas size {width} × {height}: {atlas}; "
                     "expected 1536 × 1872 (v1) or 1536 × 2288 (v2)")
        encoded = base64.b64encode(atlas.read_bytes()).decode("ascii")
        return (f"background-image: url(data:image/webp;base64,{encoded}); "
                f"background-size: {width // 4}px {height // 4}px")

    def cap(text):
        return text[:1].upper() + text[1:]

    def inline(text):
        text = html.escape(text, quote=False)
        return re.sub(r"`([^`]+)`", r"<code>\1</code>", text)

    sections = {}
    body = md.split("## The panel", 1)[1]
    for chunk in re.split(r"^### ", body, flags=re.M)[1:]:
        lines = chunk.rstrip().splitlines()
        heading, rest = lines[0].strip(), lines[1:]
        intro, fields, current = [], {}, None
        for line in rest:
            m = re.match(r"- \*\*(.+?)\*\*: (.*)", line)
            if m:
                current = m.group(1); fields[current] = m.group(2)
            elif line.startswith("  ") and current:
                fields[current] += " " + line.strip()
            elif line.strip() and current is None:
                intro.append(line.strip())
        sections[heading] = (" ".join(intro), fields)

    sections["The jury › Originality"] = ("Sits on every jury. It can only veto and never votes on taste.", {
        "believes": "Nothing we make should look like someone else's.",
        "champions": "a look that is ours alone; portrayals that respect the people and traditions they draw on.",
        "guards against": "franchise look-alikes; harmful caricature.",
    })

    ORDER = ["believes", "champions", "guards against", "touchstones"]
    cards = []
    for i, g in enumerate(panel["guardians"]):
        intro, f = sections[g["charter"]]
        name = re.sub(r"\s*\(.*\)$", "", g["charter"].replace("The jury › ", ""))
        letter = re.sub(r"^The ", "", name)[0]
        chips = []
        if g.get("vetoOnly"): chips.append('<span class="chip">Veto only</span>')
        if g.get("former"): chips.append('<span class="chip chip-off">Former · seat passed on</span>')
        elif not g["active"]: chips.append('<span class="chip chip-off">Maybe · not seated yet</span>')
        rows = "".join(
            f'<div class="row"><dt>{k.capitalize()}</dt><dd>{inline(cap(f[k]))}</dd></div>'
            for k in ORDER[1:] if k in f)
        recog = next((v for k, v in f.items() if k.startswith("recognizes")), None)
        pid = f"pet-{g['id']}"
        style = atlas_style(g["id"])
        if style:
            pet = (f'<div class="pet pet-sprite" aria-hidden="true" '
                   f'style="{style}"></div>')
        else:
            pet = f'<div class="pet" aria-hidden="true">{letter}</div>'
        cards.append(f"""
    <article class="card" id="{g['id']}" style="--c: {COLORS[i % len(COLORS)]}">
      <header class="card-head">
        {pet}
        <div class="who">
          <h2>{inline(name)}</h2>
          {f'<p class="intro">{inline(intro)}</p>' if intro else ''}
          {''.join(chips)}
        </div>
      </header>
      <p class="believes">{inline(cap(f.get('believes', '')))}</p>
      <dl>{rows}</dl>
      {f'<p class="recog"><span class="label">Knows itself when</span> {inline(cap(recog))}</p>' if recog else ''}
      <div class="prompt">
        <span class="label">Drawing prompt</span>
        <p id="{pid}">{inline(PETS[g['id']])}</p>
        <button type="button" class="copy" data-target="{pid}">Copy prompt</button>
      </div>
    </article>""")

    makers = []
    for pet_id, name, description, label, row, holds in MAKERS:
        style = atlas_style(pet_id)
        words = (f'<span class="maker-name">{name}</span>'
                 f'<span class="maker-description">{inline(description)}</span>')
        if style:
            entry = (f'<button type="button" class="maker" '
                     f'aria-label="{html.escape(label, quote=True)}" '
                     f'data-row="{row}" data-holds="{json.dumps(holds)}">'
                     f'<span class="pet pet-sprite" aria-hidden="true" style="{style}"></span>'
                     f'<span class="who">{words}</span></button>')
        else:
            entry = f'<div class="who">{words}</div>'
        makers.append(f'<article class="card maker-card" id="{pet_id}">{entry}</article>')

    seated = sum(1 for g in panel["guardians"] if g["active"] and not g.get("vetoOnly"))
    page = args.template.read_text()
    page = page.replace("{{CARDS}}", "".join(cards)).replace("{{SEATED}}", str(seated))
    page = page.replace("{{MAKERS}}", "".join(makers))
    out.write_text(page)
    print(len(cards), "cards,", seated, "seated guardians,", len(makers), "makers")


if __name__ == "__main__":
    main()
