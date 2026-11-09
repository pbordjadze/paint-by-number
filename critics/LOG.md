# Critic log — Paint Now (claude/scratch-paint-now)

## 2026-11-09 · Plan

**Verdict: change it.** M1–M3 are the right order and the right size. The gating and M4 being cuttable would ship a 1.1 that is not whole.

1. **Split the gate.** "Ship it only when the drawing tools ship" holds back the whole release, because the drawing tools are not in the release yet. Gate only what needs them: the ✎ (M2) and Blank Page (M3). The Shelf (M1) and the Length chip (M4) ship in 1.1 with no gate. While the tools stay gated, the release Shelf's Your Own row shows no Blank Page and the bar shows no ✎. It must not show disabled items.
2. **M4 is not cuttable.** This plan removes the sliders, so the chip is the only way to change a painting's length. Without it, a painter who gets 406 areas on a 10-minute evening has no way out except Settings. If something has to give, ship M4 before M3.
3. **"Forms on paper" must be a wait, not a step.** It runs only as long as the generation takes. It ends on its own, nothing on it asks for a decision, and Cancel goes back to the Shelf. A cached or library picture should go almost straight to painting. If it always takes a few seconds, it is the old preview without its controls.
4. **Ask about free paintings before the picture forms.** One tap straight to painting means the Unlimited Paintings prompt for a fourth photo of the painter's own has to appear when they pick the photo. It must not appear after the forming or on the painting screen. Library pictures and Tonight's Picture never ask.
5. **Keep the ✎ visible on phones and spell out what it does.** Moving it into More on the narrowest phones hides the feature Paul is shipping it for. Shorten Undo's label or drop it to an icon first, and keep Hint and ✎ both in the bar. Its VoiceOver label is "Change". Add a hint ("Draw or erase lines in this painting") so the word isn't cryptic, the problem the earlier board had with "Paper". "Blank Page" (over plain "Blank") is the right call. Keep it.
