# Overnight run: picture library and line-art research

Status: approved plan, not started. Written on `claude/overnight-plan` (cut from `main` =
`claude/paint-by-numbers-app` at 8c7601f). The session that runs it starts here.

Read `CLAUDE.md` first and follow it. `docs/wave2/RULES.md` applies to any agent that touches
code (no Xcode here, re-read edited Swift files, saved-data compatibility, string catalog,
demo code under `#if DEBUG`, determinism), with this file's branch names in place of wave 2's.

## What the owner wakes up to

1. **A new app build** shipping a curated default library: 20–30 public-domain paintings and
   15–20 public-domain photographs, published by CI as a `build-<run>` release and offered by
   the SideStore source. Specification: `library.md`.
2. **Options to pick from** for a future zen mode, where the line art is a legible drawing of
   the picture and the color regions sit inside its lines without being outlined by them.
   Exploration only: nothing from it goes into PaintCore or the app. Specification: `lineart.md`.
3. **One morning page**: a private claude.ai artifact that links everything: the library
   contact sheet with credits and the alternates that were nearly picked, the line-art options
   with pick buttons and notes, the build number, and a short list of decisions for the owner.

## The owner's brief (verbatim intent)

- The library: "iconic, beautiful, and well selected for coloring", all public domain, "and
  most importantly, very tasteful — I want users who see these options when they first open
  the app to think how cool my selection is." 15–20 photos, 20–30 paintings.
- The research picks some of those pictures as its test set.
- The options are narrowed by judgement: show the best few per picture, keep the rest one
  click away, not a wall of permutations.

## Authorization (given by the owner for this run)

- Push `claude/library-v2` and `claude/lineart-research` as often as needed; CI runs on both.
- **Merge `claude/library-v2` into `claude/paint-by-numbers-app` and push it** once its CI is
  green on iPad *and* iPhone (put `[iphone]` in the last commit message), the regression gate
  passes and `tools/strings_check.py` passes. That push builds and publishes the IPA. Merge
  `claude/paint-by-numbers-app` into `main` too (fast-forward; they are identical today).
  Never push a red build to `claude/paint-by-numbers-app`: if the library isn't green by
  morning, leave it on its branch and say exactly what is left.
- Publish private artifacts on claude.ai. No pull requests, no other repositories, no
  changes to the SideStore branch by hand.

## Branches

| Branch | From | Holds | Merged? |
| --- | --- | --- | --- |
| `claude/library-v2` | `claude/overnight-plan` | pictures, `Sample` model, credits, tests, CLAUDE.md | yes, into the app branch |
| `claude/lineart-research` | `claude/overnight-plan` | `research/lineart/` (Python), results index | never |

Large generated outputs (sheets, line maps, renders) are not committed; they go to the
scratchpad and into the artifacts. `research/lineart/` commits the scripts, a `README.md` on
how to rerun them, and `results.md` (what was tried, what worked, what failed, numbers).

## Order of work

```
Phase 0  Environment check, branches, corpus download tools                    (short)
Phase 1  Library: scout → verify licenses → test through pbn → curate          (the long pole)
         Line art: build the tooling and tune on Kodak + current samples        (in parallel)
Phase 2  Library: integrate into the app, CI loop until green                  (CI-bound)
         Line art: run on the research subset of the chosen library, narrow     (in parallel)
Phase 3  Merge + IPA, the morning page, final message
```

Phase 0 checks, before anything else: `huggingface.co`, `github.com` (release assets) and
the museum APIs below answer (`curl -sI`); `pip install numpy pillow opencv-python-headless
scikit-image onnxruntime torch --index-url …cpu` works; `tools/swift.sh build -c release
--static-swift-stdlib` builds `pbn`. If Hugging Face or GitHub is blocked, the learned models
in `lineart.md` are skipped and the morning page says so; everything else still runs.

## Agents

This plan is written for one orchestrator session (it reads this file, owns both branches,
the CI loop, the merges and the morning page) that fans out to subagents. Keep it under ten
agents in total. A shape that works:

| Agent | Phase | Brief |
| --- | --- | --- |
| Paintings scout | 1 | `library.md` § Scouting, paintings: a longlist of ~50 with sources and license evidence |
| Photo scout | 1 | `library.md` § Scouting, photos: a longlist of ~35 |
| License auditor | 1 | adversarial: re-verify every longlisted item from the source page itself; reject on any doubt |
| Line-art tooling | 1–2 | `lineart.md` stage 1, classical and learned families |
| Color layer and renders | 2 | `lineart.md` stage 2 and the panels |
| App integration | 2 | `library.md` § App changes, in a worktree on `claude/library-v2` |

The orchestrator does the taste work itself: the final curation of the library, and the
narrowing of line-art options. It looks at every image it ships or shows (Read tool on the
files), not just at metrics.

## Morning page

One artifact (load the `artifact-design` skill; the pick buttons and notes need the
`artifact-capabilities` skill, a page that keeps state the orchestrator can read back with
`ArtifactData`). Sections, in this order:

1. **The new library.** The build number and how to update in SideStore. A contact sheet of
   every picture in shipping order, each with title, creator, year and credit line; for each,
   its Relaxed template preview. Under it, the 8–12 alternates that nearly made it, each with a
   one-line reason it didn't, and a "swap in" pick so the owner can change the selection.
2. **Line art.** Per test picture, the narrowed options side by side; a toggle between the
   three panels (lines alone, painting plan, finished); a pick button and a notes field per
   option; "more variants" collapsed. Then the cross-picture verdict: which family looks most
   promising and why, and where every family fails.
3. **Decisions for the owner**, at most five, each answerable in a sentence.

Finish with a short final message in the session: the build number, the artifact link, and
anything that didn't get done.

## Done means

- The library ships in a green build on `claude/paint-by-numbers-app` (or, if not, the reason
  and the branch state are on the morning page).
- Every shipped picture has a provenance record and a license that `library.md` accepts.
- No existing painting changes: old artworks that came from the six former samples still open
  and still regenerate.
- The line-art research is reproducible from `research/lineart/README.md`.
- The morning page is published and its pick buttons work.
