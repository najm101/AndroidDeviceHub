#!/bin/zsh
# Asks a running Debug build to save PNGs of its windows (see App/Sources/Support/DebugSnapshotter.swift).
# Usage: Scripts/snapshot.sh [output-directory] [WIDTHxHEIGHT]
set -euo pipefail
out="${1:-${TMPDIR:-/tmp}/adh-snapshots}"
mkdir -p "$out"
request="$out${2:+|$2}"
swift - "$request" <<'SWIFT'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.najm101.AndroidDeviceApp.debugSnapshot"),
    object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true
)
SWIFT
sleep 2
ls -1 "$out"
