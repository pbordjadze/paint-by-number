"""Build the 24 reviewers of the 2x2 (plain/charter x full pack/own view): views and prompt per reviewer.

    make_prompts.py candidates.json EXPDIR
"""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SEATS = {
    "astrologer": ("The Astrologer", "the piece at two hours, its light capture beside its dark one, and nothing else", "can you tell the hour, and is the sky only hinted at?"),
    "rikyu": ("Rikyū", "the piece with its words blurred and its color taken out, so only shapes, counts and space remain", "what could go?"),
    "child": ("The Child at Bedtime", "the dark capture at phone size, dimmed to night brightness, for one look", "is it warm and safe, and would I ask to see it again?"),
    "hedge": ("The Hedge Witch", "the piece's materials at full size: 100% crops of its textures, edges, glyphs and icons", "was it grown by hand, or made in a factory?"),
    "madeleine": ("Madeleine", "the piece at the largest accessibility text size, with the words VoiceOver reads aloud", "is everyone welcome, and is nobody told off?"),
    "originality": ("Originality", "the piece beside its nearest references: the same screen in the apps it competes with, and any famous work it might echo", "is it ours?"),
}
VIEWS = {
    "astrologer": "the candidates' icons on an iPhone home screen at two hours: a light (day) screen on the left and a dark (night) screen on the right, among other apps' icons. Each candidate's letter is in a yellow tag above its icon; under the icon is its home-screen name as iOS shows it (a name too wide for the space is cut short with an ellipsis, as on a real phone)",
    "rikyu": "each candidate's icon reduced to two tones, light and dark only, at full size, with its name in plain type",
    "child": "the candidates' icons on a dark home screen at phone size, dimmed to night brightness, each with its letter in a tag above it and its home-screen name under it. Look once, as you would at bedtime",
    "hedge": "two full-size crops of each candidate's icon: its center, and its most detailed area",
    "madeleine": "each candidate's icon in iOS 26's tinted (one-color) appearance, approximated, at three sizes, and each name said in a plain sentence in large type",
    "originality": "the candidates' icons in a row above real App Store competitors (searches for photo to paint by number, paint by number, color by number, coloring books, sleep sounds and meditation), and their names beside rival apps' names",
}
ARMS = {"B": (False, False), "M": (True, False), "V": (False, True), "E": (True, True)}  # (charter, own view only)

def balanced_orders(n_keys=4):
    """The 24 orders of four candidates, one per reviewer: each candidate in each letter six times
    overall, and once or twice per arm. The orders fall into six Latin squares (relabelings by the
    Klein four-group); arms take one square each and half of one of the last two."""
    import itertools
    v4 = [(0, 1, 2, 3), (1, 0, 3, 2), (2, 3, 0, 1), (3, 2, 1, 0)]
    left, squares = set(itertools.permutations(range(n_keys))), []
    while left:
        p = min(left); sq = [tuple(v[i] for i in p) for v in v4]; squares.append(sq); left -= set(sq)
    halves = [squares[4][:2], squares[4][2:], squares[5][:2], squares[5][2:]]
    return {arm: squares[k] + halves[k] for k, arm in enumerate(ARMS)}

def main():
    cands, exp = sys.argv[1], sys.argv[2]
    keys = [c["key"] for c in json.load(open(cands))]
    orders = balanced_orders(len(keys))
    seed = 100
    for arm, (charter, own) in ARMS.items():
        for j, (seat, (name, sees, asks)) in enumerate(SEATS.items()):
            rid = f"{arm}-{seat}"; d = os.path.join(exp, "reviewers", rid); os.makedirs(d, exist_ok=True)
            seed += 1
            order = ",".join(keys[i] for i in orders[arm][j])
            subprocess.run([sys.executable, os.path.join(HERE, "views.py"), cands, d, str(seed), order], check=True)
            shown = [seat] if own else list(VIEWS)
            for v in VIEWS:
                if v not in shown: os.remove(os.path.join(d, f"{v}.png"))
            lines = []
            if charter:
                lines.append(f"You are {name}, one guardian of A Lamp Left Burning, the design panel of the app under review. Your charter, word for word:\n")
                lines.append(open(os.path.join(exp, "charters", f"{seat}.md")).read().strip() + "\n")
            else:
                lines.append("You are a reviewer of app designs.\n")
            lines.append("THE PIECE: an iOS and iPadOS app that turns any photo into a paint-by-numbers template you paint by tapping is choosing its name and its icon. There are four candidates, lettered A to D, each a name with an icon. A candidate's home-screen name, the label under its icon, can be shorter than its App Store name. One of them may be the app's identity today; don't guess which, and judge only what you see.\n")
            if own:
                lines.append(f"WHAT YOU SEE: you are given one view of the piece, and only this one: {sees}. Here that is {VIEWS[seat]}. The file:")
            else:
                lines.append("WHAT YOU SEE: the whole pack, six views of the candidates. The files:")
            for v in shown:
                lines.append(f"- {os.path.join(d, v + '.png')}: {VIEWS[v]}")
            if own:
                lines.append(f"\nThe question your view is for: {asks}")
            lines.append("""
THE TASK:
1. Look at the image(s) with the Read tool. Read nothing else and don't search the web.
2. Write at most 6 findings. Each finding is one or two sentences about one candidate, or about all of them, saying what you see and why it matters. Refer to candidates with their letter in square brackets, like [C]. Point at something anyone could check in what you were shown, for example: "[C]: the numeral disappears at the smallest size, so the icon stops saying numbers."
3. For each candidate, a verdict: keep, fix or kill. Then your favorite.""")
            if charter:
                lines.append("4. You may veto a candidate, but only by quoting your charter's guards-against line word for word." if seat != "originality" else
                             "4. You never vote on taste: give \"abstain\" for each verdict and for your favorite. You may veto a candidate that is not our own (a franchise look-alike, a famous name, a rival's look), saying why, and name what to avoid.")
            lines.append(f"""
OUTPUT: write this JSON to {os.path.join(d, 'reply.json')} and nothing else anywhere:
{{"findings": [{{"about": "A|B|C|D|all", "text": "..."}}], "verdicts": {{"A": "keep|fix|kill|abstain", "B": "...", "C": "...", "D": "..."}}, "favorite": "A|B|C|D|abstain", "veto": [{{"candidate": "A", "reason": "..."}}]}}
Your final message is the single word: done""")
            open(os.path.join(d, "prompt.md"), "w").write("\n".join(lines) + "\n")
    print("built", len(ARMS) * len(SEATS), "reviewers")

if __name__ == "__main__":
    main()
