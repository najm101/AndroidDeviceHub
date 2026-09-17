#!/bin/zsh
# Builds the Debug app and (re)launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project AndroidDeviceHub.xcodeproj -scheme AndroidDeviceHub -configuration Debug \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' build -quiet
pkill -x "Android Device App" 2>/dev/null || true
sleep 0.5
open "build/DerivedData/Build/Products/Debug/Android Device App.app"
