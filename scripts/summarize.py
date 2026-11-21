#!/usr/bin/env python3
"""Prints the per-case results of one job as Markdown.

Usage: summarize.py <out dir>

Reads the JSON line each case wrote (`app/results/*.json`, or the copy from the
app container in `app-documents/results/`). Nothing here interprets the
results beyond printing them: "loupe views" are classes whose name contains
loupe, magnif or lollipop; "session" is whether UITextLoupeSession.begin
returned an object.
"""
import glob
import json
import os
import sys

out = sys.argv[1]
SIZES = [17, 48, 96, 150, 220]
KINDS = ["textview", "textfield", "session-widget", "session-nil"]

results = {}
for directory in ("app/results", "app-documents/results"):
    for path in sorted(glob.glob(os.path.join(out, directory, "*.json"))):
        name = os.path.basename(path)[:-5]
        if name in results:
            continue
        try:
            with open(path) as handle:
                results[name] = json.loads(handle.read().strip().splitlines()[-1])
        except (OSError, ValueError, IndexError) as error:
            results[name] = {"case": name, "error": str(error)}

if not results:
    print("(no per-case results found)")
    sys.exit(0)

ios = next((r.get("ios") for r in results.values() if r.get("ios")), "?")
print(f"iOS {ios}, {len(results)} of {len(SIZES) * len(KINDS)} cases wrote a result\n")


def cell(result):
    if result is None:
        return "no result"
    if "error" in result:
        return "unreadable"
    if result["kind"].startswith("session"):
        returned = result.get("sessionReturned")
        if returned is None:
            return "session not started"
        return "session returned" if returned else "**session nil**"
    if not result.get("gestureObserved"):
        return "gesture not seen by app"
    return "loupe view seen" if result.get("loupeSeen") else "no loupe-named view"


print("### By font size\n")
print("| font | " + " | ".join(KINDS) + " |")
print("|---|" + "---|" * len(KINDS))
for size in SIZES:
    cells = [cell(results.get(f"{kind}-{size}")) for kind in KINDS]
    print(f"| {size} pt | " + " | ".join(cells) + " |")

print("\n### Per case\n")
print("| case | caret h | caret rect | session | loupe-named classes | other new classes | gesture seen |")
print("|---|---|---|---|---|---|---|")
for kind in KINDS:
    for size in SIZES:
        name = f"{kind}-{size}"
        r = results.get(name)
        if r is None:
            print(f"| {name} | | | | | | no result |")
            continue
        rect = r.get("caretRect")
        rect_text = "{:.0f},{:.0f},{:.0f}x{:.0f}".format(*rect) if rect else ""
        session = r.get("sessionReturned")
        session_text = "" if session is None else ("returned" if session else "nil")
        loupe = ", ".join(r.get("loupeClasses", [])) or "none"
        added = r.get("addedClasses", {})
        added_text = ", ".join(f"{k}x{v}" for k, v in sorted(added.items())) or "none"
        gesture = r.get("gestureObserved")
        gesture_text = "" if gesture is None else ("yes" if gesture else "no")
        print(f"| {name} | {r.get('caretHeight', '')} | {rect_text} | {session_text} | {loupe} | {added_text} | {gesture_text} |")
