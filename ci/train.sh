#!/usr/bin/env bash
# The night train: several small, reviewed branches through one full CI run, then into main as
# one push (CLAUDE.md › CI feedback loop › The night train). Run by the conductor session.
#   ci/train.sh make <name> <branch>...   merge each branch into claude/train-<name>, fresh from
#                                         origin/main, and push it (one full CI run)
#   ci/train.sh who <name> <path>...      which boarded branch changed each path (a red train's
#                                         failing file or test)
#   ci/train.sh land <name>               fast-forward main to the train once its report is green
# Branches are named without `origin/`. A branch that conflicts with the train so far is left
# off, and said so; the train goes without it.
set -euo pipefail
die() { echo "train: $*" >&2; exit 1; }
fetch() {
  # Explicit refspecs: a session's clone may track only some branches.
  local specs=() ref
  for ref in "$@"; do [[ "$ref" == +* ]] && specs+=("$ref") || specs+=("+refs/heads/$ref:refs/remotes/origin/$ref"); done
  for wait in 2 4 8 16; do git fetch -q origin "${specs[@]}" && return 0; sleep "$wait"; done
  die "can't fetch $*"
}
push() { for wait in 2 4 8 16; do git push "$@" && return 0; sleep "$wait"; done; die "can't push $*"; }

[[ $# -ge 2 ]] || die "usage: ci/train.sh make|who|land <name> …"
CMD="$1" NAME="$2"; shift 2
TRAIN="claude/train-$NAME"

boarded() {
  # "<merge sha> <branch>" for each branch the train carries, in boarding order.
  git log --first-parent --merges --reverse --format='%H %s' "origin/main..origin/$TRAIN" \
    | sed -nE 's/^([0-9a-f]+) Merge ([^ ]+) \(night train .*$/\1 \2/p'
}

case "$CMD" in
  make)
    [[ $# -ge 1 ]] || die "name the branches to board"
    fetch main "$@"
    [[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "the working tree has changes"
    git checkout -q -B "$TRAIN" origin/main
    on=() off=()
    for branch in "$@"; do
      if git merge-base --is-ancestor "origin/$branch" origin/main; then
        off+=("$branch (already in main)"); continue
      fi
      # The branch's last commit carries its review notes (CLAUDE.md › Working with Paul); the
      # merge keeps them, as a solo merge's message would, without the tags that steer CI: the
      # train's last merge is the commit CI reads them from.
      notes="$(git log -1 --format=%B "origin/$branch" \
        | sed -E -e 's/\[(compile|iphone|ipa|skip ci|ci skip|no ci|skip actions|actions skip)\]//gI' \
          -e '/^skip-checks: ?true$/Id' | sed -zE 's/\[test [^]]*\]//gI')"
      if git merge -q --no-ff -m "Merge $branch (night train $NAME)"$'\n\n'"$notes" "origin/$branch" > /dev/null 2>&1; then
        on+=("$branch")
      elif git rev-parse -q --verify MERGE_HEAD > /dev/null; then
        git merge --abort
        off+=("$branch (conflicts with main and ${on[*]:-nothing else})")
      else
        off+=("$branch (git refused to merge it: untracked files in the way?)")
      fi
    done
    [[ ${#on[@]} -gt 0 ]] || die "nothing boarded: ${off[*]}"
    push -q -f -u origin "$TRAIN"
    echo "train $TRAIN at $(git rev-parse HEAD): ${on[*]}"
    for branch in "${off[@]}"; do echo "left off: $branch"; done
    echo "wait: CI_BRANCH=$TRAIN ci/fetch.sh $(git rev-parse HEAD) <outdir>"
    ;;
  who)
    [[ $# -ge 1 ]] || die "name the paths"
    fetch main "$TRAIN"
    # A path names the branches that changed that file, or anything under that directory.
    for path in "$@"; do
      found=""
      while read -r merge branch; do
        if git diff --name-only "$merge^1" "$merge" | awk -v p="${path%/}" '$0 == p || index($0, p "/") == 1 { hit = 1 } END { exit !hit }'; then
          found+=" $branch"
        fi
      done < <(boarded)
      echo "$path:${found:- no boarded branch changed it}"
    done
    ;;
  land)
    fetch main "$TRAIN"
    git fetch -q origin "+refs/ci-shots/$TRAIN:refs/ci-shots/$TRAIN" 2> /dev/null || die "no report for the train yet"
    tip="$(git rev-parse "origin/$TRAIN")"
    [[ "$(git show "refs/ci-shots/$TRAIN:COMMIT")" == "$tip" ]] || die "no report for the train's tip $tip yet"
    # The job lines come first; the details below the blank line repeat the jobs' names.
    status="$(git show "refs/ci-shots/$TRAIN:STATUS.md" | sed '/^$/q')"
    grep -qE '^ipad: success$' <<< "$status" && grep -qE '^ipad-ui: success$' <<< "$status" \
      || die "the train's run isn't a green full run:"$'\n'"$status"
    bad="$(grep -E '^(core|ipad|ipad-ui|iphone|compile|ipa): ' <<< "$status" | grep -vE ': (success|skipped)$' || true)"
    [[ -z "$bad" ]] || die "the train's run isn't green:"$'\n'"$bad"
    # GitHub skips a push whose head commit's message has a skip tag anywhere, even quoted.
    message="$(git log -1 --format=%B "$tip")"
    ! grep -qiE '\[(skip ci|ci skip|no ci|skip actions|actions skip)\]|^skip-checks: ?true$' <<< "$message" \
      || die "the train's tip message has a skip tag: main would get no CI run; make it again"
    git merge-base --is-ancestor origin/main "$tip" \
      || die "main moved since the train was made; make it again"
    carried="$(boarded | cut -d' ' -f2 | tr '\n' ' ')"
    push -q origin "$tip:refs/heads/main"
    echo "main is $tip, carrying: $carried"
    ;;
  *) die "unknown command $CMD (make, who, land)" ;;
esac
