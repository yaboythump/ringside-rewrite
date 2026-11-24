#!/usr/bin/env python3
"""Removes the iCloud entitlements from the app (CI's upload, when the App Store profile doesn't
allow iCloud yet: the iCloud container has to be set up at developer.apple.com first).
Save sync then reports iCloud as unavailable; everything else is unchanged.
Usage: strip_icloud.py path/to/RetroDuo.entitlements
"""
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    entitlements = plistlib.load(f)
removed = [key for key in list(entitlements) if "icloud" in key or "ubiquity" in key]
for key in removed:
    del entitlements[key]
with open(path, "wb") as f:
    plistlib.dump(entitlements, f)
print("strip_icloud: removed %s" % (", ".join(removed) or "nothing"))
