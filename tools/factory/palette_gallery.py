#!/usr/bin/env python3
"""Build the Lamp's palette gallery, a static page in the Marginarium.

  python3 tools/factory/palette_gallery.py --out /root/factory-out/F12/gallery.html
  python3 tools/factory/palette_gallery.py --preview --out /root/factory-out/F12/preview.html

Defaults: factory/pieces/color-names/run/ and its checkpoint.json, with the adjacent
drops.json. A schedule is an array of {"date": "YYYY-MM-DD", "colors": [1, 2]}:
colors are slot IDs, each scheduled at most once. Drops open at midnight UTC on
their date. Unscheduled colors stay hidden; --preview includes every slot, even
without a schedule. --as-of YYYY-MM-DD pins the build date for reproducibility.
Claude drafts drops.json and Paul approves it; this tool never creates a schedule.
Future colors are omitted from the HTML entirely. Rebuild when a drop is due.
"""
import argparse
from datetime import date, datetime, timezone
import html
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from factory.taste import calibration, loop, pages

DEFAULT_RUN = ROOT / 'factory/pieces/color-names/run'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def iso_date(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
        raise ValueError('dates must use YYYY-MM-DD')
    return date.fromisoformat(value)


def released_slots(drops, slots, as_of):
    if not isinstance(drops, list):
        raise ValueError('drops.json must be an array of date/colors records')
    seen, released = set(), set()
    for drop in drops:
        if not isinstance(drop, dict) or set(drop) != {'date', 'colors'}:
            raise ValueError('each drop must contain date and colors')
        day = iso_date(drop['date'])
        if not isinstance(drop['colors'], list):
            raise ValueError('drop colors must be an array of slot IDs')
        for color in drop['colors']:
            if type(color) not in (int, str) or str(color) not in slots:
                raise ValueError(f'unknown drop color slot: {color}')
            sid = str(color)
            if sid in seen:
                raise ValueError(f'color slot {sid} is scheduled more than once')
            seen.add(sid)
            if day <= as_of:
                released.add(sid)
    return released


def indexed(records, label):
    result = {}
    for record in records:
        sid = str(record['slot'])
        if sid in result:
            raise ValueError(f'duplicate {label} slot: {sid}')
        result[sid] = record
    return result


def jury_notes(run, slot, names):
    """Verdict reasons concern the first-ranked name, not necessarily the winner."""
    notes = []
    for path in sorted((run / 'verdicts').glob(f"{slot['half']}-*.json")):
        verdict = read(path)['slots'].get(str(slot['slot']))
        if verdict is None:
            continue
        juror = path.stem[len(slot['half']) + 1:]
        ballot = read(run / 'ballots' / path.name)[str(slot['slot'])]
        if verdict.get('why'):
            ranking = verdict.get('ranking', [])
            preferred = ballot[ranking[0]] if ranking else None
            notes.append((names.get(juror, juror), preferred, verdict['why']))
    return notes


def render_card(run, slot, result, pick, names):
    esc = html.escape
    sid = str(slot['slot'])
    swatch = slot['hex'].lstrip('#')
    if not re.fullmatch(r'[0-9A-Fa-f]{6}', swatch):
        raise ValueError(f'invalid swatch for slot {sid}')
    candidates = {c['name']: c for c in slot['candidates']}
    original = result['winner']
    if pick and pick['name'] != original:
        raise ValueError(f'checkpoint name differs from decision for slot {sid}')
    selected = pick.get('replacement') if pick and pick['veto'] else None
    if pick and pick['veto'] and not selected:
        raise ValueError(f'vetoed slot {sid} needs a checkpoint replacement')
    selected = selected or {'name': original, 'source': result['winner_source']}
    name, source = selected['name'], selected['source']
    candidate = candidates.get(name)
    if candidate is None or candidate['source'] != source:
        raise ValueError(f'checkpoint/decision candidate absent from slot {sid}: {name}')
    # Some writer proposals are just names. Never invent an explanation for them.
    why = candidate.get('why', '')
    proposal = run / 'proposals' / f'{source}.json'
    if proposal.is_file():
        proposed = read(proposal)['names'].get(sid, [])
        if isinstance(proposed, list):
            why = next((p.get('why', '') for p in proposed if p['name'] == name), why)
    maker = names.get(source, {'writer': 'the outside writer', 'incumbent': 'the name the app already had'}.get(source, source))
    owner = names.get(slot['owner'], slot['owner'])
    standing = next(s for s in result['standings'] if s['name'] == name)
    loved = bool(pick and pick['love'] and not pick['veto'])
    status = 'Loved by Paul' if loved else 'Paul has not marked this name as loved'
    voices = []
    for juror, preferred, note in jury_notes(run, slot, names):
        context = f'Preferred {preferred}' if preferred else 'Jury note'
        voices.append(f'<li><p class="label">{esc(juror)} · {esc(context)}</p><p>{esc(note)}</p></li>')
    margins = voices[:2]
    for entry in result['standings']:
        if entry['name'] in {name, original}:
            for veto in entry.get('vetoes', []):
                margins.append(f'<li><p class="label">Jury veto · {esc(entry["name"])}</p><p>{esc(veto)}</p></li>')
    if pick and pick['veto']:
        margins.append(f'<li class="paul"><p class="label">Paul · veto</p>'
                       f'<p>Paul vetoed {esc(original)}. Replaced by {esc(name)}.</p>'
                       + (f'<p>{esc(pick["note"])}</p>' if pick['note'] else '') + '</li>')
        if selected.get('why'):
            margins.append(f'<li><p class="label">Replacement note</p><p>{esc(selected["why"])}</p></li>')
    elif pick and pick['note']:
        margins.append(f'<li class="paul"><p class="label">Paul</p><p>{esc(pick["note"])}</p></li>')
    if result.get('guaranteed'):
        margins.append(f'<li><p class="label">The Lamp</p><p>The jury chose {esc(original)} '
                       f'to give {esc(owner)} a color of its own.</p></li>')
    idea = f': {slot["idea"]}' if slot.get('idea') else ''
    more = (f'<details><summary>{len(voices) - 2} more jury voices</summary>'
            f'<ul>{"".join(voices[2:])}</ul></details>') if len(voices) > 2 else ''
    votes = 'vote' if standing['firsts'] == 1 else 'votes'
    return f'''<article class="color-card" id="color-{esc(sid)}" aria-labelledby="name-{esc(sid)}">
  <div class="color-story">
    <div class="swatch" style="--swatch: #{swatch}" role="img" aria-label="Color #{swatch}"></div>
    <p class="label">Color {esc(sid)} · #{swatch}</p>
    <h2 id="name-{esc(sid)}">{esc(name)}</h2>
    <p class="maker">Named by {esc(maker)}</p>
    {f'<p class="reason">{esc(why)}</p>' if why else ''}
    <p class="entrusted">Entrusted to {esc(owner + idea)}</p>
    <p class="love{' loved' if loved else ''}">{'♥ ' if loved else ''}{status}</p>
  </div>
  <aside class="margin" aria-label="The margin for {esc(name)}">
    <h3>In the margin</h3>
    <p class="tally">{standing['score']:g} jury points · {standing['firsts']} first-place {votes}</p>
    <ul>{''.join(margins) if margins else '<li>No jury notes recorded.</li>'}</ul>
    {more}
  </aside>
</article>'''


def build(run, output, *, checkpoint=None, drops=None, preview=False, as_of=None):
    run = Path(run)
    as_of = as_of or datetime.now(timezone.utc).date()
    slots = indexed(read(run / 'slots.json'), 'slate')
    decisions = indexed(read(run / 'decision.json'), 'decision')
    if slots.keys() != decisions.keys():
        raise ValueError('decision and slate slots differ')
    picks = indexed(calibration.picks(checkpoint or run / 'checkpoint.json'), 'checkpoint')
    if picks.keys() - slots.keys():
        raise ValueError('checkpoint references an unknown slot')
    schedule = Path(drops) if drops is not None else run.parent / 'drops.json'
    if not schedule.is_file() and not preview:
        raise ValueError(f'drop schedule missing: {schedule}; supply an approved schedule or use --preview')
    released = released_slots(read(schedule), slots, as_of) if schedule.is_file() else set()
    visible = slots.keys() if preview else released
    names = {gid: g['name'] for gid, g in loop.seats(read(run / 'rules.json')).items()}
    cards = [render_card(run, slot, decisions[sid], picks.get(sid), names)
             for sid, slot in slots.items() if sid in visible]
    template = Path(__file__).with_name('palette_gallery_template.html').read_text(encoding='utf-8')
    notice = 'Preview · all colors' if preview else f'{len(cards)} colors revealed · {as_of.isoformat()} UTC'
    body = '\n'.join(cards) or '<p class="empty">The first colors are still waiting in the wings.</p>'
    # One substitution pass: record text resembling a template token remains literal.
    page = re.sub(r'\{\{(CARDS|NOTICE)\}\}',
                  lambda m: {'CARDS': body, 'NOTICE': notice}[m[1]], template)
    return pages.write_html(output, page)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--run', type=Path, default=DEFAULT_RUN)
    parser.add_argument('--checkpoint', type=Path, help='Paul\'s exported picks; default: RUN/checkpoint.json')
    parser.add_argument('--drops', type=Path, help='approved date/colors schedule; default: RUN/../drops.json')
    parser.add_argument('--out', required=True, type=Path, help='HTML output outside the repository')
    parser.add_argument('--preview', action='store_true', help='show all slots, including unscheduled colors')
    parser.add_argument('--as-of', type=iso_date, help='build for this UTC date instead of today')
    args = parser.parse_args()
    try:
        output = build(args.run, args.out, checkpoint=args.checkpoint, drops=args.drops,
                       preview=args.preview, as_of=args.as_of)
    except (OSError, ValueError, KeyError, StopIteration) as error:
        parser.exit(1, f'palette gallery: {error}\n')
    print(output)


if __name__ == '__main__':
    main()
