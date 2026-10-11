# Play simulator mailbox, version 1

`factory/taste/play.py` defines the Driver protocol, move validation and settled-state schema.
`factory/taste/simctl.py` supplies the host half. The Mac session supplies a **Debug-only** Swift
play UI test; F24 adds no app code. The test launches the desired demo scene itself before hello.

## Swift UI-test contract

The simulator shares the host file system. The host starts
`xcrun xcodebuild test-without-building -xctestrun <file> -only-testing:<Target/Class/testMethod>`
with `TEST_RUNNER_PLAY_MAILBOX=<absolute host directory>` in its environment. Xcode passes this
to the test runner as **`PLAY_MAILBOX`**; the Swift test reads that variable. The host also selects
the simulator by UDID and disables parallel testing so there is just one mailbox consumer.

Use a fresh, empty directory outside the repository for each session. Both sides publish UTF-8
JSON **atomically**: write a temporary file in that directory, close it, then rename to the final
name. Ignore temporary files. Do not delete or overwrite published files: they are the wire log.
There is at most one outstanding move. Numbers start at **1**, increase by one, and are never
reused within a session, including after errors. Never resume a stopped runner in the old mailbox.

1. Launch the demo and wait for the screen to settle, then publish `hello.json`:
   `{"version":1,"state":{"screen":"painting","selected_paint":1,"filled_areas":[],"area_count":3}}`.
2. Poll for `move-1.json`, then `move-2.json`, etc. Each file contains the move object directly,
   with no envelope; validate it against [moves.schema.json](moves.schema.json).
3. Perform the move exactly once, wait for animations and painting work to settle, then publish
   `done-<n>.json`: `{"state":{"screen":"painting","selected_paint":1,"filled_areas":[1],"area_count":3}}`.
   Even `wait` and `screenshot` moves get an acknowledgement. `screenshot` just settles the
   screen; the host captures its PNG with `simctl io screenshot` after acknowledgement.
4. On failure publish `error-<n>.json`: `{"reason":"Area 4 does not exist"}`. The reason must be
   a nonempty string. Publish exactly one of done/error. A failed or timed-out move ends the
   host session, since it may already have changed the app. Do not retry it.
5. Keep the test alive polling for the next number until the host stops xcodebuild with SIGINT.
   Returning from the test while the host is awaiting hello or a move is a runner failure.

Envelope keys are exactly as above. `state` has exactly these fields (F17's schema):

| Field | Meaning |
| --- | --- |
| `screen` | String identifying the current screen |
| `selected_paint` | Positive integer paint number, or `null` |
| `filled_areas` | Array of unique positive integer area IDs, each at most `area_count` |
| `area_count` | Nonnegative integer total number of areas |

Area IDs start at 1. A `fill` uses the Debug hook's label point for that area. `tap` uses an exact
accessibility label. `drag` coordinates are **screenshot pixels**, origin top left, +y down;
the Swift side converts them to the UI test's point coordinates using the simulator screen scale.
`steps` is the number of drag interpolation steps. `wait.seconds` is nonnegative. Unknown moves,
missing/extra fields and invalid values produce an error with the reason, never a silent no-op.
The schema and examples in `factory/taste/README.md` describe all five variants.

## Host usage on the Mac

Build the Debug simulator app and UI tests first; pass the resulting .app and .xctestrun:

```sh
factory/taste/loop --run /root/factory-out/play-session --out /root/factory-out/play-host \
  play new --driver simctl --guardian moon --budget 100 \
  --app /path/PaintByNumber.app --xctestrun /path/Debug-iphonesimulator.xctestrun \
  --test PaintByNumberUITests/PlayTests/testMailbox \
  --device 'iPad Pro 13-inch (M5)' --appearance light --timeout 60 --video
```

The test selector above is the contract's example for the Mac session to implement. The default
device is CI's preferred 13-inch M5 iPad Pro (`ci/simulators.sh`). `--device` matches an available
device's name exactly in `simctl list devices --json`; duplicate names across runtimes fail with
the matching UDIDs rather than picking a runtime silently. An already booted device skips boot;
all devices wait for `bootstatus -b`. Appearance is `light` or `dark`. `--mailbox` optionally names
another fresh host directory; its default is `<out>/mailbox`. `--timeout` applies separately to
each command, initial hello and move acknowledgement. Guardian thinking has no deadline, but
the host checks runner liveness while waiting for replies.

`play new --driver simctl` stays in the foreground until completion or the move budget. It writes
the same `jobs/NNN/player-<guardian>.json` as F17 and automatically collects replies from the kit's
normal paths, including its single repair attempt. Dispatch those jobs using the kit's runners
in another process. `play jobs` can inspect the current job and `play report` can inspect records;
`play collect` is for the mock driver (the live host already collects). A blocked repair, mailbox
error, timeout, runner exit or Ctrl-C stops the runner and optional recorder. Run again with fresh
directories after interruption; preserved turns remain replayable. This host never calls a model.

All commands are argument arrays executed without a shell through `xcrun`, including xcodebuild.
`<out>/commands.jsonl` logs each argv and the mailbox environment override; per-command `.log`
files contain stdout/stderr. Screenshots are under `<out>/screenshots`, and optional video is
`<out>/video.mp4`: recording starts before the UI test and stops with **SIGINT** at session end
to finalize the movie. No simulator shutdown or app uninstall is performed.

The default `--driver mock` keeps F17's separate new/jobs/collect workflow and requires
`--recording`. Replay of either driver is offline and byte-identical:

```sh
factory/taste/loop --run /root/factory-out/play-session --out /root/factory-out/play-replay play replay
TMPDIR=/root/factory-out python3 -m unittest discover -s tools/factory -p test_simctl.py
```

Linux tests put a fake `xcrun` first on PATH. It handles both simctl and xcodebuild, records argv,
and serves scripted screenshots/states through this contract; they never invoke Apple's tools.
