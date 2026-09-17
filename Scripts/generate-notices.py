#!/usr/bin/env python3
"""Writes App/Resources/ThirdPartyNotices.md from Package.resolved and the license files of the checkouts.

Run after `swift package resolve` (Scripts/test.sh does that): python3 Scripts/generate-notices.py
"""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
package = root / "Packages/ADHKit"
checkouts = package / ".build/checkouts"
pins = json.loads((package / "Package.resolved").read_text())["pins"]

def license_text(folder: pathlib.Path) -> str:
    parts = []
    for name in ["LICENSE", "LICENSE.txt", "LICENSE.md", "NOTICE.txt", "NOTICE"]:
        path = folder / name
        if path.exists():
            parts.append(path.read_text(errors="replace").strip())
    return "\n\n".join(parts) or "License file not found."

out = [
    "# Third-Party Notices",
    "",
    "Android Device App uses the following open source software.",
    "",
    "## Android Emulator gRPC definitions",
    "",
    "`Packages/ADHKit/Protos/emulator` (from the Android SDK emulator package), "
    "Copyright The Android Open Source Project, licensed under the Apache License 2.0.",
    "The generated device frames are drawn by the app; no Android Studio artwork is included.",
    "",
]
for pin in sorted(pins, key=lambda p: p["identity"]):
    folder = next((c for c in checkouts.iterdir() if c.name.lower() == pin["identity"].lower()), None)
    out += [
        f"## {pin['identity']} {pin['state'].get('version', pin['state'].get('revision', ''))}",
        "",
        pin["location"],
        "",
        "```",
        license_text(folder) if folder else "Checkout not found; run `swift package resolve`.",
        "```",
        "",
    ]
(root / "App/Resources/ThirdPartyNotices.md").write_text("\n".join(out))
print(f"Wrote notices for {len(pins)} packages")
