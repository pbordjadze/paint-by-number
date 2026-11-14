#!/usr/bin/env bash
# Two builds measured turn about in one sitting (painting-company row 292): the frozen build and the new one,
# a run of every scenario each, three times over, so both meet the same machine at the same hour.
#   side-by-side.sh device|simulator <udid> <outdir> <frozen.app> <new.app> [-p <passes>] [scenario...]
# Runs tools/perf-tour/run.sh -i <app> -n 1 for each build in each pass (frozen first), into
# <outdir>/frozen/<pass> and <outdir>/new/<pass>, then prints compare.py's table (also <outdir>/compare.txt).
# The Mac's load is noted before each run (<outdir>/load.txt).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run.sh"
KIND="$1"; UDID="$2"; OUT="$3"; FROZEN="$4"; NEW="$5"; shift 5
PASSES=3
if [[ "${1:-}" == -p ]]; then PASSES="$2"; shift 2; fi
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
: > "$OUT/load.txt"
status=0
for pass in $(seq 1 "$PASSES"); do
  for build in frozen new; do
    app="$FROZEN"; [[ $build == new ]] && app="$NEW"
    echo "$build $pass $(date '+%H:%M:%S') $(sysctl -n vm.loadavg)" >> "$OUT/load.txt"
    "$RUN" "$KIND" "$UDID" "$OUT/$build/$pass" -i "$app" -n 1 "$@" > "$OUT/$build-$pass.out" 2>&1 || { status=1; echo "$build pass $pass: a run was missing its segment (see $OUT/$build-$pass.out)"; }
  done
done
python3 "$HERE/compare.py" "$OUT" | tee "$OUT/compare.txt"
exit $status
