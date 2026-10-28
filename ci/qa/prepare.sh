#!/usr/bin/env bash
# Paint by Moonlight's preparation for QA explore, after the install and before the first launch.
#   ci/qa/prepare.sh <udid>
# Give Feedback's Send is the one thing the app sends off the device, and a Release build sends it
# for real: no feedback reaches the developers from a test session, as the relay's host resolves to
# nowhere on this runner, whose resolver the simulator shares (and the brief says never to send).
# Found in the source, so a moved endpoint stops the run instead of slipping past.
set -euo pipefail
UDID="$1"
HOST=$(sed -n 's#.*static let endpoint = URL(string: "https://\([^/"]*\).*#\1#p' \
  App/PaintByNumber/Features/Feedback/FeedbackUploader.swift)
if [[ -z "$HOST" ]]; then echo "::error::no host in FeedbackUploader.endpoint to block"; exit 1; fi
printf '127.0.0.1 %s\n::1 %s\n' "$HOST" "$HOST" | sudo tee -a /etc/hosts > /dev/null
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder || true
if curl -s -m 10 -o /dev/null "https://$HOST/"; then echo "::error::$HOST still answers"; exit 1; fi
echo "feedback relay blocked: $HOST"
# A photo for the create flow's picker.
xcrun simctl addmedia "$UDID" Tests/Corpus/parrots.jpg
