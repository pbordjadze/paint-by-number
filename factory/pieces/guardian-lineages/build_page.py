"""Builds the contact sheet: one row per guardian, its four plates in order, liner notes, sources
and Paul's reaction buttons.

usage: python3 build_page.py <lineages.json> <plates dir> <out dir>

The page is static. Reactions POST {"pick": "lineage-<id>", "choice": ..., "note": ...} to /pick,
which the pets-page server (~/pets-drafts/picks_server.py) appends to ~/pets-drafts/picks.jsonl.
"""
import html
import json
import os
import shutil
import sys

CSS = """
body{margin:0;background:#2b2825;color:#ece6dc;font:17px/1.5 Georgia,'Liberation Serif',serif}
main{max-width:1500px;margin:0 auto;padding:28px 20px 80px}
h1{font-weight:normal;font-size:30px;margin:0 0 6px}
.lede{color:#c9c0b2;max-width:900px}
.row{margin:46px 0 0;padding-top:26px;border-top:1px solid #4a453f}
.row h2{font-weight:normal;font-size:25px;margin:0}
.chain{font-style:italic;color:#d8cdb9;margin:2px 0 14px}
.plates{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
@media(max-width:900px){.plates{grid-template-columns:repeat(2,1fr)}}
.plates figure{margin:0}
figcaption a{color:#e7c98f}
.plates img{width:100%;display:block;border-radius:2px;cursor:zoom-in}
figcaption{font-size:14.5px;color:#c9c0b2;margin-top:6px}
figcaption b{color:#ece6dc;font-weight:normal}
.kind{display:inline-block;font-size:12px;letter-spacing:.04em;text-transform:uppercase;padding:0 6px;border-radius:3px;background:#4a453f;color:#e8dcc6}
.kind.spiritual{background:#5b4a6b}
details{margin-top:12px;color:#c9c0b2;font-size:15px}
details a{color:#e7c98f}
.react{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:14px}
.react button{font:inherit;font-size:15px;padding:7px 14px;border-radius:18px;border:1px solid #6a635a;background:#36322e;color:#ece6dc;cursor:pointer}
.react button.on{background:#e7c98f;color:#2b2825;border-color:#e7c98f}
.react input{flex:1;min-width:220px;font:inherit;font-size:15px;padding:7px 10px;border-radius:6px;border:1px solid #6a635a;background:#1f1d1b;color:#ece6dc}
.saved{font-size:13px;color:#9fd3a0;min-width:60px}
.note{color:#e7c98f}
#zoom{position:fixed;inset:0;background:rgba(0,0,0,.88);display:none;align-items:center;justify-content:center;z-index:9}
#zoom img{max-width:96vw;max-height:96vh}
"""

JS = """
function send(pick, choice, note, el){
  fetch('/pick',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({pick:pick,choice:choice,note:note||''})})
  .then(r=>{el.textContent=r.ok?'saved':'not saved ('+r.status+')'})
  .catch(()=>{el.textContent='not saved'});
}
document.querySelectorAll('.react').forEach(box=>{
  const pick=box.dataset.pick, out=box.querySelector('.saved'), note=box.querySelector('input');
  box.querySelectorAll('button[data-choice]').forEach(b=>b.onclick=()=>{
    box.querySelectorAll('button[data-choice]').forEach(x=>x.classList.remove('on'));
    b.classList.add('on'); send(pick,b.dataset.choice,note.value,out);
  });
  box.querySelector('button.send').onclick=()=>{
    if(note.value.trim()) send(pick,'note',note.value,out);
  };
});
const z=document.getElementById('zoom');
document.querySelectorAll('.plates img').forEach(i=>i.onclick=()=>{z.querySelector('img').src=i.src;z.style.display='flex'});
z.onclick=()=>{z.style.display='none'};
"""


def esc(s):
    return html.escape(s or '', quote=True)


def main(data_path, plates, out):
    data = json.load(open(data_path, encoding='utf-8'))
    os.makedirs(out, exist_ok=True)
    rows = []
    for g in data['guardians']:
        figs = []
        for i, s in enumerate(g['steps']):
            src = f"{g['id']}-{i}.webp"
            shutil.copy(os.path.join(plates, src), os.path.join(out, src))
            first = src.replace('.webp', '.first.webp')
            redo = ''
            if os.path.exists(os.path.join(plates, first)):
                shutil.copy(os.path.join(plates, first), os.path.join(out, first))
                redo = f'<br><a href="{first}">first pass (redrawn)</a>'
            kind = s.get('kind', '')
            badge = f'<span class="kind {"spiritual" if "spiritual" in kind else ""}">{esc(kind)}</span> ' if kind else ''
            figs.append(f'<figure><img src="{src}" alt="{esc(s["title"])}" loading="lazy">'
                        f'<figcaption><b>{["Today", "Jump 1", "Jump 2", "Jump 3"][i]}: {esc(s["title"])}</b><br>'
                        f'{esc(s["medium"])}, {esc(s["date"])}<br>{badge}{esc(s.get("link", ""))}{redo}</figcaption></figure>')
        sources = ''.join(f'<li><b>{esc(s["short"])}</b>: {esc(s.get("source", ""))}'
                          + (f' <a href="{esc(s["url"])}">{esc(s["url"])}</a>' if s.get('url') else '') + '</li>'
                          for s in g['steps'][1:])
        chain = ' \u2190 '.join(s['short'] for s in g['steps'])
        note = f'<p class="note">{esc(g["note"])}</p>' if g.get('note') else ''
        rows.append(f"""
<section class="row" id="{g['id']}">
  <h2>{esc(g['name'])}</h2>
  <div class="chain">{esc(chain)}</div>
  <div class="plates">{''.join(figs)}</div>
  {note}
  <details><summary>Sources for each jump</summary><ul>{sources}</ul></details>
  <div class="react" data-pick="lineage-{g['id']}">
    <button data-choice="more like this">more like this</button>
    <button data-choice="not this">not this</button>
    <input placeholder="a note (which plate, what to change)">
    <button class="send">send note</button><span class="saved"></span>
  </div>
</section>""")
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Guardian lineages: pilot</title><style>{CSS}</style></head><body><main>
<h1>Guardian lineages: the pilot</h1>
<div class="lede">{data['lede']}</div>
{''.join(rows)}
<div id="zoom"><img alt=""></div>
</main><script>{JS}</script></body></html>"""
    open(os.path.join(out, 'index.html'), 'w', encoding='utf-8').write(page)


if __name__ == '__main__':
    main(*sys.argv[1:4])
