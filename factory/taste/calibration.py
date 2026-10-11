"""Paul's accepted/vetoed picks become juror and proposer-source agreement factors.

A love compares its candidate to all other candidates in its slot. A veto compares all
other candidates to the vetoed candidate. Notes alone are never inferred as preferences.
A source agrees when it supplies the preferred side; a juror agrees when its rank prefers
that side. Laplace smoothing yields factors 0.5..1.5: 0.5 + (agreements+1)/(pairs+2).
"""
from pathlib import Path
from . import loop


def picks(path):
    data = loop.load(path)
    if isinstance(data, dict) and 'picks' in data:
        data = data['picks']
    if isinstance(data, dict):
        data = list(data.values())
    if not isinstance(data, list):
        raise ValueError('checkpoint must be an array or a map of checkpoint records')
    for pick in data:
        if not isinstance(pick, dict) or not {'slot', 'name', 'veto', 'love', 'note'} <= set(pick):
            raise ValueError('invalid checkpoint record')
        if type(pick['veto']) is not bool or type(pick['love']) is not bool or not isinstance(pick['note'], str):
            raise ValueError('invalid checkpoint veto, love or note')
        if not isinstance(pick['name'], str) or not pick['name'] or type(pick['slot']) not in (str, int):
            raise ValueError('invalid checkpoint slot or name')
        if 'round' in pick and (type(pick['round']) is not int or pick['round'] < 1):
            raise ValueError('invalid checkpoint round')
        if pick['veto'] and pick['love']:
            raise ValueError('checkpoint cannot love and veto the same candidate')
    return data


def calculate(run, checkpoint, output):
    run = Path(run)
    record = loop.load(run / 'rules.json')
    jurors, sources = {}, {}
    def add(table, who, agrees):
        counts = table.setdefault(who, {'agreements': 0, 'pairs': 0})
        counts['pairs'] += 1
        counts['agreements'] += int(agrees)
    for pick in picks(checkpoint):
        n = pick.get('round', 1)
        folder = run / 'rounds' / f'{n:03}'
        if record.get('kitVersion') == 1:
            draw = loop.load(folder / 'draw.json')
            slate = loop.load(folder / 'slate.json')
            if draw is None or slate is None:
                raise ValueError('calibration needs round records')
        elif record['piece'] == 'color-names':
            slate = loop.load(run / 'slots.json')
            draw = None
        elif record['piece'] == 'panel-name':
            draw = loop.load(folder / 'draw.json')
            slate = [{'slot': '1', 'candidates': loop.load(folder / 'slate.json')['slate']}]
        else:
            raise ValueError('unknown calibration piece')
        slot = next((s for s in slate if str(s['slot']) == str(pick['slot'])), None)
        if slot is None or pick['name'] not in [c['name'] for c in slot['candidates']]:
            raise ValueError('checkpoint candidate is absent from the recorded slate')
        if not (pick['love'] or pick['veto']):
            continue
        if draw is None:
            draw = {'jury': loop.load(run / 'juries' / f"{slot['half']}.json")}
        by_name = {c['name']: c.get('origin', c['source']) for c in slot['candidates']}
        for other in by_name:
            if other == pick['name']:
                continue
            better, worse = (pick['name'], other) if pick['love'] else (other, pick['name'])
            if by_name[better] != by_name[worse]:
                add(sources, by_name[better], True)
                add(sources, by_name[worse], False)
            for gid in draw['jury']:
                if loop.seats(record)[gid].get('vetoOnly'):
                    continue
                if record.get('kitVersion') == 1:
                    ballot = loop.load(folder / 'ballots' / f'{gid}.json')[slot['slot']]
                    verdict = loop.load(folder / 'accepted' / f'juror-{gid}.json')['slots'][slot['slot']]
                elif record['piece'] == 'color-names':
                    ballot = loop.load(run / 'ballots' / f"{slot['half']}-{gid}.json")[str(slot['slot'])]
                    verdict = loop.load(run / 'verdicts' / f"{slot['half']}-{gid}.json")['slots'][str(slot['slot'])]
                else:
                    ballot = loop.load(folder / 'ballots' / f'{gid}.json')
                    verdict = loop.load(folder / 'verdicts' / f'{gid}.json')
                order = [ballot[letter] for letter in verdict['ranking']]
                add(jurors, gid, order.index(better) < order.index(worse))
    factor = lambda evidence: {gid: round(0.5 + (counts['agreements'] + 1) / (counts['pairs'] + 2), 6)
                               for gid, counts in sorted(evidence.items())}
    result = {'jurors': factor(jurors), 'sources': factor(sources),
              'evidence': {'jurors': jurors, 'sources': sources}}
    loop.save(output, result)
    return result
