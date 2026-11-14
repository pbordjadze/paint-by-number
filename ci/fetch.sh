#!/usr/bin/env bash
# Waits for the CI report of a commit and extracts it.
#   [CI_BRANCH=<pushed-branch>] [CI_RUN=<run id>[.<attempt>]] ci/fetch.sh [<commit-sha>] [<outdir>]
#   (defaults: HEAD, ./ci-report)
# The report (published by .github/workflows/ci.yml to the ref refs/ci-shots/<branch>, outside
# refs/heads) contains STATUS.md, logs (*.log, long ones trimmed), <job>/errors.txt, test results,
# screenshots under */shots/*.png and the quality regression under core/regression/
# (regression.txt, regression.json, sheets/*/*.jpg).
# Polls every 30 s for up to 180 min (a full run takes 30 on idle runners, up to 100 under load;
# main's iPhone jobs may each run 160). Run it in the background and read the report when done.
# A re-run of a commit (Re-run jobs, or a run started by hand on the same commit) finds the
# commit's earlier report at once: give CI_RUN the run id, with `.<attempt>` for a re-run of the
# same run (the run's URL and Re-run's attempt number), and only that run's report counts.
# Reports written before the RUN file existed never match a CI_RUN.
# A commit whose run gave way to a later push (a branch's run is cancelled by the next push; on
# main an entry that waits gives its turn to a newer push's) gets that push's report, which
# covers it, and a first line saying so; never with CI_RUN.
set -euo pipefail
SHA="$(git rev-parse "${1:-HEAD}")"
OUT="${2:-ci-report}"
BRANCH="${CI_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
REF="refs/ci-shots/${BRANCH}"
SEEN=
for _ in $(seq 1 360); do
  if git fetch -q origin "+${REF}:${REF}" 2>/dev/null; then
    RUN="$(git show "${REF}:RUN" 2>/dev/null || true)"
    COMMIT="$(git show "${REF}:COMMIT" 2>/dev/null || true)"
    LATER=
    if [[ -z "${CI_RUN:-}" && "$COMMIT" =~ ^[0-9a-f]{40}$ && "$COMMIT" != "$SHA" && "$COMMIT" != "$SEEN" ]]; then
      # Asked once for each report: the branch's history, to see whether this one's commit holds ours.
      SEEN="$COMMIT"
      git fetch -q origin "$BRANCH" 2>/dev/null || true
      if git merge-base --is-ancestor "$SHA" "$COMMIT" 2>/dev/null; then LATER=1; fi
    fi
    if [[ -n "$LATER" ]] || { [[ "$COMMIT" == "$SHA" ]] \
      && { [[ -z "${CI_RUN:-}" ]] || [[ "$RUN" == "$CI_RUN" || "${RUN%.*}" == "$CI_RUN" ]]; }; }; then
      if [[ -n "$LATER" ]]; then echo "The report of $COMMIT, a later push that holds $SHA: its run covers this commit."; fi
      rm -rf "$OUT" && mkdir -p "$OUT"
      git archive "${REF}" | tar -x -C "$OUT"
      cat "$OUT/STATUS.md"
      find "$OUT" -name errors.txt -size +0 -exec sh -c 'echo "== $1"; head -60 "$1"' _ {} \;
      find "$OUT" \( -name '*.png' -o -name '*.jpg' \) | sort
      exit 0
    fi
  fi
  sleep 30
done
echo "Timed out waiting for CI report of $SHA${CI_RUN:+ (run $CI_RUN)} on $REF" >&2
exit 1
