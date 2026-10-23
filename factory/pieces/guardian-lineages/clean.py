"""Moves research hedges out of plate labels (medium/date) into the guardian's note."""
import json, re, sys
p = sys.argv[1]; d = json.load(open(p))
for g in d['guardians']:
    for s in g['steps']:
        for k in ('medium', 'date', 'title'):
            for m in re.findall(r'\s*\([^)]*(?:UNCONFIRMED|per typical|inferred|unchecked)[^)]*\)', s.get(k, '')):
                s[k] = s[k].replace(m, '')
                g['note'] = (g.get('note', '') + f" {s['short']}: {m.strip()[1:-1]}.").strip()
            print(g['id'], k, '|', s.get(k, ''))
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=1)
