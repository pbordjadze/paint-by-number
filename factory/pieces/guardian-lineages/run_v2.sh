#!/bin/bash
# usage: run_v2.sh <id> [steps]   one codex exec, low effort; attaches only the guardian's silhouette
set -u
id=$1; steps=${2:-"1 2 3"}; n=$(echo $steps | wc -w); pf=${PROMPT:-$id}
d=~/lineages/v2/out/$id; mkdir -p "$d"; cp ~/lineages/v2/refs/$id-shape.png "$d/shape.png"
{ cat <<P
Use the built-in image_gen tool (imagegen skill, built-in mode). Make EXACTLY $n image_gen calls, one for each of these steps: $steps. No more, no retries, then stop. Do not write code and do not post-process the images beyond copying them. Copy each result to $d/step-<N>.png (overwrite). Attached: shape.png, the guardian's silhouette.

P
cat ~/lineages/v2/prompts/_rule.md; echo; cat ~/lineages/prompts/_plate.md; echo; cat ~/lineages/v2/prompts/$pf.md
echo; echo 'Finish with one line: "done".'
} > "$d/prompt.txt"
cd "$d" && /usr/bin/time -f "%e s" ~/.local/bin/codex exec --json --ephemeral -s workspace-write --skip-git-repo-check --cd "$d" \
  -m gpt-6.1-sol -c model_reasoning_effort='"low"' -c approval_policy='"never"' \
  --image "$d/shape.png" - < "$d/prompt.txt" > "$d/events.jsonl" 2> "$d/stderr.txt"
echo "exit $? ; $(tail -1 $d/stderr.txt)"; ls -la "$d"/step-*.png
