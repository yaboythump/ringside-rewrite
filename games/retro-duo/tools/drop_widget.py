#!/usr/bin/env python3
"""Leaves the home screen widget out of a build (CI's upload, when Apple won't let it sign the
widget): removes the widget target from the project's targets and the app's dependencies and
"Embed Foundation Extensions" phase. Edits the project file in place; the app's widget-sharing
code stays and is harmless without the widget.
Usage: drop_widget.py path/to/project.pbxproj
"""
import re
import sys

APP_TARGET = "B10000000000000000000002"
PROJECT = "B10000000000000000000001"


def object_line(text, object_id):
    match = re.search(r"^\s*" + object_id + r" = \{.*\};$", text, re.M)
    if not match:
        sys.exit("drop_widget: %s not found" % object_id)
    return match


def remove_from_list(text, object_id, field, values):
    match = object_line(text, object_id)
    line = match.group(0)
    list_match = re.search(field + r" = \(([^)]*)\)", line)
    items = [item.strip() for item in list_match.group(1).split(",") if item.strip()]
    kept = [item for item in items if item not in values]
    new_line = line[:list_match.start(1)] + ", ".join(kept) + line[list_match.end(1):]
    return text[:match.start()] + new_line + text[match.end():]


path = sys.argv[1]
text = open(path).read()
target = re.search(r"^\s*([0-9A-F]{24}) = \{isa = PBXNativeTarget;[^\n]*name = RetroDuoWidget;", text, re.M)
if not target:
    print("drop_widget: no widget target; nothing to do")
    sys.exit(0)
widget = target.group(1)
dependencies = re.findall(r"^\s*([0-9A-F]{24}) = \{isa = PBXTargetDependency; target = " + widget + ";", text, re.M)
embeds = re.findall(r'^\s*([0-9A-F]{24}) = \{isa = PBXCopyFilesBuildPhase;[^\n]*name = "Embed Foundation Extensions";', text, re.M)
text = remove_from_list(text, PROJECT, "targets", [widget])
text = remove_from_list(text, APP_TARGET, "dependencies", dependencies)
text = remove_from_list(text, APP_TARGET, "buildPhases", embeds)
open(path, "w").write(text)
print("drop_widget: built without the home screen widget (target %s)" % widget)
