#!/usr/bin/env python3
"""Drop a specific hunk from a per-file patch section.

Used when a hunk targets code that a given release simply does not contain
(for example the `buf_value` header-accumulation path that exists in PHP 5.5.38
but not in 5.5.9). Dropping such a hunk is a scoping decision, never a way to
silence a genuine conflict, and must be recorded in the coverage report.

Usage: drop_hunk.py <section.patch> <out.patch> <hunk_index_1_based> [more...]
"""

import re
import sys

HUNK = re.compile(r"^@@")


def drop(inp, outp, drop_idx):
    lines = open(inp, encoding="utf-8", errors="replace").read().splitlines(True)
    out, i, n, idx = [], 0, len(lines), 0
    while i < n:
        if HUNK.match(lines[i]):
            idx += 1
            if idx in drop_idx:
                i += 1
                while (
                    i < n
                    and not HUNK.match(lines[i])
                    and not lines[i].startswith("--- ")
                ):
                    i += 1
                continue
        out.append(lines[i])
        i += 1
    open(outp, "w", encoding="utf-8").write("".join(out))
    return idx


if __name__ == "__main__":
    inp, outp = sys.argv[1], sys.argv[2]
    idxs = {int(x) for x in sys.argv[3:]}
    total = drop(inp, outp, idxs)
    print(f"{inp}: hunks={total} dropped={sorted(idxs)} -> {outp}")
