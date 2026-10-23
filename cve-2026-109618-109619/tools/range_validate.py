#!/usr/bin/env python3
"""Range validation for CVE-2026-109618/109619 branch patches.

Builds a range-oriented patch from a set of per-file sections, optionally
reduces hunk context, then runs `patch -p1 --dry-run --fuzz=0` against every
requested PHP minor version. Strict gate: PASS requires rc==0 and zero FAILED.

Pure stdlib; downloads php.net release tarballs into a cache dir.
"""

import os
import re
import subprocess
import sys
import tarfile
import urllib.request

CACHE = "/tmp/ports/dl"
WORK = "/tmp/ports/rvwork"
PHP_DIST_URL = "https://www.php.net/distributions/php-{version}.tar.gz"
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def fetch(version):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"php-{version}-rel.tar.gz")
    if os.path.exists(path) and os.path.getsize(path) > 1_000_000:
        return path
    url = PHP_DIST_URL.format(version=version)
    try:
        with urllib.request.urlopen(url, timeout=600) as r, open(path, "wb") as f:
            f.write(r.read())
    except Exception as exc:
        print(f"  {version}: download failed ({exc})")
        return None
    return path


def minimize(text, ctx):
    """Keep `ctx` lines of context around each hunk's changed lines."""
    lines = text.splitlines(True)
    out, i, n = [], 0, len(lines)
    while i < n:
        m = HUNK.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        old_start, new_start = int(m.group(1)), int(m.group(3))
        i += 1
        body = []
        while i < n and not HUNK.match(lines[i]) and not lines[i].startswith("--- "):
            body.append(lines[i])
            i += 1
        lead = 0
        while lead < len(body) and body[lead].startswith(" "):
            lead += 1
        trail = 0
        while trail < len(body) and body[len(body) - 1 - trail].startswith(" "):
            trail += 1
        head = max(0, lead - ctx)
        tail = len(body) - max(0, trail - ctx)
        kept = body[head:tail]
        if not kept:
            kept = body
            head = 0
        oc = sum(1 for text in kept if text[:1] in (" ", "-"))
        nc = sum(1 for text in kept if text[:1] in (" ", "+"))
        out.append(f"@@ -{old_start + head},{oc} +{new_start + head},{nc} @@\n")
        out.extend(kept)
    return "".join(out)


def build_patch(sections_dir, exclude_substrings, ctx=None):
    parts = []
    for name in sorted(os.listdir(sections_dir)):
        if not name.endswith(".patch"):
            continue
        if any(s in name for s in exclude_substrings):
            continue
        with open(
            os.path.join(sections_dir, name), encoding="utf-8", errors="replace"
        ) as fh:
            parts.append(fh.read())
    text = "".join(parts)
    return minimize(text, ctx) if ctx is not None else text


def validate(patch_text, version):
    tgz = fetch(version)
    if not tgz:
        return "FETCH_FAIL", 0, 0
    os.makedirs(WORK, exist_ok=True)
    target = os.path.join(WORK, f"php-{version}")
    subprocess.run(["rm", "-rf", target], check=False)
    try:
        with tarfile.open(tgz) as tf:
            tf.extractall(WORK)
    except Exception as exc:
        return f"EXTRACT_FAIL({exc})", 0, 0
    if not os.path.isdir(target):
        return "DIR_MISSING", 0, 0

    pfile = os.path.join(WORK, f"candidate-{version}.patch")
    with open(pfile, "w", encoding="utf-8") as fh:
        fh.write(patch_text)
    proc = subprocess.run(
        ["patch", "-p1", "--dry-run", "--fuzz=0", "--forward", "-i", pfile],
        cwd=target,
        capture_output=True,
        text=True,
    )
    failed = proc.stdout.count("FAILED") + proc.stderr.count("FAILED")
    verdict = "PASS" if (proc.returncode == 0 and failed == 0) else "FAIL"
    subprocess.run(["rm", "-rf", target], check=False)
    return verdict, proc.returncode, failed


if __name__ == "__main__":
    sections_dir = sys.argv[1]
    branch = sys.argv[2]
    versions = sys.argv[3].split(",")
    ctx = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    patch_text = build_patch(sections_dir, ("zend_vm_execute",), ctx)
    hunks = patch_text.count("\n@@ ") + (1 if patch_text.startswith("@@ ") else 0)
    print(
        f"branch={branch} ctx={ctx} hunks={hunks} (VM execute excluded -> regenerate)"
    )
    for v in versions:
        verdict, rc, failed = validate(patch_text, v)
        print(f"  {branch:>4}  {v:<8} {verdict:<6} rc={rc} failed_hunks={failed}")
