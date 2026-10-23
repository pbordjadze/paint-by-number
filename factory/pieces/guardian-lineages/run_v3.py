"""Builds a guardian's version-3 prompt from RULE.md's card and steps, and runs Codex once.

usage: python3 run_v3.py <lineages-v3.json> <guardian-id> <out dir> [steps, default 1 2 3]

No image is attached: Codex sees only the card and the steps (RULE.md, How it runs). It may add
one wildcard image that breaks the rule, with a line in wild.txt (RULE.md, Room to break it).
"""
import json, os, subprocess, sys, time

PLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'prompts', '_plate.md')


def prompt(g, steps, out):
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
    lines += ["",
              "You are free here. The rule above is a default, not a law. If you see a better idea for any step, even one that "
              f"breaks the rule, you may make ONE extra image_gen call for it (so at most {len(steps) + 1} calls in all) and copy it to "
              f"{out}/step-<N>-wild.png, where N is the step it answers. Then write one line to {out}/wild.txt: which rule it breaks "
              "and why it is better. If you have a suggestion about the rule or the guardian's card, add it to the same file. "
              "This is optional; skip it if nothing better comes to you.",
              "", 'Finish with one line: "done".']
    return "\n".join(lines)


def main(data_path, gid, out, steps):
    g = next(x for x in json.load(open(data_path, encoding='utf-8'))['guardians'] if x['id'] == gid)
    os.makedirs(out, exist_ok=True)
    text = prompt(g, steps, out)
    open(os.path.join(out, 'prompt.txt'), 'w', encoding='utf-8').write(text)
    t = time.time()
    with open(os.path.join(out, 'events.jsonl'), 'w') as ev, open(os.path.join(out, 'stderr.txt'), 'w') as er:
        r = subprocess.run([os.path.expanduser('~/.local/bin/codex'), 'exec', '--json', '--ephemeral', '-s', 'workspace-write',
                            '--skip-git-repo-check', '--cd', out, '-m', 'gpt-6.1-sol', '-c', 'model_reasoning_effort="low"',
                            '-c', 'approval_policy="never"', '-'], input=text, text=True, stdout=ev, stderr=er, cwd=out)
    print(f"{gid}: exit {r.returncode}, {time.time() - t:.0f} s, images: {sorted(f for f in os.listdir(out) if f.startswith('step-'))}")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3], [int(x) for x in sys.argv[4:]] or [1, 2, 3])
