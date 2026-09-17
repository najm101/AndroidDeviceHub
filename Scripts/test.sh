#!/bin/zsh
# Unit tests (package) and, with --ui, the UI tests through Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd Packages/ADHKit && swift test)
if [[ "${1:-}" == "--ui" ]]; then
  xcodegen generate --quiet
  xcodebuild -project AndroidDeviceHub.xcodeproj -scheme AndroidDeviceHub -derivedDataPath build/DerivedData \
    -destination 'platform=macOS' -only-testing:AndroidDeviceHubUITests test -quiet
fi
