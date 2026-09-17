#!/usr/bin/env python3
"""Convert the Android SDK device definition XMLs into the JSON bundled by HardwareProfiles.

Usage:
    Scripts/generate-hardware-profiles.py [path/to/sdklib.core.jar]

The jar ships with Android cmdline-tools (lib/sdklib/sdklib.core.jar). It is only needed
when refreshing the bundled profiles; the app itself never needs Java or cmdline-tools.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET
import zipfile

FILES = ["devices.xml", "nexus.xml", "wear.xml", "tv.xml", "automotive.xml", "desktop.xml", "xr.xml"]
DENSITY_BUCKETS = {"ldpi": 120, "mdpi": 160, "tvdpi": 213, "hdpi": 240, "xhdpi": 320,
                   "xxhdpi": 480, "xxxhdpi": 640}
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "Packages/ADHKit/Sources/HardwareProfiles/Resources/hardware-profiles.json")


def text(node, path, default=None):
    found = node.find(path)
    return found.text.strip() if found is not None and found.text else default


def density(value):
    if value.endswith("dpi") and value[:-3].isdigit():
        return int(value[:-3])
    return DENSITY_BUCKETS[value]


def form_factor(source, tag, name, diagonal, is_foldable):
    if tag:
        for prefix, factor in [("android-wear", "wear"), ("android-tv", "tv"), ("google-tv", "tv"),
                               ("android-automotive", "automotive"), ("android-desktop", "desktop"),
                               ("android-xr", "xr"), ("ai-glasses", "xr")]:
            if tag.startswith(prefix):
                return factor
    if is_foldable:
        return "foldable"
    if diagonal >= 7.0 or "tablet" in name.lower():
        return "tablet"
    return "phone"


def parse(source, root):
    for device in root.findall("device"):
        hw = device.find("hardware")
        screen = hw.find("screen")
        name = text(device, "name")
        diagonal = float(text(screen, "diagonal-length", "0"))
        is_foldable = hw.find("screen/foldable-region") is not None or hw.find("hinge") is not None
        tag = text(device, "tag-id")
        ram = hw.find("ram")
        ram_mib = int(float(ram.text.strip())) * (1024 if ram.get("unit") == "GiB" else 1)
        cameras = [text(c, "location") for c in hw.findall("camera")]
        api = text(device, "software/api-level", "")
        min_api, _, max_api = api.partition("-")
        yield {
            "id": text(device, "id", name),
            "name": name,
            "manufacturer": text(device, "manufacturer", ""),
            "formFactor": form_factor(source, tag, name, diagonal, is_foldable),
            "tagID": tag,
            "playStore": text(device, "playstore-enabled", "false") == "true",
            "diagonalInches": diagonal,
            "widthPixels": int(text(screen, "dimensions/x-dimension")),
            "heightPixels": int(text(screen, "dimensions/y-dimension")),
            "density": density(text(screen, "pixel-density")),
            "isRound": text(screen, "screen-shape", "") == "round" or "round" in name.lower(),
            "ramMiB": ram_mib,
            "hasHardwareKeyboard": text(hw, "keyboard", "nokeys") != "nokeys",
            "hasHardwareButtons": text(hw, "buttons", "soft") == "hard",
            "hasDPad": text(hw, "nav", "nonav") == "dpad",
            "hasFrontCamera": "front" in cameras,
            "hasBackCamera": "back" in cameras,
            "skin": text(hw, "skin"),
            "minAPI": int(min_api) if min_api.isdigit() else None,
            "maxAPI": int(max_api) if max_api.isdigit() else None,
            "isFoldable": is_foldable,
            "source": source,
        }


def main():
    jar = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk")),
        "cmdline-tools/latest/lib/sdklib/sdklib.core.jar")
    profiles = []
    with zipfile.ZipFile(jar) as archive:
        for name in FILES:
            root = ET.fromstring(archive.read(f"com/android/sdklib/devices/{name}"))
            for element in root.iter():  # files use different schema versions; ignore namespaces
                element.tag = element.tag.rsplit("}", 1)[-1]
            profiles.extend(parse(name.removesuffix(".xml"), root))
    seen, unique = set(), []
    for profile in profiles:
        if profile["id"] not in seen:
            seen.add(profile["id"])
            unique.append(profile)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as out:
        json.dump(unique, out, indent=2, sort_keys=True)
        out.write("\n")
    print(f"wrote {len(unique)} profiles to {os.path.relpath(OUT, REPO)}")


if __name__ == "__main__":
    main()
