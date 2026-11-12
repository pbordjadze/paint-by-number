#!/usr/bin/env bash
# The performance tour with no UI test driving it: launches the installed app in a demo scenario, lets
# it play, and keeps its -tourLog (painting-company row 292). A UI test's accessibility queries cost
# the app frames of their own, so these are the numbers a change is judged by.
#   tools/perf-tour/run.sh device|simulator <udid> <outdir> [-b <bundle id>] [-n <runs>]
#                          [-r <delay>,<seconds>] [-t <template>] [-k] [scenario...]
# The app must be installed already, a build with the demo scenarios in (Debug, or ReleaseTests:
# tools/checks.sh). On a device it must be unlocked, on power, with nothing else in front.
# Scenarios (default: all), each launched <runs> times (default 3), one after the other:
#   launch            the empty gallery: the process's start to the first refresh the app answers
#   forming           the create flow makes a painting of the first fixed picture (`create-preview`), its
#                     line-art maps from the demo launches' cache: PaintCore's share alone
#   forming-cold      the same with the cache off: the models and Vision run, as for a painter's own photo
#   start             the same, then Start Painting taps itself: the hand-off into the painting, the
#                     making-of off (the app's default)
#   start-making-of   the same with Settings > The Making-of on: the show plays to its end
#   zen-30            thirty fills in Zen Mode, a tap's and a drag's in turn (`paint-zen-30`)
#   finish            the last fill, the flight to the whole painting and night falling (`paint-nightfall`)
# Launch arguments override the app's stored settings for that launch only; nothing stored is changed.
# -r records each run with Instruments (xctrace, every process) from <delay> seconds after its launch,
# for <seconds>: keep it short on a device (a recording takes about 70 MB of its storage a second
# until it restarts). -t names the template (default: Animation Hitches, which carries a Time
# Profiler). tools/perf-tour/stacks.py reads each trace into <scenario>-<run>.stacks.txt, and the
# trace is then deleted unless -k keeps it. Recording costs the app time: judge frames by the
# unrecorded runs.
# Results: <outdir>/<scenario>-<run>.tsv (the log), .meta (the Mac's load, times), and summary.txt
# (tools/perf-tour/summary.py on every log). A device's app is left open as its owner opens it, with no demo.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIND="$1"; UDID="$2"; OUT="$3"; shift 3
BUNDLE=com.pbordjadze.paintbynumber; RUNS=3; RECORD=""; TEMPLATE="Animation Hitches"; KEEP=0
while getopts "b:n:r:t:k" flag; do
  case "$flag" in
    b) BUNDLE="$OPTARG" ;;
    n) RUNS="$OPTARG" ;;
    r) RECORD="$OPTARG" ;;
    t) TEMPLATE="$OPTARG" ;;
    k) KEEP=1 ;;
    *) sed -n '2,20p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
SCENARIOS=("$@"); [[ ${#SCENARIOS[@]} -eq 0 ]] && SCENARIOS=(launch forming forming-cold start start-making-of zen-30 finish)
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

# <scenario> -> the launch arguments and how long it plays (seconds).
plan() {
  case "$1" in
    launch)          ARGS=(-demo gallery-empty); PLAY=10 ;;
    forming)         ARGS=(-demo create-preview -demoFixedPictures YES); PLAY=25 ;;
    forming-cold)    ARGS=(-demo create-preview -demoFixedPictures YES -demoColdMaps YES); PLAY=45 ;;
    start)           ARGS=(-demo create-preview -demoFixedPictures YES -demoStart YES -playsMakingOf NO); PLAY=28 ;;
    start-making-of) ARGS=(-demo create-preview -demoFixedPictures YES -demoStart YES -playsMakingOf YES); PLAY=75 ;;
    zen-30)          ARGS=(-demo paint-zen-30 -zenMode YES); PLAY=106 ;;
    finish)          ARGS=(-demo paint-nightfall); PLAY=22 ;;
    *) echo "unknown scenario: $1"; exit 2 ;;
  esac
  ARGS+=(-tourLog YES)
}
launch() {
  if [[ "$KIND" == device ]]; then
    xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE" -- "$@"
  else
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
    xcrun simctl launch "$UDID" "$BUNDLE" "$@"
  fi
}
# On a device the next launch ends this one (and the last scenario's is ended by a plain launch).
close() {
  [[ "$KIND" == device ]] || xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
  return 0
}
# The app's tmp folder, copied to <dir>: its tour logs, one per process.
fetch() {
  mkdir -p "$1"
  if [[ "$KIND" == device ]]; then
    xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
      --source tmp --destination "$1" > /dev/null 2>&1
  else
    cp "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"/tmp/tour-log-*.tsv "$1"/ 2>/dev/null
  fi
}
SEEN="$OUT/.seen"; mkdir -p "$SEEN"
# The create scenarios read their picture's line-art maps from the demo launches' cache: one launch
# that fills it, not measured (a device's caches go when its storage runs low).
if [[ " ${SCENARIOS[*]} " == *" forming "* || " ${SCENARIOS[*]} " == *" start"* ]]; then
  plan forming
  launch "${ARGS[@]}" > "$OUT/warm-up.launch.log" 2>&1 || echo "the warm-up launch failed: see $OUT/warm-up.launch.log"
  sleep 45
  close
  sleep 2
fi
fetch "$SEEN"   # logs of earlier launches are not this run's
for scenario in "${SCENARIOS[@]}"; do
  plan "$scenario"
  for run in $(seq 1 "$RUNS"); do
    name="$scenario-$run"
    echo "load-before $(sysctl -n vm.loadavg) $(date +%s)" > "$OUT/$name.meta"
    launch "${ARGS[@]}" > "$OUT/$name.launch.log" 2>&1 || echo "launch failed: see $OUT/$name.launch.log"
    echo "launched $(date +%s) ${ARGS[*]}" >> "$OUT/$name.meta"
    if [[ -n "$RECORD" ]]; then
      rm -rf "$OUT/$name.trace"
      ( sleep "${RECORD%,*}"
        xcrun xctrace record --device "$UDID" --template "$TEMPLATE" --all-processes --output "$OUT/$name.trace" \
          --time-limit "${RECORD#*,}s" > "$OUT/$name.xctrace.log" 2>&1 ) &
      echo "recording $TEMPLATE from ${RECORD%,*} s for ${RECORD#*,} s" >> "$OUT/$name.meta"
    fi
    sleep "$PLAY"
    wait
    echo "load-after $(sysctl -n vm.loadavg) $(date +%s)" >> "$OUT/$name.meta"
    close
    sleep 2
    fetch "$OUT/.tmp-$name"
    new=""
    for log in $(find "$OUT/.tmp-$name" -name 'tour-log-*.tsv' 2>/dev/null); do
      [[ -n "$(find "$SEEN" -name "$(basename "$log")" 2>/dev/null)" ]] || new="$log"
    done
    if [[ -n "$new" ]]; then
      cp "$new" "$OUT/$name.tsv"
      cp "$new" "$SEEN/"
      pid="$(basename "$new" .tsv)"; pid="${pid#tour-log-}"
      echo "pid $pid" >> "$OUT/$name.meta"
      if [[ -d "$OUT/$name.trace" ]]; then
        python3 "$HERE/stacks.py" "$OUT/$name.trace" "$OUT/$name.tsv" --pid "$pid" > "$OUT/$name.stacks.txt" 2>&1
        [[ $KEEP == 1 ]] || rm -rf "$OUT/$name.trace"
      fi
    else
      echo "no tour log for $name (was the app built with the demo scenarios, and unlocked?)" | tee -a "$OUT/$name.meta"
    fi
    rm -rf "$OUT/.tmp-$name"
    echo "$name: $(tail -1 "$OUT/$name.meta")"
  done
done
# No demo is left playing: the app as its owner opens it, then (in a simulator) closed.
[[ "$KIND" == device ]] && xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE" > /dev/null 2>&1
python3 "$HERE/summary.py" "$OUT"/*.tsv > "$OUT/summary.txt" 2>&1
cat "$OUT/summary.txt"
