"""Private contracts for the frozen panel-name v1 and color-names v2 records.

Their snapshots own the glossary and cap switch. New runs never load these inputs.
"""
import re


def frozen(record):
    return (record.get("recorded") is True and not record.get("kitVersion") and
            record.get("promptVersion", 1) == 1 and
            (record.get("piece"), record.get("version")) in
            (("panel-name", 1), ("color-names", 2)))


_THREAD = ("The Georgian thread is felt, not named: use materials, light, gardens and habits. "
           "Across the whole set, at most one name in fifty uses a Georgian place name, "
           "and at most one in thirty uses a Georgian word.")


def caps_prompt(record):
    return _THREAD if frozen(record) else ""


def glossary_prompt(record):
    if not frozen(record):
        return ""
    return "Georgian glossary (ordinary cultural words, not franchise references):\n" + "\n".join(
        f"- {word}: {meaning}" for word, meaning in record["glossary"]["words"].items())


def _contains(name, terms):
    return any(re.search(r"(?<![a-z])" + re.escape(term.lower()) + r"(?![a-z])", name.lower())
               for term in terms)


class GeorgianCaps:
    def __init__(self, record):
        self.record = record

    def __call__(self, table):
        if not frozen(self.record) or not self.record["sharedBar"]:
            return []
        names, glossary = list(table.values()), self.record["glossary"]
        return [(kind, "Georgian " + kind) for kind, terms, denominator in
                (("places", glossary["places"], 50), ("words", glossary["words"], 30))
                if sum(_contains(n, terms) for n in names) > len(names) // denominator]

    def contributes(self, name, kind, word):
        return (frozen(self.record) and self.record["sharedBar"] and
                kind in ("places", "words") and _contains(name, self.record["glossary"][kind]))


def panel_craft(name, record):
    if frozen(record) and any("Ⴀ" <= c <= "ჿ" or "Ა" <= c <= "Ჿ" for c in name):
        return ["no Georgian letters as ornament"]
    return []


PANEL_BRIEF = """Medea is an iPhone and iPad app that turns a photo into a paint-by-numbers painting, made on the device, that you then paint with your finger or Apple Pencil. It is named for Medea of Colchis (today's western Georgia): a kind, helpful witch whose magic makes the old new. Its look should remind anyone who knows Georgia of Georgia, without being obviously Georgian (no flags, no Georgian letters as decoration, no tourist cliches). It must never look like Harry Potter, Disney or any other famous franchise.

Every design decision for the app (colors, logo, animations, words) is judged by a panel of guardians. Each guardian keeps one idea and judges every design for it; for each decision a jury of six is drawn from the panel. These are the guardians:
{roster}

The panel needs a name for itself: what the guardians are called together. The name appears on review pages and in the record of decisions ("This palette was chosen by ..."), and it may one day be seen by the app's users, so it should be beautiful, memorable and true to the panel."""

