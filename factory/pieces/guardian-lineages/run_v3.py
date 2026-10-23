"""Builds a guardian's version-3 prompt from RULE.md's card and steps, and runs Codex once.

usage: python3 run_v3.py <lineages-v3.json> <guardian-id> <out dir> [steps, default 1 2 3 | wild]
       wild: one wildcard plate only; PLATES=<dir of plates> gives it the guardian's three jumps to answer.
       NOWILD=1 leaves the optional wildcard out (for a redo).

No image is attached: Codex sees only the card and the steps (RULE.md, How it runs). It may add
one wildcard image that breaks the rule, with a line in wild.txt (RULE.md, Room to break it).
"""
import json, os, subprocess, sys, time

PLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'prompts', '_plate.md')


def prompt(g, steps, out, wild=True):
    if steps == ['wild']:
        return wild_prompt(g, out)
    c = g['card']
    lines = [f"Use the built-in image_gen tool (imagegen skill, built-in mode). Make one image_gen call "
             f"for each of these steps: {' '.join(map(str, steps))} (plus the optional wildcard at the end), no retries, then stop. Do not write code and do not "
             f"post-process the images beyond copying them. Copy each result to {out}/step-<N>.png (overwrite). No image is attached.",
             "",
             "THE RULE: carry the guardian's idea back, not its picture. Each step is how THAT tradition, with its own tools, "
             "conventions and level of knowledge, would make this guardian's subject; never a copy of a modern drawing. "
             "What to aim for (a way of looking, not a law): (1) Native: a curator of that period would see an ordinary, well-made object of their "
             "own tradition; no tricks: no shape hidden in a landscape, no outline filled with a pattern, no double exposure, nothing "
             "out of its time. (2) Lineage: with its caption, someone who knows the guardian recognises the same thing, through its "
             "subject, not a traced outline. (3) Signature: nothing in the manner of a named artist from a later time.",
             "", open(PLATE, encoding='utf-8').read().strip(), "",
             f"Guardian: {g['name']}.",
             f"Essence (always keep): {c['essence']}."]
    if c['rhymes']:
        lines.append("May echo, only where this tradition has its own native form for it, free in shape, scale and pose: " + "; ".join(c['rhymes']) + ".")
    lines.append("Leave behind (by default): " + "; ".join(c['leave']) + ".")
    lines.append("")
    for i in steps:
        s = g['steps'][i]
        lines.append(f"Step {i}, {s['title']} ({s['date']}). Medium: {s['medium']}. What this tradition natively makes: {s['native']}")
    if wild:
        lines += ["",
              "You are free here. The rule above is a default, not a law. If you see a better idea for any step, even one that "
              f"breaks the rule, you may make ONE extra image_gen call for it (so at most {len(steps) + 1} calls in all) and copy it to "
              f"{out}/step-<N>-wild.png, where N is the step it answers. Then write one line to {out}/wild.txt: which rule it breaks "
              "and why it is better. If you have a suggestion about the rule or the guardian's card, add it to the same file. "
              "This is optional; skip it if nothing better comes to you."]
    lines += ["", 'Finish with one line: "done".']
    return "\n".join(lines)


def card_lines(g):
    c = g['card']
    lines = [f"Guardian: {g['name']}.", f"Essence: {c['essence']}."]
    if c['rhymes']:
        lines.append("Rhymes that may echo: " + "; ".join(c['rhymes']) + ".")
    lines.append("Left behind by default: " + "; ".join(c['leave']) + ".")
    return lines


def wild_prompt(g, out):
    """One wildcard plate that breaks the rule on purpose (RULE.md, Room to break it)."""
    steps = "\n".join(f"Step {i}, {s['title']} ({s['date']}): {s['medium']}. {s.get('native', '')}" for i, s in enumerate(g['steps']) if i)
    trail = " <- ".join(s['short'] for s in g['steps'])
    return "\n".join([
        "Use the built-in image_gen tool (imagegen skill, built-in mode). Make EXACTLY ONE image_gen call, no retries, then stop. "
        "Do not write code and do not post-process the image beyond copying it.",
        "",
        f"This guardian's lineage ({trail}) is already drawn: the attached images are steps 1, 2 and 3 in order, each "
        "made by the rule below. Your job is the WILDCARD: one plate that breaks that rule on purpose because you think "
        "breaking it gives something better, truer or more surprising for this guardian. Any rule may go (the medium, the era, "
        "the step, the essence, the one-object framing, the idea of a lineage itself), but keep the catalogue plate "
        "presentation so it sits with the others, and keep its craft real.",
        "",
        "THE RULE you are free to break: carry the guardian's idea back, not its picture; each step is how that tradition, with "
        "its own tools, conventions and knowledge, would make the guardian's subject; no shapes hidden in landscapes, no "
        "double exposures, nothing in a later artist's manner.",
        "",
        *card_lines(g), "", steps, "",
        open(PLATE, encoding='utf-8').read().strip(), "",
        f"Copy the image to {out}/step-wild.png. Then write {out}/wild.txt with three short lines: "
        "TITLE: a museum-label title; MEDIUM: its real medium and a date; WHY: which rule it breaks and why that is better. "
        "If you have a suggestion about the rule or this guardian's card, add a fourth line SUGGESTION:.",
        "", 'Finish with one line: "done".'])


def main(data_path, gid, out, steps):
    g = next(x for x in json.load(open(data_path, encoding='utf-8'))['guardians'] if x['id'] == gid)
    os.makedirs(out, exist_ok=True)
    text = prompt(g, steps, out, wild=not os.environ.get('NOWILD'))
    images = []
    if steps == ['wild']:
        for i in (1, 2, 3):
            src = os.path.join(os.environ['PLATES'], f"{gid}-{i}.webp")
            dst = os.path.join(out, f"plate-{i}.png")
            subprocess.run(['python3', '-c', f"from PIL import Image; Image.open('{src}').convert('RGB').save('{dst}')"], check=True)
            images += ['--image', dst]
    open(os.path.join(out, 'prompt.txt'), 'w', encoding='utf-8').write(text)
    t = time.time()
    with open(os.path.join(out, 'events.jsonl'), 'w') as ev, open(os.path.join(out, 'stderr.txt'), 'w') as er:
        r = subprocess.run([os.path.expanduser('~/.local/bin/codex'), 'exec', '--json', '--ephemeral', '-s', 'workspace-write',
                            '--skip-git-repo-check', '--cd', out, '-m', 'gpt-6.1-sol', '-c', 'model_reasoning_effort="low"',
                            '-c', 'approval_policy="never"', *images, '-'], input=text, text=True, stdout=ev, stderr=er, cwd=out)
    print(f"{gid}: exit {r.returncode}, {time.time() - t:.0f} s, images: {sorted(f for f in os.listdir(out) if f.startswith('step-'))}")


if __name__ == '__main__':
    rest = sys.argv[4:]
    main(sys.argv[1], sys.argv[2], sys.argv[3], ['wild'] if rest == ['wild'] else [int(x) for x in rest] or [1, 2, 3])
