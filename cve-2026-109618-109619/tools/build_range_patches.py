#!/usr/bin/env python3
"""Build and validate a range-portable CVE-2026-109618/109619 patch per branch.

Pipeline per branch:
  1. split the shipped per-branch patch into one section per target file
  2. drop the generated `Zend/zend_vm_execute.h` section (regenerated instead)
  3. reduce hunk context (default 1) so the patch stays an exact match while
     surviving inter-minor context drift
  4. run `patch -p1 --dry-run --fuzz=0` against every requested minor version

Usage: build_range_patches.py <branch>[,<branch>...] <ctx>
"""

import os
import re
import sys

sys.path.insert(0, "/tmp/ports")
import range_validate as rv

REPO = "/home/andycungkrinx/experiment/portofolio/data/php-patch-collection/cve-2026-109618-109619"
OUT = "/tmp/ports/rangecaps"
MINUS = re.compile(r"^--- (?:php-src-php-[^/]+|a)/(\S+)")

BRANCH_VERSIONS = {
    "5.5": ["5.5.9", "5.5.20", "5.5.38"],
    "5.6": ["5.6.10", "5.6.25", "5.6.40"],
    "7.0": ["7.0.10", "7.0.20", "7.0.33"],
    "7.1": ["7.1.10", "7.1.20", "7.1.33"],
    "7.2": ["7.2.10", "7.2.20", "7.2.24", "7.2.34"],
    "7.3": ["7.3.10", "7.3.20", "7.3.33"],
    "7.4": ["7.4.3", "7.4.10", "7.4.20", "7.4.33"],
    "8.0": ["8.0.10", "8.0.20", "8.0.30"],
    "8.1": ["8.1.2", "8.1.16", "8.1.25", "8.1.31", "8.1.34"],
}


def split_sections(branch, outdir):
    patch = os.path.join(REPO, f"php{branch}-cve-109618-109619.patch")
    os.makedirs(outdir, exist_ok=True)
    for old in os.listdir(outdir):
        os.remove(os.path.join(outdir, old))
    lines = open(patch, encoding="utf-8", errors="replace").read().splitlines(True)
    sections, i, n = [], 0, len(lines)
    while i < n:
        m = MINUS.match(lines[i])
        if m:
            j = i + 1
            while j < n and not MINUS.match(lines[j]):
                j += 1
            sections.append((m.group(1), lines[i:j]))
            i = j
            continue
        i += 1
    written = []
    for target, body in sections:
        name = target.replace("/", "__") + ".patch"
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as fh:
            fh.write("".join(body))
        written.append(target)
    return written


def build(branch, ctx):
    secdir = os.path.join(OUT, f"sections-{branch}")
    targets = split_sections(branch, secdir)
    text = rv.build_patch(secdir, ("zend_vm_execute", "zend_test", ".phpt"), ctx)
    return text, targets


def main():
    branches = sys.argv[1].split(",")
    ctx = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for branch in branches:
        text, targets = build(branch, ctx)
        hunks = text.count("\n@@ ") + (1 if text.startswith("@@ ") else 0)
        print(
            f"--- branch {branch}: files={len(targets)} hunks={hunks} ctx={ctx} (VM regenerate) ---"
        )
        for v in BRANCH_VERSIONS.get(branch, []):
            verdict, rc, failed = rv.validate(text, v)
            print(f"    {v:<8} {verdict:<6} rc={rc} failed_hunks={failed}")
            rows.append((branch, v, verdict, failed))
        outfile = os.path.join(OUT, f"php{branch}-cve-109618-109619.range.patch")
        with open(outfile, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"    wrote {outfile}")
    print("\n=== summary ===")
    for branch, v, verdict, failed in rows:
        print(f"  {branch:<5} {v:<8} {verdict:<6} failed={failed}")


if __name__ == "__main__":
    main()
