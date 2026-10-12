# Pets run state (October 12, 2026)

The Codex-run Lamp's pets run (`factory/taste/codex_lamp.py`, run directory
`/root/factory-out/F36/lamp`), saved because Codex's usage limit paused it until October 18 and
the cloud container that held it can be reclaimed.

`pets-run-state.tar.gz` holds every text record (inputs, jobs, replies, decisions, provenance,
replays, the model comparison, costs, records of superseded steps) and each hatch's final
sprite sheets and validation reports. Left out: intermediate image generations, PNG copies of the
sheets, and preview animations.

State: steps 1 to 5 done (style 12 chosen 3–2; 20 briefs; set review). Step 6: Originality and
the Snow Queen validated; the Baba Yaga, the Hedge Witch, Medea, the Moon and the Robber Girl
failed their quality gates; the other 13 never started (usage limit). Step 7 not run.

Restore: `mkdir -p /root/factory-out/F36 && tar -xzf pets-run-state.tar.gz -C /root/factory-out/F36`,
then `python3 -m factory.taste.codex_lamp run /root/factory-out/F36/lamp --model gpt-6-astra
--compare gpt-6.1-sol --parallel 4 --image-workers 3` from `claude/vibe-factory`.
