# The Lamp under another model

F36 is an opt-in local pet run and a recorded comparison of guardian judgement. Paul waived
style, set and final-image approvals for this run; the primary model's Lamp decides, and Paul
can veto later. The driver creates local files only. It never calls Library or pet-service
upload, creation, selection, activation, update or preflight tools. No live run is recorded here.

Run commands and estimates are in [the taste kit README](../../../taste/README.md#codex-runs-the-lamp).
Paths written as `pieces/…` in older factory documents mean `factory/pieces/…` in the repository.

## Decisions

1. Nineteen guardians propose style sheets (including the waiting Bible School Teacher).
   Originality does not propose taste. A six-seat jury ranks them; Borda scores select two.
   Vetoed or technically flagged styles cannot win. If fewer than two survive, a second and
   final proposal/shortlist round receives the rejection evidence.
2. Four local v2 pilots: the golden ram and trolleybus in each shortlisted style. Identity
   and rightward gait come first. Pilots have no family reference: each creates its own base,
   then grounds its remaining jobs in that base. Both pilots must validate for their style to
   remain eligible.
3. A separate six-seat image jury chooses one surviving style and nominates a reference pilot
   for each style. The winning style's most nominated pilot becomes the fixed family reference;
   Originality abstains from reference nominations. Ties use stable pilot IDs.
   Under decision rules v2, only vetoes exclude a style here. Flags remain attributed drawing
   notes: every subsequent hatch and redo, including the reference guardian's final pet, receives
   the winning style's flags as **readability notes from the image jury**. Waiting, focused work
   and review must read differently from idle and each other at 192 × 208. The notes travel in
   briefs' context, worker requests/prompts and pet provenance; the pilot art stays unchanged.
   All rejected/failed pilots remain in the run, not in `factory/pets/`.
4. All twenty owners draft their own briefs: 150–300 words, 50–80 appearance-note words,
   nine row directions, plus the frozen do-not-resemble entries. Originality also has a pet.
5. Six seats read the whole set. Every flagged brief returns to its owner once. The primary
   model's revised brief goes to the maker; the final image jury checks whether it worked.
6. Hatch all twenty final pets using the jury's chosen pilot contact as their family reference.
   The reference pet already exists before these hatches; no final pet replaces it mid-set.
   Each pet has a separate workspace-write session; image generation within a worker is
   sequential, with at most three pet workers. Technical repairs within a session are bounded
   to two per failing row. On resume, a set pet that failed a gate gets one fresh attempt
   with the prior failure in its request; a second gate failure is terminal. Provider refusals
   are always terminal. Recorded provider stops before work spend no attempt; stops after
   work can continue using preserved art and the cumulative row-repair counts.
7. Six separate image jurors receive the actual contact sheets through `--image`, with every
   frame in playback order at native cell size, owner charters and preview paths. Any redo,
   flag or veto requests one redo. A final jury checks those replacements; a second rejection
   withholds the pet instead of triggering another generation. Only validated, kept pets copy
   into the repository. If no pilot style survives, the run stops with the evidence preserved.
   Completed image decisions stay immutable. A later resume reviews only newly validated pets,
   reuses their existing ballots when available, and appends its decisions. Earlier redos and
   rejections cannot receive another Lamp attempt.

The [maker's call](makers-call.md) is a separate F42 decision: one focused attempt each for
Baba Yaga, Glassblower and Hedge Witch; leave Moon withheld. Passing
`--makers-call factory/pieces/pets/codex-lamp/makers-call.json` explicitly records that commission.
It changes no Lamp rule or verdict. These attempts still require the unchanged validators and
a separate image jury, with no further jury redo. The commission, prior evidence and statement
hash travel into each new package's provenance. An ordinary resume grants no maker attempt;
an already recorded commission resumes without repeating the flag.

Every jury contains Originality and the Painter, who explicitly guards function at 192 × 208
in all nine animation states. Four other seats rotate deterministically through the active
panel. Originality never ranks taste. Vetoes must quote the full normalized guards-against
line exactly. Function flags carry concrete evidence separately. Ties use stable candidate IDs.
Originality receives the glossary; the collection page's current seeds, all charters, chapter-6
replies and Originality's seven risk/fix entries are frozen before any calls.

New text prompts state the v2 contract: 192 × 208 cells, eight columns by eleven rows,
nine animation rows with 6/8/8/4/5/8/6/6/6 frames, then sixteen clockwise look directions.
Looks are poses with a consistent palette, not alternate paint treatments. Hatch workers apply
the contract over conflicting technical numbers or look meanings in existing sheets, preserving
their preset, notes, palette, line, framing, boundaries and motion intent. Each override records
its source field, original text, replacement and reason in the worker reply and pet provenance.
Workers never ask questions or wait for clarification: they decide within the supplied brief,
style and contract and record their choices. This also overrides the skill's interactive steps.
Style-sheet motion numbers are drawing guidance. Workers record target versus observed motion
in their decisions; a numerical difference alone neither consumes repairs nor fails a pet.
Only the skill's validators gate acceptance. The image jury then judges the resulting motion.

The comparison model receives identical prompts and output schemas for proposals, shortlist,
briefs, repairs and set review. It sees the primary model's selected context and is recorded
only: this measures different answers to the same task, not two independent evolving sets.
The image juries and all makers use the primary model. Dispatch derives a strict transport
schema with closed, fully required objects and `anyOf` unions; uniqueness, bounds and string
lengths remain local checks against each job's unchanged full schema. Invalid answers get one
new call with the original prompt, validation reasons and previous reply; both raw answers are
kept. A second invalid answer becomes a durable `invalid` record and the round continues without
its proposal or vote. Invalid owner briefs withhold those pets, including failed brief repairs.
Invalid replies remain visible in comparison reports but contribute no agreement or votes.
A worker report repair only corrects JSON from existing evidence; it does not authorize more art.
Transport failures can resume on rerun. A provider refusal during
hatching never authorizes a revised prompt or a retry; explicit refusal events survive even
if the process dies before writing its final reply.

## Records under the chosen run directory

All live and test scratch output belongs under `/root/factory-out/`. The live run is in `F36/lamp`;
tests use `FACTORY_TEST_OUT` and `TMPDIR`. The run directory is
locked against two simultaneous drivers. Model, effort, sources, skill hashes and jobs are
immutable; changing those inputs requires a new run directory, except for explicitly refreshed
guardian charters on unstarted or explicitly restarted steps, and the explicit blocked-step-3
flag-policy revision below. Parallel limits may change.

`rules.json` freezes the step-specific flag/veto policy. New runs use v2; existing runs without
that file import v1, preserving their original tallies and decision bytes. Shortlist flags still
exclude, set-review flags still return a brief to its guardian once, and image-review flags still
request one redo. None of those policies change with v2.

For a live legacy run blocked at step 3, use
`codex_lamp retally-style <run> --reason 'State-readability flags are drawing notes, not vetoes.'`.
This offline command checks the completed primary ballots, archives the previous decision
verbatim in `records/style-policy/001/style.json`, and records the reason, timestamp and old/new rule
hashes in `provenance.json`. Immutable snapshots in `rule-revisions/` override only step 3;
the original rules, all jobs/replies, earlier decisions and historical replays remain intact.
It refuses a completed style selection or any run that has started step 4 or later. Repeating
the command recovers an interrupted decision write without making calls.

`codex_lamp run <run> <original model/effort options> --dry-resume` requires completed jobs and
pilot hatches, re-tallies through step 3 using frozen policies, and reports the style, fixed
reference and attached notes at the step-4 boundary. It makes no model calls and writes no
step-4 jobs. An ordinary `run` then continues with the same selection and notes.

`codex_lamp list-resume <run>` instead lists the next action for each known hatch and approved
brief without writing any file or calling a model. It distinguishes provider retries before
work, continuations of partial art, the one fresh set attempt, local repackaging and terminal
records. Eligibility comes from the same checks used by hatch dispatch; an exit code alone
never grants a provider retry. The initial hatch `result.json` is immutable; subsequent
outcomes append to `resume-results/000001.json`, etc., and link to the previous completion
with `resumed_from`. New attempt `driver-request.json` files preserve the previous failure,
provider event evidence and attempt budget. Both art and worker reports remain in their
original attempt directories. Validated atlases that only exceed the package budget can be
repackaged with a smaller contact preview; atlas bytes and the 2 MB limit stay unchanged.

`codex_lamp refresh-inputs <run> --reason '…'` saves the current charter text in a new immutable
input revision. `inputs.json` and all dispatched jobs/replies remain unchanged. The provenance
records the old/new hashes, reason, timestamp and started steps. A whole step freezes its inputs
before its first dispatch (including both proposal rounds, or review and its repair). Rerunning
an unchanged refresh is a no-op. Steps already started finish with their original charters;
unstarted steps use the latest revision. Other inputs remain frozen. This command makes no
model calls and needs no generation skill. Use `python3 -m factory.taste.codex_lamp` as the CLI.

To abandon a partial or completed step after a refresh, add `--restart-step N`, with N from
the seven-step plan above (step 3 is job round 005). The step and every later dependent step
move into `records/superseded/<restart>/` with their directory layout and bytes preserved:
jobs, replies, completions, retries, rejections, costs, dispatch work, hatches, decisions and
summary. Earlier steps and historical replays stay active. The manifest and provenance retain
the reason, old input revision for each step, and paths and revisions of superseded replies.
Their step bindings are cleared so the next run writes fresh jobs using current inputs.
An explicit restart works even when the charter refresh itself is unchanged. A pending move
journal is recovered before the next run, refresh or comparison can consume active records.
Comparison outputs are archived and regenerated: superseded replies remain visible, including
raw replies interrupted before collection, but enter no tallies, active totals or paired results.
Paths embedded in archived files remain original evidence; resolve them through the manifest's
archive prefix. Already published repository packages retain the existing overwrite protection.

```text
run.json                         primary/comparison models, effort, skill location, version
rules.json                       frozen step-specific flag/veto policies (v1 legacy, v2 drawing notes)
rule-revisions/<sha256>.json      immutable rules for an explicit style-policy revision
inputs.json                      frozen charters, seeds, glossary, chapter-6 evidence and rules
input-revisions/<sha256>.json     immutable full snapshots; refresh changes only charter text
provenance.json                  input hashes, step revisions, refresh/restart and style-policy history
skill.json                       hashes of the installed generation/validation skill
jobs/NNN/<stage>-<seat>-mN.json    own prompt, schema, model, effort and image attachments
retries/NNN/<job>.json            second attempt with validation reasons and previous reply
replies/NNN/<job>[.retry].json    raw schema answer from the kit runner
records/NNN/<job>.json            durable completion: valid/invalid, errors, reply, hashes, lengths, costs
records/superseded/<restart>/    manifest and unchanged artifacts superseded by a step restart
records/style-policy/001/         original blocked style decision before the explicit rule revision
rejections/NNN/<job>-N.json       invalid reply and validation reasons
costs/NNN/<job>-N.json            measured tokens/time; unknown measurements remain null
dispatch/<unique>/…              every invocation's schema, reply, JSONL and stderr
hatches/<pilot|set|redo|maker>-…/
  request.json                   brief, style, avoidances, reference hash, readability notes, redo reasons
  active-attempt.json            current attempt, stable across an interrupted migration
  attempt-…/                     isolated worker directory, prompts, command and process log
    result.json                  archived original failure when the legacy pilot is retried
    reply[.retry].json           original report and at most one JSON repair
    final/spritesheet.webp       exact v2 encoding submitted to local validation
    qa/                          chroma, frames, directions and continuity evidence
    previews/                    worker's motion GIFs/MP4s and stills
    gate/                        independently executed validator commands/logs/reports/contact
    package/                     validated atlas, contact, pet.json and provenance.json
  result.json                    validated/failed/refused; package hashes or concrete failure
decisions/                       scores, selected style and briefs
decisions/images.json            immutable first completed image pass
decisions/image-resumes/NNN.json  appended outcomes for previously unsettled pets, with ballot sources
decisions/makers-call.json       explicit maker commission, statement, reasons and prior gate evidence
decisions/maker-images.json      separate maker jury and outcomes; no change to Lamp verdicts
summary.json                     Lamp pet statuses plus separate makers_call outcomes when commissioned
replay/
  config.json, sources.json       frozen historical prompts, briefs and Claude replies
  inputs/<piece>/brief.md         read-only brief at a resolvable local path
  baselines/<piece>/<seat>.json   recorded Claude (Haiku), effort unknown
  jobs/, replies/, records/, …    the same per-call layout for the re-posed prompts
comparison.json, comparison.md   paired votes, vetoes, agreement, lengths and verbatim reasons
```

Completion records are atomic, one per job. A crash leaves completed siblings intact; only
in-flight calls may repeat. If a raw reply arrived before the record was written, rerunning
uses it without a new call. Tallies and comparison outputs are derived again from saved replies.
Transport conversion leaves job hashes unchanged; records made before the status field are
treated as valid completions. Schema fixes therefore resume a stopped run at its unfinished jobs.
Dispatched text prompts remain frozen across driver changes, including partially completed
primary/comparison pairs. Replays and comparison artifacts are untouched by `run`.
Hatch failures are normally terminal. Migration covers a legacy pilot with zero image
generations blocked by a missing family reference, a v2 conflict or unanswered clarification,
and the old jump-lift failure that enforced the style's pixel range. Rerunning the same command
archives its old result alongside its original logs
and starts a fresh attempt under the corrected policy. That attempt survives interruption;
if it fails, it is terminal. Provider refusals (including events and repaired replies) never
authorize a retry, nor do unrelated failures. The motion-policy migration may reuse suitable
source art but must complete the pipeline and pass both validators on the exact final atlas.
Re-running verification
checks package hashes before copying anything. Existing differing repository pet files cause
an explicit error rather than being overwritten; identical partial copies can resume.

A kept pet is `factory/pets/<guardian-id>/{pet.json,spritesheet.webp,contact-sheet.webp,provenance.json}`.
The entire four-file package must be at most **2,000,000 bytes**. The parent runs the installed
`validate_atlas.py --require-v2` with the actual chroma key, then `validate_pet_quality.py` on
that exact WebP and its evidence. Both reports must pass and match the final hash. The contact
is rendered from those bytes by the bundled script and compressed independently. Provenance
includes the brief, unchanged style, reference/hash, model/effort, reported generation count,
contract overrides, motion guidance and measured differences, autonomous decisions, technical
repairs, jury redo and validator paths.
Large source art, previews and logs stay outside the repo.
Generation totals are explicitly worker-reported; raw tool events are retained for auditing.

## Historical replay and its limits

Replay covers the **main round** of chapter-6, renumber and front-door: 19 prompts each.
The later five-seat `front-door/review` draft review is excluded: it references an old worktree
and images, not just that piece's frozen brief. No current draft is substituted for that evidence.

Every recorded prompt is passed to stdin byte for byte, including its obsolete absolute paths
and Write-tool directions. A separately recorded `transport_instructions` field, passed as
Codex developer instructions, maps only the brief read to its frozen file and returns the JSON
in the reply instead of writing a file and saying `done`. This unavoidable transport difference
is disclosed; the content question and charter are unchanged. Claude replies retain the label
**Claude (Haiku)**, without an exact model identifier or an invented effort.

Comparison is descriptive: categorical equality, ranking top-choice and pairwise agreement,
and veto-target agreement. It quotes up to three verbatim reasons per response. It does not
score prose similarity or treat absent votes as agreement. JSON includes full replies and
per-seat/model aggregates. Claude reply lengths use normalized JSON; new lengths use raw reply
characters. No extra model calls or image generations are needed for comparison.
Input revisions have separate aggregates and are never paired across a charter refresh;
each reply and comparison includes its input hash.
