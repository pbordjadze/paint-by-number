"""Glance test: each candidate alone on a day and a night home screen, among placeholder shapes,
with its home-screen name and no letter, for a reviewer who never sees the others.

    glance.py candidates.json OUTDIR   -> OUTDIR/<key>/screen.png, OUTDIR/<key>/prompt.md
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from views import home

def main():
    cands, out = json.load(open(sys.argv[1])), sys.argv[2]
    for c in cands:
        d = os.path.join(out, c["key"]); os.makedirs(d, exist_ok=True)
        day, night = home({"A": c}, ["A"], False, tags=False), home({"A": c}, ["A"], True, tags=False)
        two = Image.new("RGB", (day.width * 2 + 40, day.height), (0, 0, 0)); two.paste(day, (0, 0)); two.paste(night, (day.width + 40, 0))
        two.resize((two.width // 2, two.height // 2), Image.LANCZOS).save(os.path.join(d, "screen.png"))
        open(os.path.join(d, "prompt.md"), "w").write(f"""Look at this image with the Read tool: {os.path.join(d, 'screen.png')}
It is one iPhone home screen shown twice, by day (left) and by night (right). Every icon on it is a
plain placeholder shape except one: a real app's icon, with the app's name under it. You have never
seen this app. Judge from its icon and name alone, at a glance, as someone flicking past it would.

1. In one sentence, what do you think the app does?
2. Which App Store category would you expect to find it in?
3. Your second guess: what else could it be?

Read nothing else and don't search the web. Write this JSON to {os.path.join(d, 'glance.json')} and nothing else anywhere:
{{"does": "...", "category": "...", "second_guess": "..."}}
Your final message is the single word: done
""")
    print("built", len(cands))

if __name__ == "__main__":
    main()
