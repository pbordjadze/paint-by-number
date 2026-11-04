#!/usr/bin/env bash
# The one place CI's Xcode is named: every macOS job runs this right after checkout, and it
# selects that Xcode for the job's later steps (DEVELOPER_DIR in $GITHUB_ENV).
#   ci/xcode.sh
# A runner image without it fails here, by name, rather than building with another Xcode. Its
# image is the workflows' `runs-on` label (`xcode-27`: GitHub's image for Xcode 27, on macOS 27;
# 27.1 is the first with the iPhone Duo's SDK and simulator, ci/duo.sh). The Metal toolchain is
# a separate download since Xcode 26: fetched here if the image lacks it (the app's shaders).
# ci/simulators.sh boots the iOS runtime of this Xcode's simulator SDK.
set -euo pipefail
VERSION=27.1
DIR="/Applications/Xcode_$VERSION.app/Contents/Developer"
[[ -d "$DIR" ]] || { echo "::error::Xcode $VERSION is not on this runner ($DIR); installed: $(ls -d /Applications/Xcode*.app 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"; exit 1; }
echo "DEVELOPER_DIR=$DIR" >> "${GITHUB_ENV:-/dev/null}"
export DEVELOPER_DIR="$DIR"
xcodebuild -version
if ! xcrun metal --version >/dev/null 2>&1; then
  echo "The Metal toolchain is missing: downloading it"
  xcodebuild -downloadComponent MetalToolchain
fi
