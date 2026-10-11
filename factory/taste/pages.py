"""Checkpoint and gallery HTML, using the Thirty-Six Colors checkpoint record format."""
import base64
import hashlib
import html
import json
from pathlib import Path
from . import calibration, loop
from .kit import outside_repo


def image_data(path):
    from PIL import Image
    import io
    # Rasterize/strip metadata and embed for a portable, self-contained review page.
    with Image.open(path) as image:
        image.thumbnail((1024, 1024))
        buffer = io.BytesIO()
        image.convert('RGB').save(buffer, format='PNG')
    return 'data:image/png;base64,' + base64.b64encode(buffer.getvalue()).decode()


def generate(run, output, *, n=1, checkpoint=None, gallery=False):
    run, output = Path(run), outside_repo(output)
    record = loop.load(run / 'rules.json')
    gs = loop.seats(record)
    names = {gid: g['name'] for gid, g in gs.items()}
    folder = run / 'rounds' / f'{n:03}'
    if record.get('kitVersion') == 1:
        results = loop.load(folder / 'decision.json')['results']
        slots = {s['slot']: s for s in loop.load(folder / 'slate.json')}
    elif record['piece'] == 'color-names':
        results = loop.load(run / 'decision.json')
        slots = {s['slot']: s for s in loop.load(run / 'slots.json')}
    else:
        decision = loop.load(folder / 'decision.json')
        standings = [{**s, 'vetoes': s['vetoed']} for s in decision['standings']]
        results = [{'slot': 1, 'winner': decision['winner'], 'standings': standings}]
        slots = {1: {'candidates': loop.load(folder / 'slate.json')['slate']}}
    cards = []
    images_by_path = {}
    def embedded(path):
        if path not in images_by_path:
            images_by_path[path] = image_data(path)
        return images_by_path[path]
    for result in results:
        slot = slots[result['slot']]
        candidates = {c['name']: c for c in slot['candidates']}
        standings = [{**s, 'notes': s.get('notes', s.get('whys', [])),
                      'author': names.get(s.get('origin', s['source']), s['source']),
                      'why': candidates.get(s['name'], {}).get('why', '')} for s in result['standings']]
        for standing in standings:
            candidate_images = candidates.get(standing['name'], {}).get('images', slot.get('images', []))
            if candidate_images:
                standing['image'] = embedded(candidate_images[0])
        card = {'slot': result['slot'], 'name': result['winner'], 'standings': standings}
        if 'hex' in slot:
            card['hex'] = slot['hex']
        winner = candidates.get(result['winner'], {})
        images = winner.get('images', slot.get('images', []))
        if images:
            card['image'] = embedded(images[0])
        cards.append(card)
    picks = calibration.picks(checkpoint) if checkpoint else []
    picks = [p for p in picks if p.get('round', 1) == n]
    title = record['piece'].replace('-', ' ').title() + (' · Gallery' if gallery else ' · Checkpoint')
    data = {'cards': cards, 'picks': picks, 'edit': not gallery, 'round': n,
            'key': hashlib.sha256(str(run.resolve()).encode()).hexdigest()[:16]}
    # Prevent records from closing the script element; the page uses textContent for all prose.
    encoded = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    template = Path(__file__).with_name('review.html').read_text()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(template.replace('__TITLE__', html.escape(title)).replace('__DATA__', encoded))
    return output
