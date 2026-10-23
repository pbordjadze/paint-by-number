# Guardian lineages: the pilot

Paul, October 23, 2026: "a single frame mock-up of every single guardian, but rethemed to look
more like an ancient version of them", not all the way back to the oldest, but "some kind of
metaphorical like lens applied to each of them, so that the visually I want them to all be very
different, but metaphorically I want the same shift to have happened to each of them ... a few
jumps like that to where the lineage is traceable and kind of makes sense". For the four in the
pilot: "I would like to see all 4 steps rendered as a new image."

Mock-ups only. Nothing here changes the app, the Marginarium, a charter or a name.

## The rule

- Exactly three jumps back along a line of influence. A jump is a real link (a cited influence,
  someone who championed them, a teacher, a tradition that grew out of another), or it is
  labelled *spiritual* when no documented tie was found.
- The guardian's silhouette, pose or emblem stays; medium, palette, era and texture come from
  wherever the step lands.
- Every step is the same catalogue plate (`plate.py`): one backdrop, one light, one framing, and a
  typeset label (guardian, step, medium, date) with the trail so far. The label is set by script,
  not drawn by the image model.
- Plate 0 is today's guardian re-made as a new image, with its approved drawing beside it
  (`pet-<id>.webp` on `main`, first frame). This is one reading of "all 4 steps"; the page asks
  Paul to say if he meant four jumps instead.

## The pilot

`lineages.json` holds the four chains, each jump's link, kind and source. In short:

- **Eno** ← Cage (cited) ← Satie (championed) ← plainchant (teacher, then tradition)
- **Dino** ← Charles R. Knight (cited) ← the Crystal Palace dinosaurs (spiritual, with a bridge)
  ← *Duria Antiquior* (spiritual)
- **Scherenschnitt** ← the Chat Noir shadow theatre (spiritual) ← Séraphin's ombres chinoises
  (tradition) ← Chinese piying (tradition, by name). The often-told story that Reiniger loved
  Chinese shadow puppets as a child has no primary source, so it isn't used.
- **The Moon** ← the computus (tradition) ← Babylonian lunar reckoning (probable) ← Sin's crescent
  and Nusku's lamp on a kudurru (same tradition, older)

Hedge Witch is skipped in any full run: Paul is keeping her for a real woodcut by his mum.

## How it was made (October 23)

- Sources: one Claude research agent, then Claude checked the gaps (Séraphin's figures; Uruk's
  drawn tablets).
- Images: Codex (gpt-6.1-sol, low effort), one run per guardian, four image generations each,
  with the approved drawing attached. Prompts: `prompts/` (`_plate.md` is shared by all).
- Redos (one each at most): Dino II and III came out as the same blue-green modern plesiosaur as
  plate 0, so they were redrawn without the reference image, described in words; Moon I had Arabic
  numerals on an 11th-century wheel, redrawn with Roman ones. First passes kept as `*.first.webp`.
- 19 image generations in all.
- `build_page.py` makes the contact sheet. Paul's reactions go through the pets-page server
  (tailnet :8445, `/lineages/`) to `~/pets-drafts/picks.jsonl` on lenovo-homelab, as picks named
  `lineage-<id>`.
