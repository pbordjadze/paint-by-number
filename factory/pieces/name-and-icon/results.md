# Eyes, not masks: results (2026-10-17)

24 reviewers (low-effort subagents, as ORCHESTRATOR step 3), 138 findings, two blind coders (a smaller model), adjusted Rand index 0.844.

| Arm | Findings | Distinct checkable clusters (coder 1 / 2) | Redundancy | Unique clusters | Favorite |
|---|---|---|---|---|---|
| B plain, full pack | 35 | 20 / 18 | 0.66 / 0.71 | 7 / 4 | nose 4, workbench 2 |
| M charter, full pack | 34 | 23 / 22 | 0.50 / 0.56 | 3 / 3 | control 2, nose 2, shopwindow 1 |
| V plain, own view | 35 | 30 / 31 | 0.23 / 0.17 | 10 / 7 | workbench 4, control 1, shopwindow 1 |
| E charter, own view | 34 | 29 / 27 | 0.24 / 0.24 | 9 / 6 | workbench 2, control 1, nose 1, shopwindow 1 |

Permutation test (20,000 shuffles of the 24 reviewers across arms, distinct checkable clusters):
view effect +8 / +9 (p = 0.011 / 0.005); mask effect +1 / +0 (p = 0.41 / 0.53).

Sealed predictions:
- P1 E > V > M > B: no. V >= E > M > B; the mask added nothing on top of a view.
- P2 view matters more than mask: yes (V-B +10/+13 vs M-B +3/+4).
- P3 redundancy highest in B, lowest in E: half. Highest in B; lowest in V (E within 0.01-0.07).
- P4 E and V hold most unique clusters: yes (19 of 29; 13 of 20).
- P5 checkable share higher with views: no. 97-100% everywhere (the prompt demanded checkable findings: ceiling).
- P6 arms name different favorites: yes.
- P7 identical copies disagree on a favorite: yes (4 nose, 2 workbench).
- Counter-evidence (M >= V, or E no better than M): not met.

Reading: what a reviewer sees drives useful divergence; the persona adds nothing measurable once
the view is set. One piece, six reviewers per arm, model coders: a first result, not a law.
Glance test (glance/results.md): "Moonlight" under a moon icon read as sleep / moon-phase; "Paint by Mo…" under the same icons read as paint by numbers.
