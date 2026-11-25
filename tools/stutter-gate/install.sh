#!/usr/bin/env bash
# Installs the stutter check's LaunchAgent (com.pbm.ipad-stutter-gate) on the Mac the iPad is wired to:
# gate.sh at 2:15 and 5:15 AM local time (ET), before the nightly TestFlight's 08:17 and 10:47 UTC tries.
# It runs from ~/pbm-out/stutter-gate/repo, which it first brings up to origin/main when that checkout is
# on main (a branch checked out there is left as it is, for trying a change). In Paul's GUI session, so
# Xcode can sign. Output: ~/pbm-out/stutter-gate/agent.log.
#   tools/stutter-gate/install.sh            install, or update, and load it
#   tools/stutter-gate/install.sh --remove   unload and delete it
set -euo pipefail
LABEL=com.pbm.ipad-stutter-gate
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
ROOT="$HOME/pbm-out/stutter-gate"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [[ "${1:-}" == --remove ]]; then rm -f "$PLIST"; echo "removed $LABEL"; exit 0; fi
[[ -d "$ROOT/repo/.git" ]] || git clone -q https://github.com/pbordjadze/paint-by-number.git "$ROOT/repo"
touch "$ROOT/.keep"
RUN='cd "$HOME/pbm-out/stutter-gate/repo" && git fetch -q origin main && { [ "$(git branch --show-current)" != main ] || git merge -q --ff-only origin/main; } && exec tools/stutter-gate/gate.sh'
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>-c</string><string>${RUN//&/&amp;}</string></array>
  <key>StartCalendarInterval</key><array>
    <dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>15</integer></dict>
    <dict><key>Hour</key><integer>5</integer><key>Minute</key><integer>15</integer></dict>
  </array>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>EnvironmentVariables</key><dict>
    <key>HOME</key><string>$HOME</string>
    <key>PATH</key><string>/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key><string>$ROOT/agent.log</string>
  <key>StandardErrorPath</key><string>$ROOT/agent.log</string>
</dict></plist>
PLIST
plutil -lint "$PLIST" > /dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $LABEL: $(launchctl print "gui/$(id -u)/$LABEL" | grep -m1 state)"
