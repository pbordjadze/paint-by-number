"""Builds the Lamp's collection page from factory/GUARDIANS.md and factory/panel.json.
Available factory/pets/<id>/spritesheet.webp atlases are embedded in the page.

  collection.py <repo> <out.html> <template.html>   (write the page outside the repo)
"""
import base64, html, json, re, sys
from pathlib import Path
from PIL import Image

repo, out = sys.argv[1], sys.argv[2]
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
}
COLORS = ["#C8963E", "#5E7F4A", "#8E3B2E", "#5D7186", "#B86A6A", "#B59A3A", "#3F6E68", "#9A7BA6"]

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
    if not g["active"]: chips.append('<span class="chip chip-off">Maybe · not seated yet</span>')
    rows = "".join(
        f'<div class="row"><dt>{k.capitalize()}</dt><dd>{inline(cap(f[k]))}</dd></div>'
        for k in ORDER[1:] if k in f)
    recog = next((v for k, v in f.items() if k.startswith("recognizes")), None)
    thread = f.get("Georgian thread")
    pid = f"pet-{g['id']}"
    atlas = Path(repo) / "factory" / "pets" / g["id"] / "spritesheet.webp"
    if atlas.is_file():
        with Image.open(atlas) as image:
            width, height = image.size
        if (width, height) not in ((1536, 1872), (1536, 2288)):
            sys.exit(f"collection: unsupported atlas size {width} × {height}: {atlas}; "
                     "expected 1536 × 1872 (v1) or 1536 × 2288 (v2)")
        encoded = base64.b64encode(atlas.read_bytes()).decode("ascii")
        pet = (f'<div class="pet pet-sprite" aria-hidden="true" '
               f'style="background-image: url(data:image/webp;base64,{encoded}); '
               f'background-size: {width // 4}px {height // 4}px"></div>')
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
  {f'<p class="thread"><span class="label">Georgian thread</span> {inline(cap(thread))}</p>' if thread else ''}
  <div class="prompt">
    <span class="label">Pet prompt</span>
    <p id="{pid}">{inline(PETS[g['id']])}</p>
    <button type="button" class="copy" data-target="{pid}">Copy prompt</button>
  </div>
</article>""")

seated = sum(1 for g in panel["guardians"] if g["active"] and not g.get("vetoOnly"))
page = open(f"{sys.argv[3]}").read()
page = page.replace("{{CARDS}}", "".join(cards)).replace("{{SEATED}}", str(seated))
open(out, "w").write(page)
print(len(cards), "cards,", seated, "seated guardians")
