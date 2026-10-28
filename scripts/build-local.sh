#!/bin/bash
# Builds and installs this fork on a Mac without Xcode (local branch only).
# Uses the swift.org 6.3.3 toolchain in ~/Developer/.toolchains because the Command Line Tools' SwiftPM is broken,
# and the macOS 26.5 SDK it is compatible with. Pass --install to replace /Applications/BetterWispr.app.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/Developer/.toolchains/swift-6.3.3.xctoolchain/usr/bin:$PATH"
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
app="$(./scripts/build-app.sh release | tail -1)"
if [[ "${1:-}" == --install ]]; then
    osascript -e 'quit app "BetterWispr"' 2>/dev/null || true
    sleep 1
    rm -rf /Applications/BetterWispr.app
    ditto "$app" /Applications/BetterWispr.app
    open /Applications/BetterWispr.app
    echo "Installed /Applications/BetterWispr.app"
else
    echo "$app"
fi
