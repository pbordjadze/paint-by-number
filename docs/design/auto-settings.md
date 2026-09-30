# Automatic generation settings ("Auto")

Status: proposed. Lands after build 68 (after the compile fixes, the open review fixes and
localization).

## Goal

A photo becomes the best template it can be with no decisions from the user. The create
preview opens on settings chosen for that photo; the Colors, Detail and Smoothness sliders stay
available under "Adjust" for anyone who wants them. Today every photo starts from the same
defaults (24 colors, detail 0.5), which suits some photos and not others: a flat still life
needs fewer paints, a busy portrait more detail around the face.

## What it decides

- `colorCount` (6–150), `detail` and `smoothness` in `GenerationSettings`.
- Region count is not a knob of its own: it follows from those three, so Auto controls it
  through them and scores it directly.

## Approach

It lives in PaintCore (`AutoSettings`), not on Metal. The pipeline runs on the CPU, the
decision is a small search over pipeline runs, and keeping it in PaintCore means it is
portable, deterministic, and testable on Linux CI (`pbn generate --auto`). Vision keeps
supplying the importance map (subjects, faces) as it does now.

1. **Analyze the photo** with data the pipeline already computes: how many OKLab clusters the
   palette histogram needs to reach a target ΔE, edge and texture density (`StructureMap`,
   `TextureMap`), and how much of the frame the important subject covers.
2. **Narrow to a few candidates** from those features, for example 3 color counts × 2 detail
   levels at the smoothness the texture suggests.
3. **Run each candidate in the preview regime** (about 700 px, about 100 ms each on the CI's
   M1), in parallel and cancellable.
4. **Score each candidate:**
   - fidelity: importance-weighted mean and 95th-percentile ΔE;
   - paintability: region count, estimated painting time (`PaintingTime.estimate`), smallest
     label room, tiny regions;
   - calm: share of low-contrast boundaries (banding) and slivers, the failure modes the
     segmentation research targets.
   The objective is the best fidelity within a painting-time budget. The budget is the one
   user preference Auto needs: Settings › Painting length (Quick, Relaxed, Detailed).
5. **Generate the winner at full detail**, exactly as a manual choice would be.

## App behaviour

- The preview shows the first candidate at once and swaps to the winner when scoring finishes,
  so Auto never makes the flow feel slower.
- Moving any slider leaves Auto; a Reset control returns to it.
- Saved artworks record the chosen values and that they came from Auto. Regeneration and
  re-tuning reuse the recorded values, so a stored painting never changes under the user.

## Validation

- `tools/regression.py` gains an `auto` regime. The baseline records the settings Auto picks
  per sample, so a change in its choices shows up in review.
- Acceptance on the corpus (bundled samples plus the evaluation photos): every Auto template
  passes the hard invariants; Auto stays within the painting-time budget; against the fixed
  defaults it has equal or lower importance-weighted ΔE at equal or fewer regions on most
  photos. The contact sheets are checked by eye, since metrics alone miss taste.
- Determinism: the same photo and preference always give the same settings on every device.

## Risks and open questions

- Older devices run the pipeline several times slower. The candidate count must adapt, and
  the time to first preview must not regress.
- Tuning the scoring to the corpus could overfit. The corpus needs more variety first:
  portraits, pets, landscapes, night scenes and low-contrast photos.
- Whether one painting-length preference is enough, or whether "more colors" and "less
  detail" are distinct wishes that need their own control.
