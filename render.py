#!/usr/bin/env python3
"""Build site/index.html, the chronicle's published page, from story/, log/ and sessions.json.

    render.py [<chronicle dir>]

Newest night first. The page carries the log as JSON too (`<script id="log">`)."""
import html, json, pathlib, re, sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent)
sessions = json.loads((root / "sessions.json").read_text())
KINDS = {"start": "Started", "ask": "Needs Paul", "decision": "Paul decided", "idea": "Idea",
         "work": "Progress", "ship": "Shipped", "ci": "CI", "block": "Blocked",
         "review": "Review", "end": "Finished", "note": "Note"}


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", text)
    return re.sub(r"\[([^\]]+)\]\((https://[^)]+)\)", r'<a href="\2">\1</a>', text)


def markdown(md):
    out, para, items = [], [], []
    def flush():
        if para: out.append("<p>" + inline(" ".join(para)) + "</p>"); para.clear()
        if items: out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>"); items.clear()
    for line in md.splitlines():
        s = line.strip()
        if not s: flush(); continue
        m = re.match(r"(#{1,3}) (.*)", s)
        if m:
            flush(); level = len(m.group(1)) + 1
            out.append(f"<h{level}>{inline(m.group(2))}</h{level}>"); continue
        if s.startswith("- "):
            if para: flush()
            items.append(s[2:]); continue
        if items and line.startswith("  "): items[-1] += " " + s; continue
        para.append(s)
    flush()
    return "\n".join(out)


def night(date):
    story = root / "story" / f"{date}.md"
    log = root / "log" / f"{date}.jsonl"
    events = [json.loads(l) for l in log.read_text().splitlines() if l.strip()] if log.exists() else []
    body = markdown(story.read_text()) if story.exists() else f"<h2>{date}</h2>"
    rows = []
    for e in events:
        who = sessions.get(e["session"], {}).get("title", e["session"])
        meta = " · ".join(x for x in (e.get("branch"), e.get("sha"), f"row {e['row']}" if e.get("row") else "") if x)
        quote = f'<blockquote>Paul: “{inline(e["paul"])}”</blockquote>' if e.get("paul") else ""
        rows.append(f'''<li class="ev" data-kind="{e["kind"]}">
  <time datetime="{e["at"]}">{e["at"][11:16]}</time>
  <div class="evbody"><div class="evhead"><span class="chip k-{e["kind"]}">{KINDS.get(e["kind"], e["kind"])}</span><span class="who">{html.escape(who)}</span></div>
  <p>{inline(e["text"])}</p>{quote}{f'<div class="meta">{html.escape(meta)}</div>' if meta else ""}</div></li>''')
    return body, rows, events


dates = sorted({p.stem for p in (root / "story").glob("*.md")} | {p.stem for p in (root / "log").glob("*.jsonl")}, reverse=True)
sections, all_events = [], []
for d in dates:
    body, rows, events = night(d)
    all_events += events
    asks = [e for e in events if e["kind"] in ("ask", "block")]
    sections.append(f'''<section class="night" id="n{d.replace("-", "")}">
<article class="story">{body}</article>
<details class="log" open><summary>The log · {len(events)} entries</summary><ol class="timeline">{"".join(rows)}</ol></details>
</section>''')

crew = []
for sid, s in sorted(sessions.items(), key=lambda kv: kv[1].get("started", ""), reverse=True):
    asked = f'<blockquote>“{inline(s["asked"])}”</blockquote>' if s.get("asked") else ""
    crew.append(f'<li><div class="cname">{html.escape(s["title"])}</div><div class="crole">{inline(s.get("role", ""))} · since {s.get("started", "")[5:16].replace("T", " ")}</div>{asked}</li>')

updated = max((e["at"] for e in all_events), default="")
page = (root / "page.html").read_text()
page = page.replace("{{UPDATED}}", updated[:16].replace("T", " ")).replace("{{NIGHTS}}", "\n".join(sections))
page = page.replace("{{CREW}}", "\n".join(crew)).replace("{{LOG}}", json.dumps(all_events, ensure_ascii=False).replace("</", "<\\/"))
(root / "site").mkdir(exist_ok=True)
(root / "site" / "index.html").write_text(page)
print(root / "site" / "index.html", len(all_events), "events")
