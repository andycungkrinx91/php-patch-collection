#!/usr/bin/env python3
"""Reduce a unified diff to N lines of hunk context.

Why: the CVE patches are generated against one point release, but the modified
statements inside a branch are stable while surrounding context drifts between
minors. Shrinking context keeps the patch an *exact* match (still valid under
`patch --fuzz=0`) while letting it apply across the whole minor range of a
branch. No fuzzy matching is introduced.

Usage: minimize_patch.py <in.patch> <out.patch> [context=1]
"""

import re
import sys

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def minimize(inp, outp, ctx=1):
    lines = open(inp, encoding="utf-8", errors="replace").read().splitlines(True)
    out = []
    i = 0
    n = len(lines)
    stats = {"hunks": 0, "kept": 0}
    while i < n:
        m = HUNK.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        # collect this hunk's body
        i += 1
        body = []
        while i < n and not HUNK.match(lines[i]) and not lines[i].startswith("--- "):
            body.append(lines[i])
            i += 1
        # trim leading/trailing context to ctx lines
        lead = 0
        while lead < len(body) and body[lead].startswith(" "):
            lead += 1
        trail = 0
        while trail < len(body) and body[len(body) - 1 - trail].startswith(" "):
            trail += 1
        start = max(0, lead - ctx)
        end = len(body) - max(0, trail - ctx)
        trimmed = body[start:end]
        old_count = sum(1 for text in trimmed if text[:1] in (" ", "-"))
        new_count = sum(1 for text in trimmed if text[:1] in (" ", "+"))
        old_start = int(m.group(1)) + (start - 0)
        new_start = int(m.group(3)) + (start - 0)
        # recompute the start line referenced by the kept block
        if start == 0:
            old_start = int(m.group(1))
            new_start = int(m.group(3))
        out.append(f"@@ -{old_start},{old_count} +{new_start},{new_count} @@\n")
        out.extend(trimmed)
        stats["hunks"] += 1
        stats["kept"] += len(trimmed)
    open(outp, "w", encoding="utf-8").write("".join(out))
    return stats


if __name__ == "__main__":
    ctx = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    st = minimize(sys.argv[1], sys.argv[2], ctx)
    print(f"hunks={st['hunks']} retained_lines={st['kept']} context={ctx}")
