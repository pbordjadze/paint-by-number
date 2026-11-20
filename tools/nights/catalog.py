#!/usr/bin/env python3
"""Gathers the candidates for Tonight's Picture's catalog (painting-company row 368) from the museums'
open-access APIs and applies the library's hard rules (docs/picture-library.md) to their metadata.

    tools/nights/catalog.py --out DIR [--sources aic,cma,met] [--limit N]

Writes DIR/candidates.jsonl (one record a line, `rejected` naming the rule a refused one broke, or
null) and DIR/raw/<source>.jsonl (the APIs' answers, so a rerun with new rules needs no network:
--offline). Sources, each read through the museum's own public-domain flag:

  aic  Art Institute of Chicago, `is_public_domain` (CC0 images by IIIF): paintings, and prints
       from Arts of Asia (the woodblock prints)
  cma  Cleveland Museum of Art, `share_license_status` CC0: paintings, and Japanese prints
  met  The Met, `isPublicDomain` (Open Access): European Paintings and the American Wing's paintings

The rules (any doubt rejects): made by 1930 and its maker dead by 1955 (both known), at least 2048 px
on the long edge, a painting or print, and no subject the library refuses (nudity, violence,
religious iconography as the subject, death), read from titles, the museums' subject terms and tags.
What survives is judged on its template next (judge.py), then by eye.
"""
import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

UA = "PaintByMoonlight-catalog/1.0 (open-access research)"
MAX_YEAR = 1930
MAX_DEATH = 1955
MIN_EDGE = 2048

# Words that refuse a picture when they appear in its title, subjects or tags (whole words,
# case-insensitive). Broad on purpose: thousands of candidates remain, and a miss costs nothing.
REFUSED = [
    r"nudes?", r"naked", r"bath(er|ers|ing|sheba)?", r"undress\w*", r"toilette?", r"odalisque",
    r"venus", r"nymphs?", r"satyrs?", r"bacchan\w*", r"leda", r"dana[eë]", r"susanna", r"judith", r"salome",
    r"lucretia", r"cupid", r"eros", r"psyche", r"adam", r"eve",
    r"christ", r"jesus", r"madonna", r"virgin", r"saints?", r"st\.", r"apostles?", r"crucifi\w*", r"martyr\w*",
    r"annunciation", r"nativity", r"adoration", r"piet[aà]", r"deposition", r"entombment", r"resurrection",
    r"lamentation", r"holy", r"angels?", r"magi", r"baptism", r"pope", r"bishop", r"monk", r"nun", r"buddha",
    r"bodhisattva", r"deity", r"gods?", r"goddess", r"religio\w*", r"christianity", r"biblical", r"bible",
    r"battle", r"war", r"fight\w*", r"boxing", r"boxers?", r"soldiers?", r"army", r"warriors?", r"samurai", r"executions?", r"murder", r"massacre",
    r"death", r"dead", r"dying", r"skulls?", r"corpse", r"funeral", r"blood", r"hunt(ing)?", r"slaughter",
    r"vanitas", r"ghosts?", r"demons?", r"devil", r"hell", r"shipwreck", r"wreck", r"fire", r"storm",
    r"kabuki", r"actors?", r"courtesans?", r"geisha", r"shunga", r"erotic\w*", r"lovers",
    r"slaves?", r"slavery",
]
REFUSED_RE = re.compile(r"\b(" + "|".join(REFUSED) + r")\b", re.IGNORECASE)


def fetch(url, tries=8, pause=1.5, data=None):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read()
            time.sleep(pause)
            return json.loads(body)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(pause * (4 << attempt))
        except Exception:
            time.sleep(pause * (2 << attempt))
    raise RuntimeError(f"giving up on {url}")


def year_of(text):
    m = re.findall(r"\b(1[0-9]{3})\b", text or "")
    return int(m[-1]) if m else None


# ---- Art Institute of Chicago ----------------------------------------------------------------

AIC = "https://api.artic.edu/api/v1"
AIC_FIELDS = ["id", "title", "artist_id", "artist_title", "date_display", "date_end", "image_id", "thumbnail",
              "is_public_domain", "artwork_type_title", "classification_titles", "subject_titles", "term_titles",
              "medium_display", "credit_line", "department_title", "place_of_origin"]


def aic_search(must):
    out, page = [], 1
    while True:
        q = {"limit": 100, "page": page, "fields": AIC_FIELDS, "query": {"bool": {"must": must}}}
        d = fetch(f"{AIC}/artworks/search", data=json.dumps(q).encode())
        out += d["data"]
        if page * 100 >= min(d["pagination"]["total"], 10000):
            return out
        page += 1


def aic_raw(limit):
    base = [{"term": {"is_public_domain": True}}, {"range": {"date_end": {"lte": MAX_YEAR}}},
            {"exists": {"field": "image_id"}}]
    rows = aic_search(base + [{"term": {"artwork_type_id": 1}}])
    rows += aic_search(base + [{"term": {"artwork_type_id": 18}}, {"term": {"department_title.keyword": "Arts of Asia"}}])
    rows = rows[:limit] if limit else rows
    ids = sorted({r["artist_id"] for r in rows if r.get("artist_id")})
    deaths = {}
    for i in range(0, len(ids), 100):
        d = fetch(f"{AIC}/agents?limit=100&fields=id,death_date&ids=" + ",".join(map(str, ids[i:i + 100])))
        deaths.update({a["id"]: a.get("death_date") for a in d["data"]})
    for r in rows:
        r["_death"] = deaths.get(r.get("artist_id"))
    return rows


def aic_record(r):
    t = r.get("thumbnail") or {}
    w, h = t.get("width") or 0, t.get("height") or 0
    kind = "print" if r.get("artwork_type_title") == "Print" else "painting"
    return {
        "id": f"aic-{r['id']}", "source_name": "aic", "kind": kind,
        "title": r.get("title") or "", "creator": r.get("artist_title") or "",
        "year": r.get("date_display") or "", "made": r.get("date_end"), "died": r.get("_death"),
        "credit": "The Art Institute of Chicago" + (f", {r['credit_line']}" if r.get("credit_line") else ""),
        "license": "CC0 / Public domain",
        "source": f"https://www.artic.edu/artworks/{r['id']}",
        "evidence_url": f"{AIC}/artworks/{r['id']}",
        "evidence": f"{AIC}/artworks/{r['id']}: \"is_public_domain\": true; images CC0 (https://www.artic.edu/open-access/open-access-images)",
        "image": f"https://www.artic.edu/iiif/2/{r['image_id']}/full/2048,/0/default.jpg" if w >= h else
                 f"https://www.artic.edu/iiif/2/{r['image_id']}/full/,2048/0/default.jpg",
        "thumb": f"https://www.artic.edu/iiif/2/{r['image_id']}/full/400,/0/default.jpg",
        "width": w, "height": h, "medium": r.get("medium_display") or "",
        "place": "The Art Institute of Chicago",
        "terms": (r.get("subject_titles") or []) + (r.get("term_titles") or []),
    }


# ---- Cleveland Museum of Art -----------------------------------------------------------------

CMA = "https://openaccess-api.clevelandart.org/api/artworks/"


def cma_raw(limit):
    rows = []
    for params in ({"type": "Painting"}, {"type": "Print", "culture": "Japan"}):
        skip = 0
        while True:
            q = {"cc0": 1, "has_image": 1, "created_before": MAX_YEAR, "limit": 500, "skip": skip, **params}
            d = fetch(CMA + "?" + urllib.parse.urlencode(q), pause=0.3)
            rows += d["data"]
            skip += 500
            if skip >= d["info"]["total"] or (limit and len(rows) >= limit):
                break
    return rows[:limit] if limit else rows


def cma_record(r):
    imgs = r.get("images") or {}
    full = imgs.get("full") or imgs.get("print") or {}
    creators = r.get("creators") or [{}]
    c = creators[0] if creators else {}
    name = re.sub(r"\s*\(.*\)$", "", c.get("description") or "").strip()
    died = c.get("death_year")
    try:
        died = int(died) if died else None
    except ValueError:
        died = None
    tags = []
    for k in ("type", "technique", "department", "collection", "culture"):
        v = r.get(k)
        tags += v if isinstance(v, list) else [v] if v else []
    return {
        "id": f"cma-{r['id']}", "source_name": "cma", "kind": "print" if r.get("type") == "Print" else "painting",
        "title": r.get("title") or "", "creator": name, "year": r.get("creation_date") or "",
        "made": r.get("creation_date_latest"), "died": died,
        "credit": "The Cleveland Museum of Art" + (f", {r['creditline']}" if r.get("creditline") else ""),
        "license": "CC0",
        "source": r.get("url") or "", "evidence_url": f"{CMA}{r['id']}",
        "evidence": f"{CMA}{r['id']}: \"share_license_status\": \"{r.get('share_license_status')}\"",
        "image": (imgs.get("print") or full).get("url"), "thumb": (imgs.get("web") or {}).get("url"),
        "width": int(full.get("width") or 0), "height": int(full.get("height") or 0),
        "medium": r.get("technique") or "", "place": "The Cleveland Museum of Art",
        "terms": tags,
    }


# ---- The Met ---------------------------------------------------------------------------------

MET = "https://collectionapi.metmuseum.org/public/collection"


def met_raw(limit):
    ids = []
    for dept in (11, 1):
        offset = 0
        while True:
            d = fetch(f"{MET}/v1.1/search?isPublicDomain=true&hasImages=true&departmentId={dept}&q=painting"
                      f"&offset={offset}&limit=500", pause=0.2)
            ids += d.get("objectIDs") or []
            offset += 500
            if offset >= d.get("total", 0):
                break
    ids = list(dict.fromkeys(ids))[:limit] if limit else list(dict.fromkeys(ids))
    rows = []
    for i in ids:
        o = fetch(f"{MET}/v1/objects/{i}", pause=0.08)
        if o:
            rows.append(o)
    return rows


def met_record(o):
    end = o.get("artistEndDate") or ""
    return {
        "id": f"met-{o['objectID']}", "source_name": "met",
        "kind": "painting" if (o.get("classification") or "").startswith("Painting") else "other",
        "title": o.get("title") or "", "creator": o.get("artistDisplayName") or "",
        "year": o.get("objectDate") or "", "made": o.get("objectEndDate"), "died": year_of(end),
        "credit": "The Metropolitan Museum of Art" + (f", {o['creditLine']}" if o.get("creditLine") else ""),
        "license": "CC0 / Public domain", "source": o.get("objectURL") or "",
        "evidence_url": f"{MET}/v1/objects/{o['objectID']}",
        "evidence": f"{MET}/v1/objects/{o['objectID']}: \"isPublicDomain\": {str(o.get('isPublicDomain')).lower()}",
        "image": o.get("primaryImage"), "thumb": o.get("primaryImageSmall"),
        "width": 0, "height": 0,  # the Met gives no size: judge.py measures the file
        "medium": o.get("medium") or "", "place": "The Metropolitan Museum of Art, New York",
        "terms": [t.get("term", "") for t in (o.get("tags") or [])] + [o.get("classification") or ""],
        "public_domain": o.get("isPublicDomain"),
    }


SOURCES = {"aic": (aic_raw, aic_record), "cma": (cma_raw, cma_record), "met": (met_raw, met_record)}


def judge_rules(c):
    if c.get("public_domain") is False:
        return "not public domain"
    if c["kind"] not in ("painting", "print"):
        return "not a painting or print"
    if not c.get("image"):
        return "no image"
    made = c.get("made")
    if not isinstance(made, int) or made > MAX_YEAR:
        return "made after 1930 or undated"
    if not isinstance(c.get("died"), int) or c["died"] > MAX_DEATH:
        return "maker's death unknown or after 1955"
    if not c["creator"] or re.search(r"unknown|anonymous|attributed|workshop|follower|circle of|after\b",
                                     c["creator"], re.IGNORECASE):
        return "maker unknown or uncertain"
    if c["width"] and max(c["width"], c["height"]) < MIN_EDGE:
        return "image under 2048 px"
    text = " ".join([c["title"]] + [t for t in c["terms"] if isinstance(t, str)])
    m = REFUSED_RE.search(text)
    if m:
        return f"subject: {m.group(0).lower()}"
    if "italy" in (c.get("credit") or "").lower():
        return "Italian holding"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--sources", default="aic,cma,met")
    ap.add_argument("--limit", type=int, default=0, help="at most N per source (a quick try)")
    ap.add_argument("--offline", action="store_true", help="reuse DIR/raw instead of the network")
    a = ap.parse_args()
    (a.out / "raw").mkdir(parents=True, exist_ok=True)
    out = []
    for name in a.sources.split(","):
        raw_path = a.out / "raw" / f"{name}.jsonl"
        gather, record = SOURCES[name]
        if a.offline:
            rows = [json.loads(l) for l in raw_path.open()]
        else:
            rows = gather(a.limit)
            raw_path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
        for r in rows:
            c = record(r)
            c["rejected"] = judge_rules(c)
            out.append(c)
        kept = sum(1 for c in out if c["source_name"] == name and not c["rejected"])
        print(f"{name}: {len(rows)} read, {kept} pass the rules", file=sys.stderr)
    with (a.out / "candidates.jsonl").open("w") as f:
        for c in out:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")
    reasons = {}
    for c in out:
        if c["rejected"]:
            key = c["rejected"].split(":")[0]
            reasons[key] = reasons.get(key, 0) + 1
    print(json.dumps(reasons, indent=1), file=sys.stderr)


if __name__ == "__main__":
    main()
