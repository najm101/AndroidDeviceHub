#!/bin/zsh
# Runs swift-format (bundled with Xcode) and SwiftLint (brew install swiftlint).
# SwiftLint warnings are reported but only errors fail; pass --strict to fail on warnings too.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift-format lint --recursive --strict App Packages/ADHKit/Sources Packages/ADHKit/Tests UITests
if command -v swiftlint >/dev/null; then
  swiftlint lint --quiet ${1:+"$1"}
else
  echo "SwiftLint isn't installed (brew install swiftlint); skipped."
fi
Scripts/check-deps.sh
