# The taste loop

`loop.py` owns seeded ledger draws, individual blind ballots, weighted Borda scoring, vetoes,
unique slot winners, whole-set caps, the optional owner guarantee and the representation ledger.
`pieces/panel_name.py` and `pieces/color_names.py` supply the briefs, agent formats, craft checks,
slots, tie preferences and rendering in use. `transcripts.py` reads the final `SubagentHandback`
from a Claude Code `.output` file. The loop never launches agents or chooses taste itself.

The old entry points still work from any directory:

```sh
TASTE_RUN=/path/to/run python3 factory/taste/taste.py draw 1
TASTE_RUN=/path/to/run python3 factory/taste/taste.py proposals 1
TASTE_RUN=/path/to/run python3 factory/taste/taste.py extract 1 proposals robber-girl /path/to/agent.output
TASTE_RUN=/path/to/run python3 factory/taste/taste.py collect 1
TASTE_RUN=/path/to/run python3 factory/taste/taste.py extract 1 verdicts moon /path/to/agent.output
TASTE_RUN=/path/to/run python3 factory/taste/taste.py decide 1
TASTE_RUN=/path/to/run python3 factory/taste/taste.py finalists 1
TASTE_RUN=/path/to/run python3 factory/taste/taste.py decide-finalists 1
COLORS_RUN=/path/to/run python3 factory/taste/colors.py setup
COLORS_RUN=/path/to/run python3 factory/taste/colors.py prompts
COLORS_RUN=/path/to/run python3 factory/taste/colors.py extract proposals robber-girl /path/to/agent.output
COLORS_RUN=/path/to/run python3 factory/taste/colors.py collect
COLORS_RUN=/path/to/run FACTORY_OUT=/root/factory-out python3 factory/taste/colors.py sheets
COLORS_RUN=/path/to/run python3 factory/taste/colors.py judges
COLORS_RUN=/path/to/run python3 factory/taste/colors.py decide
```

Between those commands, the orchestrator runs agents with the written prompts and extracts their
replies. Color extraction also accepts an agent ID under `$TASTE_TASKS`. Render output belongs
outside the repository. `FACTORY_OUT` defaults to `~/factory-out`.

Before the first draw or setup, `rules.json` freezes the version, seats (including charters and
weights), calibration factors, glossary and, for colors, the input vocabulary. To configure a new
run, call `loop.rules(run, piece)` before drawing and set its `calibration` factors or `guarantee`
option before the run starts. Later commands read that snapshot. Unknown versions are errors.

- Rules **v1** reproduce the panel run: any veto reason is accepted, ranking gaps go last, and
  the incumbent breaks ties after points and first places. The original all-vetoed fallback is
  retained for replay.
- Rules **v2** require a quote from the charter's **guards against** line. Slot selection applies
  uniqueness and the piece's caps before the optional guarantee. A guarantee cannot defeat a veto,
  duplicate a name or break a cap. An impossible new selection fails explicitly.
  When caps or representation require several substitutions together, new runs search for a
  legal assignment in deterministic order, trying the current winners first.
- The recorded color run had an Originality exemption, no shared-bar check, and ten cap-repair
  attempts. Its snapshot records these historical settings (`recorded`, `originalityFreeVeto`,
  `sharedBar`) so its decisions still replay exactly. New runs use v2, require quotes from
  Originality too, and enforce the Georgian bar. Recorded output schemas stay unchanged;
  new decisions report `broad_favorite` and `most_loved` separately. The panel CLI reports both
  for old decisions too.

The existing panel ledger is unchanged. The color script previously wrote no ledger; its added
ledger records the winning proposers and the jurors whose first-choice reasons support each winner.
Both replay tests rebuild decisions and ledgers from inputs, compare bytes and verify idempotence.
Historical `nina` IDs and the display name Nina remain in those snapshots; today's `robber-girl`
seat has a `nina` alias, which also carries representation through to new draws.

The Georgian check counts names in the final set, using whole terms from `glossary.json`: at most
`floor(set size / 50)` place names and `floor(set size / 30)` Georgian words. For colors, the set
is the entire vocabulary, including anchors outside the batch. For a one-name panel, both limits
are zero. Glossary definitions go to Originality; all prompts say the thread is felt, not named.
Proposers receive their own past names, points, first places, vetoes and wins. The finalist hook
writes a separate jury, slate, blind ballots and prompts; its verdict and decision files never
overwrite the first jury's records.

Tests: `python3 -m pytest tools/factory/test_taste.py` (or the dependency-free equivalent
`python3 -m unittest discover -s tools/factory -p test_taste.py`).
