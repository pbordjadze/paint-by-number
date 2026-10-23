"""Turns the research files into lineages-batch2.json (same format as lineages-v3.json)."""
import json, os, sys
out = sys.argv[1]
data = json.load(open(out)) if os.path.exists(out) else {'guardians': []}
have = {g['id'] for g in data['guardians']}
for path in sys.argv[2:]:
    for r in json.load(open(path)):
        if r['id'] in have:
            continue
        s0 = r['step0']
        steps = [{'short': r['name'], 'title': s0['title'], 'medium': r.get('_step0', s0['medium']), 'date': s0.get('date', '')}]
        for s in r['steps']:
            steps.append({k: s.get(k, '') for k in ('short', 'title', 'medium', 'date', 'kind', 'link', 'source', 'url', 'native')})
        data['guardians'].append({'id': r['id'], 'name': r['name'], 'approved': f"refs/{r['id']}-frame.png",
                                  'card': r['card'], 'steps': steps, 'note': r.get('note', ''), 'confidence': r.get('confidence', '')})
json.dump(data, open(out, 'w'), ensure_ascii=False, indent=1)
print([g['id'] for g in data['guardians']])
