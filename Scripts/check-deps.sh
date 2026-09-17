#!/bin/zsh
# Enforces the module layering rules on import statements.
# Package.swift already prevents most violations; this also catches `@testable`/`public import` slips.
set -euo pipefail
cd "$(dirname "$0")/../Packages/ADHKit/Sources"

features=(${(f)"$(ls -d *Feature | sed 's|/||')"})
infrastructure=(SDKLocator SDKCatalog SDKInstaller AVDStore HardwareProfiles SetupChecks EmulatorRuntime
  EmulatorGRPC ADBClient ADBRuntime ScrcpyClient DeviceControllers)
failed=0

for feature in $features; do
  for other in $features $infrastructure; do
    [[ "$other" == "$feature" ]] && continue
    if grep -rEn "^(@testable |public |package |internal )?import $other\$" "$feature" >/dev/null; then
      echo "✘ $feature imports $other"
      grep -rEn "^(@testable |public |package |internal )?import $other\$" "$feature"
      failed=1
    fi
  done
done

for domain in SDKDomain DeviceDomain; do
  for other in $features $infrastructure SwiftUI AppKit; do
    if grep -rEn "^(public )?import $other\$" "$domain" >/dev/null; then
      echo "✘ $domain imports $other"
      failed=1
    fi
  done
done

(( failed == 0 )) && echo "✔ Module dependency rules hold"
exit $failed
