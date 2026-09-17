#!/bin/zsh
# One-time setup: tools from the Brewfile, then the Xcode project.
set -euo pipefail
cd "$(dirname "$0")/.."
brew bundle --file Brewfile
xcodegen generate
echo "Open AndroidDeviceHub.xcodeproj, or run Scripts/run-debug.sh"
