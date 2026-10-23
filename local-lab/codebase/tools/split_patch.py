#!/usr/bin/env python3
"""Split a multi-file unified diff into one patch per target file.

The Ubuntu security patch is a `git format-patch` mail whose file sections are
delimited by `--- a/<path>` / `+++ b/<path>` pairs (no `diff --git` lines), so
boundaries are detected on that pair.
"""

import os
import re
import sys

MINUS = re.compile(r"^--- a/(\S+)")
PLUS = re.compile(r"^\+\+\+ b/(\S+)")


def split(patch_path, outdir):
    os.makedirs(outdir, exist_ok=True)
    with open(patch_path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()

    sections = []
    i = 0
    preamble = []
    n = len(lines)
    while i < n:
        m = MINUS.match(lines[i])
        if m and i + 1 < n and PLUS.match(lines[i + 1]):
            target = m.group(1)
            start = i
            j = i + 2
            while j < n:
                if MINUS.match(lines[j]) and j + 1 < n and PLUS.match(lines[j + 1]):
                    break
                j += 1
            sections.append((target, lines[start:j]))
            i = j
            continue
        if not sections:
            preamble.append(lines[i])
        i += 1

    index = []
    for target, body in sections:
        name = target.replace("/", "__") + ".patch"
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as fh:
            fh.write("".join(body))
        index.append((target, name, sum(1 for text in body if text.startswith("@@"))))

    with open(os.path.join(outdir, "INDEX.tsv"), "w", encoding="utf-8") as fh:
        for target, name, hunks in index:
            fh.write(f"{target}\t{name}\t{hunks}\n")
    return index


if __name__ == "__main__":
    idx = split(sys.argv[1], sys.argv[2])
    for target, name, hunks in idx:
        print(f"{hunks:>3}  {target}")
    print(f"total files: {len(idx)}, total hunks: {sum(h for _, _, h in idx)}")
