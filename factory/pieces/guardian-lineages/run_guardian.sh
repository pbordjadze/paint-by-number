#!/bin/bash
# usage: run_guardian.sh <id> [steps]   one codex exec, low effort, one image_gen per step (default 0 1 2 3)
set -u
id=$1; pf=${PROMPT:-$1}; steps=${2:-"0 1 2 3"}; n=$(echo $steps | wc -w)
d=~/lineages/out/$id; mkdir -p "$d"; cp ~/lineages/refs/$id-frame.png "$d/approved.png"
{ cat <<P
Use the built-in image_gen tool (imagegen skill, built-in mode). Make EXACTLY $n image_gen calls, one for each of these steps: $steps. No more, no retries, then stop. Do not write code and do not post-process the images beyond copying them. Copy each result to $d/step-<N>.png (overwrite). ${NOREF:+No image is attached: the guardian is described in words below. }${NOREF:-The attached image approved.png is} the guardian's approved drawing: it fixes ONLY the silhouette, pose and emblem that must stay recognizable at every step. Everything else (material, palette, technique, era, texture) comes from the step's own medium as described; do not carry the drawing's colours or rendering style into steps 1 to 3.

P
cat ~/lineages/prompts/_plate.md; echo; cat ~/lineages/prompts/$pf.md
echo; echo 'Finish with one line: "done".'
} > "$d/prompt.txt"
cd "$d" && /usr/bin/time -f "%e s" ~/.local/bin/codex exec --json --ephemeral -s workspace-write --skip-git-repo-check --cd "$d" \
  -m gpt-6.1-sol -c model_reasoning_effort='"low"' -c approval_policy='"never"' \
  $( [ -n "${NOREF:-}" ] || echo --image "$d/approved.png" ) - < "$d/prompt.txt" > "$d/events.jsonl" 2> "$d/stderr.txt"
echo "exit $? ; $(tail -1 $d/stderr.txt)"; ls -la "$d"/step-*.png
