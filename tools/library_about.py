#!/usr/bin/env python3
"""Checks what library.json says about each painting's real work against its keeper's own record.

The Original, the app's page about a library picture's real work (painting-company row 120), shows a
record's `medium`, `place` and `wikipedia` verbatim, so they are facts to audit like the rest
(docs/picture-library.md › The
record). For every painting this fetches the museum's open-access record of the object its
`source` names and compares:

- `medium`: the museum's own words (The Met's `medium`, Cleveland's `technique`, the Art Institute
  of Chicago's `medium_display`, the Rijksmuseum's English material statement). A record without
  one is fine; one that differs from the museum's is a problem.
- `wikipedia`: an English Wikipedia article about this very work. It is confirmed when Wikidata's
  item for the article is the object itself (the museum's own Wikidata link, or the item carrying
  the museum's number for it), and otherwise listed as "by hand": the article is about a work
  this object is one of (a print's design, a painting made in several versions), which a person
  confirms by reading it. Never add a link the article doesn't bear out.

    python3 tools/library_about.py            # every painting; exits 1 on a problem

Needs network access (the museums' APIs and query.wikidata.org, asked once: it allows few
queries); standard library only.
"""
import json
import pathlib
import sys
import urllib.parse
import urllib.request

LIBRARY = pathlib.Path(__file__).resolve().parent.parent / "App/PaintByNumber/Resources/Samples/library.json"


def get(url, accept="application/json"):
    request = urllib.request.Request(url, headers={"User-Agent": "library-check/1.0", "Accept": accept})
    with urllib.request.urlopen(request, timeout=150) as response:
        return json.load(response)


def museum(record):
    """The museum's medium, and how Wikidata knows the object: its item's address, or a pattern
    that finds `?item` (either may be None)."""
    source = record["source"]
    number = source.rstrip("/").rsplit("/", 1)[1]
    if "metmuseum.org" in source:
        found = get("https://collectionapi.metmuseum.org/public/collection/v1/objects/" + number)
        return found.get("medium"), found.get("objectWikidata_URL") or None
    if "clevelandart.org" in source:
        found = get("https://openaccess-api.clevelandart.org/api/artworks/" + number)["data"]
        items = (found.get("external_resources") or {}).get("wikidata") or []
        return found.get("technique"), items[0] if items else None
    if "artic.edu" in source:
        found = get("https://api.artic.edu/api/v1/artworks/" + number + "?fields=medium_display")["data"]
        return found.get("medium_display"), '?item wdt:P4610 "%s".' % number
    if "rijksmuseum.nl" in source:
        inventory = number.split("--")[0]
        listed = get("https://data.rijksmuseum.nl/search/collection?objectNumber=" + inventory)["orderedItems"]
        found = get(listed[0]["id"], accept="application/ld+json")
        english = "http://vocab.getty.edu/aat/300388277"
        materials = "http://vocab.getty.edu/aat/300435429"
        medium = next(
            (note.get("content") for note in found.get("referred_to_by", [])
             if any(kind.get("id") == materials for kind in note.get("classified_as", []))
             and any(language.get("id") == english for language in note.get("language", []))), None)
        return medium, '?item wdt:P217 "%s"; wdt:P195 wd:Q190804.' % inventory
    return None, None


def articles(known):
    """The English Wikipedia article of each object's own Wikidata item, by picture id."""
    if not known:
        return {}
    items = " ".join('("%s" wd:%s)' % (name, item.rsplit("/", 1)[1]) for name, item in known.items() if item.startswith("http"))
    # The article is asked for inside each branch: joined after the union, the service timed out.
    article = "?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> ."
    parts = ["{ VALUES (?name ?item) { %s } %s }" % (items, article)]
    parts += ['{ %s %s BIND("%s" AS ?name) }' % (item, article, name) for name, item in known.items() if not item.startswith("http")]
    query = "SELECT ?name ?article WHERE { %s }" % " UNION ".join(parts)
    found = get("https://query.wikidata.org/sparql?format=json&query=" + urllib.parse.quote(query))
    return {row["name"]["value"]: urllib.parse.unquote(row["article"]["value"]) for row in found["results"]["bindings"]}


def main():
    problems = 0
    paintings = [record for record in json.loads(LIBRARY.read_text(encoding="utf-8")) if record["kind"] == "painting"]
    known = {}
    for record in paintings:
        name = record["id"]
        try:
            medium, item = museum(record)
        except Exception as error:  # a museum's API down is not the library's fault, but say so
            print(f"{name}: couldn't read its museum's record ({error})")
            problems += 1
            continue
        if item:
            known[name] = item
        if "medium" in record and record["medium"] != medium:
            print(f"{name}: medium {record['medium']!r}, the museum says {medium!r}")
            problems += 1
        elif "medium" not in record and medium:
            print(f"{name}: no medium; the museum says {medium!r}")
        if not record.get("place"):
            print(f"{name}: no place")
            problems += 1
    try:
        exact = articles(known)
    except Exception as error:
        print(f"couldn't ask Wikidata ({error}): the wikipedia links are unchecked")
        return 1
    for record in paintings:
        name, link, own = record["id"], record.get("wikipedia"), exact.get(record["id"])
        if link and urllib.parse.unquote(link) == own:
            print(f"{name}: wikipedia confirmed, the object's own article")
        elif link:
            print(f"{name}: wikipedia by hand ({link}); the object's own item has "
                  + (f"another article, {own}" if own else "no article"))
            problems += 1 if own else 0
        elif own:
            print(f"{name}: no wikipedia; its object's article is {own}")
    print(f"library_about: {problems} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
