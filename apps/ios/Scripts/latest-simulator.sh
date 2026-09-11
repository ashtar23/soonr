#!/bin/sh
# Prints the UDID of an available iPhone simulator on the newest iOS runtime.
# Runner images change device and runtime names, so the destination is resolved
# instead of hardcoded.
set -eu

xcrun simctl list devices available --json | python3 -c '
import json
import re
import sys

PREFERRED = ("iPhone 17 Pro", "iPhone 17", "iPhone")

devices = json.load(sys.stdin)["devices"]


def runtime_version(identifier):
    match = re.search(r"iOS-([\d-]+)$", identifier)
    if not match:
        return None
    return tuple(int(part) for part in match.group(1).split("-"))


candidates = []
for identifier, entries in devices.items():
    version = runtime_version(identifier)
    if version is None:
        continue
    for entry in entries:
        if entry["name"].startswith("iPhone"):
            candidates.append((version, entry["name"], entry["udid"]))

if not candidates:
    sys.exit("No available iPhone simulator found.")

newest = max(version for version, _, _ in candidates)
on_newest = [entry for entry in candidates if entry[0] == newest]

for wanted in PREFERRED:
    for _, name, udid in on_newest:
        if name == wanted or (wanted == "iPhone" and name.startswith("iPhone")):
            print(udid)
            sys.exit(0)
'
