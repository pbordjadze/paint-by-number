"""Pool the 24 replies for blind coding: letters undone to candidate numbers, arms and reviewers hidden.

    pool.py EXPDIR CANDIDATES_JSON   -> EXPDIR/pool.json (shuffled findings with ids), EXPDIR/key.json (id -> arm, seat)
"""
import json, os, random, re, sys
exp, cands = sys.argv[1], json.load(open(sys.argv[2]))
num = {c["key"]: i + 1 for i, c in enumerate(cands)}
items, key = [], {}
for rid in sorted(os.listdir(os.path.join(exp, "reviewers"))):
    d = os.path.join(exp, "reviewers", rid)
    try: reply = json.load(open(os.path.join(d, "reply.json")))
    except Exception as e: print("missing", rid, e); continue
    letters = json.load(open(os.path.join(d, "letters.json")))
    to_num = {L: f"#{num[k]}" for L, k in letters.items()}
    for f in reply.get("findings", [])[:6]:
        text = re.sub(r"\[([A-D])\]", lambda m: f"[{to_num[m.group(1)]}]", f.get("text", ""))
        about = f.get("about", "all"); about = to_num.get(about, "all") if about != "all" else "all"
        items.append({"text": text, "about": about}); key[len(items) - 1] = rid
order = list(range(len(items))); random.Random(2026).shuffle(order)
pool = [{"id": f"f{j + 1:03d}", "about": items[i]["about"], "text": items[i]["text"]} for j, i in enumerate(order)]
json.dump(pool, open(os.path.join(exp, "pool.json"), "w"), indent=1)
json.dump({f"f{j + 1:03d}": key[i] for j, i in enumerate(order)}, open(os.path.join(exp, "key.json"), "w"), indent=1)
print(len(pool), "findings pooled")
