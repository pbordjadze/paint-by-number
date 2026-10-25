#!/usr/bin/env bash
# The one place CI's Xcode is named: every macOS job runs this right after checkout, and it
# selects that Xcode for the job's later steps (DEVELOPER_DIR in $GITHUB_ENV).
#   ci/xcode.sh
# A runner image without it fails here, by name, rather than building with another Xcode.
# ci/simulators.sh boots the iOS runtime of this Xcode's simulator SDK.
set -euo pipefail
VERSION=26.6
DIR="/Applications/Xcode_$VERSION.app/Contents/Developer"
[[ -d "$DIR" ]] || { echo "::error::Xcode $VERSION is not on this runner ($DIR); installed: $(ls -d /Applications/Xcode*.app 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"; exit 1; }
echo "DEVELOPER_DIR=$DIR" >> "${GITHUB_ENV:-/dev/null}"
DEVELOPER_DIR="$DIR" xcodebuild -version
