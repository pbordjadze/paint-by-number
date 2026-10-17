You are coding reviewers' findings about four candidate identities (a name and an icon) for an iOS
app, numbered #1 to #4. You don't know who wrote each finding or under what conditions, and you
don't need to: code each one on its own words.

1. Read {POOL} with the Read tool. It is a JSON list of findings: {"id", "about" ("#1".."#4" or
   "all"), "text"}. Read nothing else and don't search the web.
2. Put every finding in a cluster. A cluster is one issue: one judgment about one detail of one
   candidate (or of all of them). Two findings share a cluster when they point at the same detail
   of the same candidate and judge it the same way, even in different words ("the 6 vanishes at
   the smallest size" and "numeral unreadable at 40 px" are one cluster). Praise and complaint of
   the same detail are two clusters; the same detail on two candidates is two clusters. Name each
   cluster with a short kebab-case label that starts with its candidate, like "#2-numeral-lost-small"
   or "all-names-too-similar".
3. Mark each finding checkable (true) when it names a candidate, or all of them, and a detail
   anyone could verify by looking at the images (a shape, a color, a size, a word, a truncation, a
   resemblance to a named rival). Mark it false when it is taste or feeling with nothing to check
   ("[#3] feels warm", "the best of the four").
4. Write {OUT} and nothing else anywhere, as one JSON object with every id:
   {"f001": {"cluster": "#2-numeral-lost-small", "checkable": true}, ...}
Your final message is the single word: done
