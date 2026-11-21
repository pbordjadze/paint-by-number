#!/usr/bin/env python3
"""Builds the Museum's catalog (painting-company row 369): every open-access painting, print,
drawing and watercolor two museums offer that the app can paint, one record each, with the
movement it belongs to and how colorful it is.

    tools/museum/catalog.py wikidata
    tools/museum/catalog.py gather --out DIR [--sources aic,cma] [--limit N]
    tools/museum/catalog.py measure --out DIR [--workers 12]
    tools/museum/catalog.py write --out DIR

`gather` reads the museums' APIs into DIR/raw/<source>.jsonl (a rerun of the later steps needs no
network). `measure` fetches each work's smallest rendition and keeps its colorfulness (Hasler and
Süsstrunk's M, 2003, on sRGB: about 0 for a grey print, 30 to 60 for most paintings, over 80 for
the loudest) and its average color, in DIR/measured.jsonl, resuming where it stopped. `write`
puts the catalog the app downloads in DIR/museum.json (and .json.gz), whose shape is
`MuseumCatalog`'s doc comment in the app.

Sources, each read through the museum's own public-domain flag, which is the license (CC0):
  aic  The Art Institute of Chicago, `is_public_domain`; images through its IIIF server
  cma  The Cleveland Museum of Art, `share_license_status` CC0; images from its open-access CDN
The Met's image CDN refuses cloud fetches (painting-company row 368), so it is not a source yet.

The rules are lighter than Tonight's Picture's (tools/nights/catalog.py, a picture everyone gets):
the painter chooses here. A work needs a known maker or culture, an image at least 1500 px on its
long edge and at most 3.5 times its short one, and no title or subject term of nudity or the
erotic; prints and drawings need a colorfulness of 21 (a black-and-white or sepia etching makes a
grey painting). AIC's works need 1686 px across (`aic_record`). The movement is the museum's own style
where it names one of the catalog's (`MOVEMENTS`), else the artist's (`ARTISTS`), else one read
from where and when it was made (`movement_of`). The artists' movements are Wikidata's
(`wikidata` writes `artists.csv` from `artists.rq`; CC0), on the catalog's words (`WIKIDATA_MOVEMENTS`).

Publishing: the file goes on the `museum` branch of this repository (orphan, `[skip ci]`), which
the app reads at raw.githubusercontent.com (`MuseumCatalog.source`).
"""
import argparse
import concurrent.futures as cf
import gzip
import io
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

UA = "PaintByMoonlight-museum/1.0 (open-access catalog)"
MIN_EDGE = 1500
REFUSED_RE = re.compile(r"\b(nudes?|naked|nudity|erotic\w*|shunga|undress\w*)\b", re.IGNORECASE)


def fetch(url, data=None, tries=8, pause=1.1, raw=False, timeout=60):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
            if pause:
                time.sleep(pause)
            return body if raw else json.loads(body)
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):
                return None
            time.sleep(pause * (2 << attempt) + 1)
        except Exception:
            time.sleep(pause * (2 << attempt) + 1)
    return None


# ---- The Art Institute of Chicago ------------------------------------------------------------

AIC = "https://api.artic.edu/api/v1"
AIC_FIELDS = ["id", "title", "artist_id", "artist_title", "artist_display", "date_display", "date_start",
              "date_end", "image_id", "thumbnail", "is_public_domain", "artwork_type_title", "style_title",
              "style_titles", "subject_titles", "term_titles", "classification_titles", "medium_display",
              "place_of_origin", "colorfulness", "department_title"]
# (artwork type id, least AIC colorfulness): paintings and miniatures whatever their color.
AIC_TYPES = [(1, None), (30, None), (18, 12), (14, 12)]
AIC_BANDS = [(-5000, 1700), (1700, 1800), (1800, 1850), (1850, 1880), (1880, 1900), (1900, 1915), (1915, 2100)]


def aic_raw(limit):
    rows = {}
    for kind, least in AIC_TYPES:
        for lo, hi in AIC_BANDS:
            must = [{"term": {"is_public_domain": True}}, {"exists": {"field": "image_id"}},
                    {"term": {"artwork_type_id": kind}}, {"range": {"date_end": {"gte": lo, "lt": hi}}}]
            if least:
                must.append({"range": {"colorfulness": {"gte": least}}})
            page = 1
            while True:
                q = {"limit": 100, "page": page, "fields": AIC_FIELDS, "query": {"bool": {"must": must}}}
                d = fetch(f"{AIC}/artworks/search", data=json.dumps(q).encode())
                if not d:
                    break
                for r in d["data"]:
                    rows[r["id"]] = r
                total = min(d["pagination"]["total"], 10000)
                print(f"aic type {kind} {lo}-{hi}: page {page}, {len(rows)} rows", file=sys.stderr, flush=True)
                if page * 100 >= total or (limit and len(rows) >= limit):
                    break
                page += 1
            if limit and len(rows) >= limit:
                return list(rows.values())[:limit]
    return list(rows.values())


def aic_record(r):
    t = r.get("thumbnail") or {}
    w, h = t.get("width") or 0, t.get("height") or 0
    iid = r.get("image_id")
    kind = {"Painting": "painting", "Miniature Painting": "painting", "Print": "print"}.get(
        r.get("artwork_type_title"), "drawing")
    # AIC's image server gives a CC0 work at 843, 1686 or 3000 pixels wide (other widths, "full"
    # and heights are refused): the widest the image has, and a work under 1686 is left out
    # (`rules`), 843 being too small to paint from.
    size = "3000," if w >= 3000 else "1686,"
    return {
        "id": f"aic-{r['id']}", "source": "aic", "kind": kind,
        "title": r.get("title") or "", "artist": r.get("artist_title") or "",
        "artist_display": r.get("artist_display") or "",
        "year": r.get("date_display") or "", "date": r.get("date_end"),
        "styles": r.get("style_titles") or [], "place": r.get("place_of_origin") or "",
        "image": f"https://www.artic.edu/iiif/2/{iid}/full/{size}/0/default.jpg",
        "thumb": f"https://www.artic.edu/iiif/2/{iid}/full/600,/0/default.jpg",
        "probe": f"https://www.artic.edu/iiif/2/{iid}/full/120,/0/default.jpg",
        "page": f"https://www.artic.edu/artworks/{r['id']}",
        "width": w, "height": h, "medium": r.get("medium_display") or "", "narrow": w < 1686,
        "terms": (r.get("subject_titles") or []) + (r.get("term_titles") or []) + (r.get("classification_titles") or []),
        "department": r.get("department_title") or "",
        "known": aic_known(r),
    }


def aic_known(r):
    """AIC measures each image's colorfulness itself, and its thumbnail carries a tiny preview
    (`lqip`): from them, no image need be fetched. AIC's figure tracks this tool's closely (0.94
    correlation on 104 works, Nov 20, 2026): the fit below puts it on this tool's scale."""
    c = r.get("colorfulness")
    lqip = (r.get("thumbnail") or {}).get("lqip") or ""
    if c is None or not lqip.startswith("data:image"):
        return None
    import base64
    from PIL import Image
    try:
        im = Image.open(io.BytesIO(base64.b64decode(lqip.split(",", 1)[1]))).convert("RGB")
    except Exception:
        return None
    import numpy as np
    mean = np.asarray(im, dtype=np.float64).reshape(-1, 3).mean(0)
    return round(0.937 * c + 1.36, 1), "%02x%02x%02x" % tuple(int(x) for x in mean)


# ---- The Cleveland Museum of Art -------------------------------------------------------------

CMA = "https://openaccess-api.clevelandart.org/api/artworks/"
CMA_QUERIES = [{"type": "Painting"}, {"type": "Print", "culture": "Japan"}, {"type": "Drawing"},
               {"type": "Miniature"}, {"type": "Print"}]


def cma_raw(limit):
    rows = {}
    for params in CMA_QUERIES:
        skip = 0
        while True:
            q = {"cc0": 1, "has_image": 1, "limit": 500, "skip": skip, **params}
            d = fetch(CMA + "?" + urllib.parse.urlencode(q), pause=0.3)
            if not d:
                break
            for r in d["data"]:
                rows[r["id"]] = r
            skip += 500
            print(f"cma {params}: {skip}/{d['info']['total']}, {len(rows)} rows", file=sys.stderr, flush=True)
            if skip >= d["info"]["total"] or (limit and len(rows) >= limit):
                break
    return list(rows.values())[:limit] if limit else list(rows.values())


def cma_record(r):
    imgs = r.get("images") or {}
    big = imgs.get("print") or imgs.get("web") or {}
    creators = r.get("creators") or []
    c = creators[0] if creators else {}
    desc = c.get("description") or ""
    name = re.sub(r"\s*\(.*\)$", "", desc).strip()
    cult = r.get("culture") or []
    try:
        date = int(r.get("creation_date_latest")) if r.get("creation_date_latest") is not None else None
    except (TypeError, ValueError):
        date = None
    kind = {"Painting": "painting", "Miniature": "painting", "Print": "print"}.get(r.get("type"), "drawing")
    return {
        "id": f"cma-{r['id']}", "source": "cma", "kind": kind,
        "title": r.get("title") or "", "artist": name, "artist_display": desc,
        "year": r.get("creation_date") or "", "date": date,
        "styles": [], "place": ", ".join(cult) if isinstance(cult, list) else str(cult),
        "image": big.get("url"), "thumb": (imgs.get("web") or {}).get("url"),
        "probe": (imgs.get("web") or {}).get("url"),
        "page": r.get("url") or "",
        "width": int(big.get("width") or 0), "height": int(big.get("height") or 0),
        "medium": r.get("technique") or "",
        "terms": [r.get("type") or "", r.get("department") or "", r.get("collection") or ""],
        "department": r.get("department") or "",
    }


SOURCES = {"aic": (aic_raw, aic_record), "cma": (cma_raw, cma_record)}


def rules(c):
    if not c.get("image") or not c.get("thumb"):
        return "no image"
    if not (c["artist"] or c["place"]):
        return "maker unknown"
    if c["width"] and max(c["width"], c["height"]) < MIN_EDGE:
        return "image under 1500 px"
    if c["width"] and c["height"] and not 1 / 3.5 <= c["width"] / c["height"] <= 3.5:
        return "a scroll or a strip (beyond 1:3.5)"
    if c.get("narrow"):
        return "image under 1686 px wide (AIC)"
    text = " ".join([c["title"]] + [t for t in c["terms"] if isinstance(t, str)])
    if REFUSED_RE.search(text):
        return "subject"
    return None


# ---- Movements -------------------------------------------------------------------------------

# The catalog's movements, in the order the app lists them (roughly by time, then the rest of
# the world). Each is a word painters and museums use.
MOVEMENTS = [
    "Medieval", "Early Netherlandish", "Renaissance", "Mannerism", "Baroque", "Dutch Golden Age", "Rococo",
    "Neoclassicism", "Romanticism", "Orientalism", "Academic Art", "Barbizon School", "Hudson River School",
    "Realism", "Hague School", "Pre-Raphaelites", "Impressionism", "American Impressionism",
    "Post-Impressionism", "Pointillism", "Nabis", "Pont-Aven School", "Symbolism", "Art Nouveau",
    "Arts and Crafts", "Tonalism", "Ashcan School", "Fauvism", "Expressionism", "Cubism", "Futurism",
    "Art Deco", "Modernism", "Late 19th Century", "Early 20th Century", "Ukiyo-e", "Shin-hanga", "Nihonga",
    "Japanese Painting", "Chinese Painting", "Korean Art", "Indian Painting", "Persian & Islamic", "Folk Art",
]

# Wikidata's movements (P135, as `artists.rq` reads them) onto the catalog's.
WIKIDATA_MOVEMENTS = {
    "Pointillism": ["pointillism", "Neo-impressionism", "divisionism"],
    "Nabis": ["Les Nabis"], "Pont-Aven School": ["Pont-Aven School"], "Fauvism": ["Fauvism"],
    "Cubism": ["cubism", "Orphism"], "Futurism": ["Futurism"], "Art Deco": ["Art Deco"],
    "Art Nouveau": ["Art Nouveau", "Catalan modernism", "École de Nancy", "Vienna Secession", "Jugendstil",
                    "Viennese Secession", "Munich Secession", "Berlin Secession"],
    "Arts and Crafts": ["Arts and Crafts movement"],
    "Pre-Raphaelites": ["Pre-Raphaelite Brotherhood", "Aestheticism"],
    "Barbizon School": ["Barbizon school"], "Hudson River School": ["Hudson River school", "Luminism"],
    "Hague School": ["Hague School"], "Ashcan School": ["Ashcan School"], "Tonalism": ["Tonalism"],
    "American Impressionism": ["American Impressionism"], "Impressionism": ["Impressionism"],
    "Post-Impressionism": ["Post-impressionism", "cloisonnism", "synthetism"],
    "Symbolism": ["Symbolism", "Russian symbolism"], "Expressionism": ["Expressionism", "Die Brücke", "Der Blaue Reiter"],
    "Orientalism": ["Orientalism", "Orientalist painting"],
    "Shin-hanga": ["shin-hanga"], "Ukiyo-e": ["ukiyo-e", "Utagawa school"], "Nihonga": ["Nihonga"],
    "Japanese Painting": ["Kanō school", "Rimpa school", "Yōga", "Maruyama-Shijō school"],
    "Chinese Painting": ["Wu School", "Xin'an School", "Southern School", "Shanghai School", "Zhe school"],
    "Early Netherlandish": ["Early Netherlandish painting"],
    "Dutch Golden Age": ["Dutch Golden Age painting", "Delft school", "fijnschilder"],
    "Mannerism": ["Mannerism", "Northern Mannerism", "School of Fontainebleau"],
    "Rococo": ["Rococo"], "Neoclassicism": ["Neoclassicism", "Classicism", "neo-Pompeian"],
    "Romanticism": ["Romanticism", "Romantic painting", "Nazarene movement", "Norwich school of painters",
                    "Düsseldorf school of painting", "Biedermeier", "Danish Golden Age", "Troubadour style",
                    "romantic nationalism", "Post-romanticism"],
    "Realism": ["realism", "French Realism", "Naturalism", "Costumbrismo", "Peredvizhniki", "social realism"],
    "Academic Art": ["academic art", "Official Salon of Painting and Sculpture", "fairy painting", "Munich school"],
    "Baroque": ["Baroque", "Baroque painting", "Flemish Baroque painting", "Utrecht Caravaggism", "Caravaggisti",
                "tenebrism", "Bamboccianti", "Bolognese school", "Counter-Reformation"],
    "Renaissance": ["Renaissance", "High Renaissance", "German Renaissance", "Venetian school", "Sienese school",
                    "Veronese school", "Northern Renaissance", "Italian Renaissance", "Umbrian school",
                    "Early Renaissance", "Spanish Renaissance", "School of Ferrara", "Florentine School",
                    "Mantuan School"],
    "Medieval": ["International Gothic", "Gothic art", "Cretan school"],
    "Modernism": ["modernism", "modern art", "School of Paris", "avant-garde", "Constructivism", "Suprematism",
                  "abstract art", "Russian avant-garde", "surrealism", "Dada", "primitivism", "Bloomsbury Group"],
    "Folk Art": ["naïve art"],
}
WIKIDATA_TO = {w: m for m, ws in WIKIDATA_MOVEMENTS.items() for w in ws}
# When an artist has several, the most particular wins: this order.
PRIORITY = list(WIKIDATA_MOVEMENTS)

# The museum's own style words, as AIC's `style_titles` write them, onto the catalog's.
STYLE_WORDS = {
    "impressionism": "Impressionism", "post-impressionism": "Post-Impressionism", "pointillism": "Pointillism",
    "neo-impressionism": "Pointillism", "symbolism": "Symbolism", "art nouveau": "Art Nouveau",
    "jugendstil": "Art Nouveau", "fauvism": "Fauvism", "expressionism": "Expressionism",
    "german expressionism": "Expressionism", "cubism": "Cubism", "futurism": "Futurism",
    "romanticism": "Romanticism", "realism": "Realism", "baroque": "Baroque", "rococo": "Rococo",
    "neoclassicism": "Neoclassicism", "renaissance": "Renaissance", "italian renaissance": "Renaissance",
    "northern renaissance": "Renaissance", "gothic": "Medieval", "medieval": "Medieval",
    "byzantine": "Medieval", "ukiyo-e": "Ukiyo-e", "shin hanga": "Shin-hanga", "shin-hanga": "Shin-hanga",
    "pre-raphaelite": "Pre-Raphaelites", "arts and crafts movement": "Arts and Crafts",
    "barbizon school": "Barbizon School", "hudson river school": "Hudson River School",
    "tonalism": "Tonalism", "ashcan school": "Ashcan School", "nabis": "Nabis", "les nabis": "Nabis",
    "modernism": "Modernism", "american impressionism": "American Impressionism",
    "folk art": "Folk Art", "mughal": "Indian Painting", "rajput": "Indian Painting", "pahari": "Indian Painting",
    "edo period": None, "meiji period": None,
}

ARTISTS = {
    "Impressionism": ["Claude Monet", "Pierre-Auguste Renoir", "Camille Pissarro", "Alfred Sisley", "Berthe Morisot",
                      "Edgar Degas", "Gustave Caillebotte", "Édouard Manet", "Eva Gonzalès", "Armand Guillaumin",
                      "Marie Bracquemond", "Federico Zandomeneghi", "Jean-Louis Forain"],
    "American Impressionism": ["Mary Cassatt", "Childe Hassam", "William Merritt Chase", "Theodore Robinson",
                               "John Henry Twachtman", "J. Alden Weir", "Frederick Carl Frieseke", "Edmund Charles Tarbell",
                               "Frank Weston Benson", "Willard Leroy Metcalf", "Theodore Earl Butler", "Lilla Cabot Perry",
                               "Richard E. Miller", "Daniel Garber", "Edward Willis Redfield", "Guy Rose"],
    "Post-Impressionism": ["Vincent van Gogh", "Paul Gauguin", "Paul Cézanne", "Henri de Toulouse-Lautrec",
                           "Odilon Redon", "Émile Bernard", "Paul Sérusier", "Henri Rousseau", "Suzanne Valadon",
                           "Louis Anquetin", "Charles Angrand"],
    "Pointillism": ["Georges Seurat", "Paul Signac", "Henri-Edmond Cross", "Théo van Rysselberghe",
                    "Maximilien Luce", "Hippolyte Petitjean", "Albert Dubois-Pillet"],
    "Nabis": ["Pierre Bonnard", "Édouard Vuillard", "Maurice Denis", "Félix Vallotton", "Ker-Xavier Roussel",
              "Paul Ranson"],
    "Fauvism": ["Henri Matisse", "André Derain", "Maurice de Vlaminck", "Raoul Dufy", "Albert Marquet",
                "Kees van Dongen", "Georges Rouault", "Charles Camoin", "Henri Manguin", "Othon Friesz", "Jean Puy"],
    "Expressionism": ["Vasily Kandinsky", "Wassily Kandinsky", "Franz Marc", "Ernst Ludwig Kirchner", "Emil Nolde",
                      "Karl Schmidt-Rottluff", "Erich Heckel", "Max Pechstein", "August Macke", "Alexej von Jawlensky",
                      "Gabriele Münter", "Edvard Munch", "Egon Schiele", "Oskar Kokoschka", "Paula Modersohn-Becker",
                      "Lyonel Feininger", "Max Beckmann", "Otto Mueller", "Paul Klee"],
    "Cubism": ["Pablo Picasso", "Georges Braque", "Juan Gris", "Fernand Léger", "Robert Delaunay", "Sonia Delaunay",
               "Albert Gleizes", "Jean Metzinger", "Louis Marcoussis", "Roger de La Fresnaye", "Jacques Villon"],
    "Futurism": ["Gino Severini", "Umberto Boccioni", "Giacomo Balla", "Carlo Carrà", "Luigi Russolo"],
    "Art Nouveau": ["Alphonse Mucha", "Gustav Klimt", "Koloman Moser", "Eugène Grasset", "Théophile-Alexandre Steinlen",
                    "Jules Chéret", "Aubrey Beardsley", "Will H. Bradley", "Henri Privat-Livemont", "Edward Penfield",
                    "Louis Rhead", "Ethel Reed", "Carlos Schwabe", "Jan Toorop", "Henry van de Velde", "Leonetto Cappiello"],
    "Symbolism": ["Gustave Moreau", "Pierre Puvis de Chavannes", "Arnold Böcklin", "Fernand Khnopff", "James Ensor",
                  "Ferdinand Hodler", "Giovanni Segantini", "Franz von Stuck", "Lucien Lévy-Dhurmer"],
    "Pre-Raphaelites": ["Dante Gabriel Rossetti", "John Everett Millais", "William Holman Hunt", "Edward Burne-Jones",
                       "John William Waterhouse", "Ford Madox Brown", "Arthur Hughes", "Evelyn De Morgan"],
    "Arts and Crafts": ["William Morris", "Walter Crane", "Charles Rennie Mackintosh", "C. F. A. Voysey"],
    "Romanticism": ["J. M. W. Turner", "Joseph Mallord William Turner", "John Constable", "Caspar David Friedrich",
                    "Eugène Delacroix", "Théodore Géricault", "Francisco Goya", "Francisco José de Goya y Lucientes",
                    "Thomas Cole", "John Martin", "Richard Parkes Bonington", "Ivan Aivazovsky", "Henry Fuseli"],
    "Hudson River School": ["Frederic Edwin Church", "Albert Bierstadt", "Thomas Moran", "Asher Brown Durand",
                            "Jasper Francis Cropsey", "Sanford Robinson Gifford", "John Frederick Kensett",
                            "Martin Johnson Heade", "Fitz Henry Lane", "Worthington Whittredge", "Thomas Doughty"],
    "Barbizon School": ["Jean-Baptiste-Camille Corot", "Camille Corot", "Jean-François Millet", "Théodore Rousseau",
                        "Charles-François Daubigny", "Narcisse Virgilio Díaz de la Peña", "Constant Troyon",
                        "Jules Dupré", "Charles Jacque"],
    "Realism": ["Gustave Courbet", "Rosa Bonheur", "Jules Breton", "Honoré Daumier", "Winslow Homer", "Thomas Eakins",
                "Ilya Repin", "Jean-François Raffaëlli", "Léon Lhermitte", "Jules Bastien-Lepage"],
    "Tonalism": ["James McNeill Whistler", "George Inness", "Dwight William Tryon", "Thomas Wilmer Dewing",
                 "Ralph Albert Blakelock", "Alexander Helwig Wyant"],
    "Ashcan School": ["George Bellows", "Robert Henri", "John Sloan", "George Luks", "Everett Shinn", "William Glackens"],
    "Ukiyo-e": ["Katsushika Hokusai", "Utagawa Hiroshige", "Kitagawa Utamaro", "Suzuki Harunobu", "Utagawa Kuniyoshi",
                "Utagawa Kunisada", "Torii Kiyonaga", "Tōshūsai Sharaku", "Keisai Eisen", "Tsukioka Yoshitoshi",
                "Kobayashi Kiyochika", "Utagawa Toyokuni I", "Isoda Koryūsai", "Katsukawa Shunshō", "Chōbunsai Eishi"],
    "Shin-hanga": ["Kawase Hasui", "Hiroshi Yoshida", "Yoshida Hiroshi", "Ohara Koson", "Itō Shinsui", "Hashiguchi Goyō",
                   "Tsuchiya Koitsu", "Kasamatsu Shirō", "Natori Shunsen", "Takahashi Hiroaki"],
    "Baroque": ["Peter Paul Rubens", "Caravaggio", "Anthony van Dyck", "Diego Velázquez", "Nicolas Poussin",
                "Claude Lorrain", "Artemisia Gentileschi", "Guido Reni", "Bartolomé Esteban Murillo", "Francisco de Zurbarán"],
    "Dutch Golden Age": ["Rembrandt van Rijn", "Johannes Vermeer", "Frans Hals", "Jan Steen", "Jacob van Ruisdael",
                         "Pieter de Hooch", "Meindert Hobbema", "Rachel Ruysch", "Jan Davidsz. de Heem",
                         "Aelbert Cuyp", "Willem Kalf", "Ambrosius Bosschaert the Elder", "Jan van Huysum"],
    "Rococo": ["Jean-Antoine Watteau", "François Boucher", "Jean-Honoré Fragonard", "Giovanni Battista Tiepolo",
               "Canaletto", "Francesco Guardi", "Jean-Baptiste-Siméon Chardin", "Élisabeth Louise Vigée Le Brun",
               "Thomas Gainsborough", "Nicolas Lancret", "Jean-Baptiste Pater"],
    "Neoclassicism": ["Jacques-Louis David", "Jean-Auguste-Dominique Ingres", "Angelica Kauffman", "Antonio Canova",
                      "Anton Raphael Mengs", "Benjamin West", "Joshua Reynolds"],
}
ARTISTS["Arts and Crafts"] += ["Arthur Wesley Dow", "Helen Hyde", "Bertha Lum", "Margaret Jordan Patterson",
                               "Frances Gearhart", "Pedro Joseph de Lemos", "Gustave Baumann", "B. J. O. Nordfeldt",
                               "Ethel Mars", "Edna Boies Hopkins", "Blanche Lazzell", "Tod Lindenmuth",
                               "William Seltzer Rice", "Elizabeth Colborne", "Arthur W. Dow"]
ARTISTS["Art Nouveau"] += ["Carl Moll", "Emil Orlik", "Carl Thiemann", "Walter Klemm", "Ludwig Heinrich Jungnickel",
                           "Franz von Zülow", "Josef Hoffmann", "Henri Rivière", "Maxfield Parrish", "Georges de Feure",
                           "Manuel Orazi", "Paul Berthon", "Maurice Pillard Verneuil"]


def name_key(name):
    import unicodedata
    n = unicodedata.normalize("NFKD", name or "")
    n = "".join(ch for ch in n if not unicodedata.combining(ch)).lower()
    return re.sub(r"[^a-z0-9]+", " ", n).strip()


ARTIST_MOVEMENT = {}
for _m, _names in ARTISTS.items():
    for _n in _names:
        ARTIST_MOVEMENT[name_key(_n)] = _m


def wikidata_movements():
    """Artist name → the catalog's movement, from `artists.csv` (written by `wikidata`)."""
    import csv
    path = Path(__file__).with_name("artists.csv")
    if not path.exists():
        return {}
    found = {}
    for row in csv.DictReader(path.open(encoding="utf-8")):
        m = WIKIDATA_TO.get(row["movement"])
        if m:
            found.setdefault(name_key(row["name"]), set()).add(m)
    # A name of no Latin letters (Chinese, Japanese, Cyrillic) folds to nothing: never a key.
    return {k: min(v, key=PRIORITY.index) for k, v in found.items() if len(k) >= 4 and " " in k}


WIKIDATA = wikidata_movements()

EUROPE = ["france", "french", "italy", "italian", "germany", "german", "netherlands", "dutch", "flemish", "belgium",
          "belgian", "spain", "spanish", "england", "english", "british", "britain", "scotland", "austria", "austrian",
          "switzerland", "swiss", "norway", "norwegian", "sweden", "swedish", "denmark", "danish", "russia", "russian",
          "europe", "bohemia", "czech", "hungary", "poland", "portugal", "ireland", "finland"]
AMERICA = ["united states", "america", "american", "canada", "canadian"]


def movement_of(c):
    """The work's movement: its museum's own style, else its artist's (this file's lists, then
    Wikidata's), else where and when it was made. A guess from the date alone names the period
    ("Late 19th Century") rather than a movement the work may not belong to."""
    d = c.get("date")
    for s in c["styles"]:
        m = STYLE_WORDS.get(s.lower())
        if m:
            return m
    m = artist_movement(c["artist"])
    if m:
        if m == "Ukiyo-e" and d and d >= 1905:
            return "Shin-hanga"
        if m in ("Renaissance", "Early Netherlandish") and d and d < 1400:
            return "Medieval"
        if m == "Impressionism" and has_words(c, AMERICA):
            return "American Impressionism"
        return m
    if has_words(c, ["japan", "japanese"]):
        if c["kind"] == "print":
            return "Shin-hanga" if d and d >= 1905 else "Ukiyo-e"
        return "Japanese Painting"
    if has_words(c, ["china", "chinese"]):
        return "Chinese Painting"
    if has_words(c, ["korea", "korean"]):
        return "Korean Art"
    if has_words(c, ["india", "indian", "pakistan", "nepal", "tibet", "tibetan", "himalayan", "mughal", "rajasthan",
                     "deccan", "pahari", "south asian"]):
        return "Indian Painting"
    if has_words(c, ["iran", "persia", "persian", "turkey", "ottoman", "egypt", "syria", "iraq", "islamic",
                     "uzbekistan", "afghanistan", "arab"]):
        return "Persian & Islamic"
    if not d:
        return None
    dutch = has_words(c, ["netherlands", "dutch", "flemish", "holland"])
    if d < 1400:
        return "Medieval"
    if d < 1600:
        return "Renaissance"
    if d < 1720:
        return "Dutch Golden Age" if dutch else "Baroque"
    if d < 1780:
        return "Rococo"
    if d < 1820:
        return "Neoclassicism"
    if d < 1850:
        return "Romanticism"
    if c["kind"] == "print" and 1890 <= d <= 1912 and re.search(r"color lithograph|colour lithograph|poster", " ".join(
            [c["medium"], c["title"]] + [t for t in c["terms"] if isinstance(t, str)]), re.I):
        return "Art Nouveau"
    if d < 1900:
        return "Late 19th Century"
    return "Early 20th Century"


def artist_movement(name):
    """The movement an artist's name finds, whole, then as its last two words and as its first
    and last ("Hilaire Germain Edgar Degas" is Wikidata's "Edgar Degas", "Édouard Jean Vuillard"
    its "Édouard Vuillard")."""
    words = name_key(name).split()
    if not words:
        return None
    for key in dict.fromkeys([" ".join(words), " ".join(words[-2:]), f"{words[0]} {words[-1]}"]):
        m = ARTIST_MOVEMENT.get(key) or WIKIDATA.get(key)
        if m and " " in key:
            return m
    return None


def has_words(c, words):
    where = " ".join([c["place"], c["artist_display"], c["department"]] + c["styles"]).lower()
    return any(re.search(r"\b" + w + r"\b", where) for w in words)


# ---- Colorfulness ----------------------------------------------------------------------------

def colorfulness(data):
    from PIL import Image
    import numpy as np
    im = Image.open(io.BytesIO(data)).convert("RGB")
    im.thumbnail((96, 96))
    a = np.asarray(im, dtype=np.float64)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    rg = r - g
    yb = 0.5 * (r + g) - b
    m = (rg.std() ** 2 + yb.std() ** 2) ** 0.5 + 0.3 * (rg.mean() ** 2 + yb.mean() ** 2) ** 0.5
    mean = a.reshape(-1, 3).mean(0)
    return round(float(m), 1), "%02x%02x%02x" % tuple(int(x) for x in mean)


def measure_one(c):
    data = fetch(c["probe"], pause=0, raw=True, tries=3, timeout=15)
    if not data:
        return c["id"], None, None
    try:
        m, avg = colorfulness(data)
    except Exception:
        return c["id"], None, None
    return c["id"], m, avg


# ---- Commands --------------------------------------------------------------------------------

def records(out):
    seen = {}
    for name, (_, record) in SOURCES.items():
        p = out / "raw" / f"{name}.jsonl"
        if not p.exists():
            continue
        for line in p.open():
            c = record(json.loads(line))
            c["rejected"] = rules(c)
            c["movement"] = movement_of(c)
            seen[c["id"]] = c
    return list(seen.values())


def wikidata(a):
    """Every artist Wikidata gives a movement (P135) and a death before 1960, with their English
    names and aliases, into artists.csv beside this file (committed: the other steps read it)."""
    query = Path(__file__).with_name("artists.rq").read_text()
    body = fetch("https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query, "format": "json"}),
                 raw=True, tries=3, timeout=120)
    rows = json.loads(body)["results"]["bindings"]
    import csv
    with Path(__file__).with_name("artists.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["name", "movement"])
        for r in sorted({(r["name"]["value"], r["mLabel"]["value"]) for r in rows}):
            w.writerow(r)
    print(f"{len(rows)} names", file=sys.stderr)


def gather(a):
    (a.out / "raw").mkdir(parents=True, exist_ok=True)
    for name in a.sources.split(","):
        rows = SOURCES[name][0](a.limit)
        (a.out / "raw" / f"{name}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
        print(f"{name}: {len(rows)} read", file=sys.stderr)


def measure(a):
    path = a.out / "measured.jsonl"
    done = set()
    if path.exists():
        done = {json.loads(l)["id"] for l in path.open()}
    todo = [c for c in records(a.out) if not c["rejected"] and c["id"] not in done and not c.get("known")]
    print(f"measuring {len(todo)}", file=sys.stderr, flush=True)
    with path.open("a") as f, cf.ThreadPoolExecutor(a.workers) as pool:
        futures = [pool.submit(measure_one, c) for c in todo]
        for i, future in enumerate(cf.as_completed(futures)):
            cid, m, avg = future.result()
            f.write(json.dumps({"id": cid, "colorfulness": m, "average": avg}) + "\n")
            if i % 200 == 0:
                f.flush()
                print(f"{i}/{len(todo)}", file=sys.stderr, flush=True)


def write(a):
    measured = {}
    p = a.out / "measured.jsonl"
    if p.exists():
        for l in p.open():
            j = json.loads(l)
            measured[j["id"]] = j
    works, reasons = [], {}
    for c in records(a.out):
        why = c["rejected"]
        m = measured.get(c["id"], {})
        if c.get("known") and m.get("colorfulness") is None:
            m = {"colorfulness": c["known"][0], "average": c["known"][1]}
        if not why and m.get("colorfulness") is None:
            why = "not measured"
        if not why and c["kind"] != "painting" and m["colorfulness"] < 21:
            why = "too grey for a print or drawing"
        if not why and not c["movement"]:
            why = "no movement"
        if why:
            reasons[why] = reasons.get(why, 0) + 1
            continue
        works.append({
            "id": c["id"], "title": c["title"].strip(), "artist": c["artist"] or c["place"],
            "year": c["year"], "date": c["date"], "movement": c["movement"], "kind": c["kind"],
            "colorfulness": m["colorfulness"], "average": m["average"], "width": c["width"], "height": c["height"],
            "museum": c["source"], "thumb": c["thumb"], "image": c["image"], "page": c["page"] or None,
            "medium": c["medium"][:120],
        })
    works.sort(key=lambda w: w["id"])
    counts = {}
    for w in works:
        counts[w["movement"]] = counts.get(w["movement"], 0) + 1
    movements = [m for m in MOVEMENTS if counts.get(m, 0) >= 12]
    works = [w for w in works if w["movement"] in movements]
    catalog = {
        "version": 1, "made": time.strftime("%Y-%m-%d"),
        "museums": {"aic": "The Art Institute of Chicago", "cma": "The Cleveland Museum of Art"},
        "movements": movements, "works": works,
    }
    body = json.dumps(catalog, ensure_ascii=False, separators=(",", ":")).encode()
    (a.out / "museum.json").write_bytes(body)
    (a.out / "museum.json.gz").write_bytes(gzip.compress(body, 9))
    print(json.dumps({"works": len(works), "movements": {m: counts[m] for m in movements}, "left out": reasons},
                     indent=1, ensure_ascii=False), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("wikidata")
    for name in ("gather", "measure", "write"):
        s = sub.add_parser(name)
        s.add_argument("--out", required=True, type=Path)
        if name == "gather":
            s.add_argument("--sources", default="aic,cma")
            s.add_argument("--limit", type=int, default=0)
        if name == "measure":
            s.add_argument("--workers", type=int, default=12)
    a = ap.parse_args()
    {"wikidata": wikidata, "gather": gather, "measure": measure, "write": write}[a.cmd](a)


if __name__ == "__main__":
    main()
