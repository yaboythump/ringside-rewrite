#!/usr/bin/env python3
"""Reject release-brand and icon packaging regressions before upload."""
import json
import plistlib
import re
import struct
from pathlib import Path
root = Path(__file__).resolve().parents[1]
ios = root / "ios"
config = (ios / "App.xcconfig").read_text()
assert "INFOPLIST_KEY_CFBundleDisplayName = AVYDRIX Play" in config
assert "PRODUCT_BUNDLE_IDENTIFIER = com.ctnetworkstudios.retroduo" in config
for source in (ios / "RetroDuo").glob("*.swift"):
    assert not re.search(r'(?:Text|navigationTitle)\("[^"\n]*2\.0', source.read_text()), source
icons = ios / "RetroDuo/Assets.xcassets/AppIcon.appiconset"
contents = json.loads((icons / "Contents.json").read_text())
icon = icons / contents["images"][0]["filename"]
data = icon.read_bytes()
assert data[:8] == b"\x89PNG\r\n\x1a\n"
w, h, depth, color = struct.unpack(">IIBB", data[16:26])
assert (w, h, depth, color) == (1024, 1024, 8, 2), "Icon must be 1024-square opaque RGB PNG"
privacy = plistlib.loads((ios / "RetroDuo/PrivacyInfo.xcprivacy").read_bytes())
assert privacy["NSPrivacyTracking"] is False
assert privacy["NSPrivacyCollectedDataTypes"] == []
project = (ios / "RetroDuo.xcodeproj/project.pbxproj").read_text()
assert "B4F000000000000000000001," in project
print("PASS: AVYDRIX Play branding, unchanged bundle ID, opaque 1024 icon and bundled privacy manifest")
