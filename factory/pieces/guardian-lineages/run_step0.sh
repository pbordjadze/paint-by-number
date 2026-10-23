#!/bin/bash
# usage: run_step0.sh <id> "<medium>"   one codex exec, one image: today's guardian re-made as a real object
set -u
id=$1; medium=$2; d=~/lineages/batch2/out/$id; mkdir -p "$d"; cp ~/lineages/batch2/refs/$id-frame.png "$d/approved.png"
{ cat <<P
Use the built-in image_gen tool (imagegen skill, built-in mode). Make EXACTLY ONE image_gen call, no retries, then stop. Do not write code and do not post-process the image beyond copying it. Copy the result to $d/step-0.png.

The attached image approved.png is this guardian's approved drawing. Make it as a real object, faithful to the drawing: the same subject, pose, colours, details and character (where it has a face, keep it, made as that medium would really make it). Medium: $medium.

P
cat ~/lineages/prompts/_plate.md; echo; echo 'Finish with one line: "done".'
} > "$d/prompt.txt"
cd "$d" && ~/.local/bin/codex exec --json --ephemeral -s workspace-write --skip-git-repo-check --cd "$d" \
  -m gpt-6.1-sol -c model_reasoning_effort='"low"' -c approval_policy='"never"' \
  --image "$d/approved.png" - < "$d/prompt.txt" > "$d/events.jsonl" 2> "$d/stderr.txt"
echo "$id exit $? $(ls $d/step-0.png 2>/dev/null)"
