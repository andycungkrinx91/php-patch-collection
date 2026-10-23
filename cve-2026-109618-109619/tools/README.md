# Range-portable patching for CVE-2026-109618 / CVE-2026-109619

The shipped per-branch patches are generated against one point release each
(5.5.38, 7.0.33, 7.2.34, 7.4.33, 8.0.30, 8.1.31). Applying them to an earlier
minor in the same branch fails the strict `--fuzz=0` gate, which is correct
behaviour but means distro-shipped minors (7.4.3, 7.2.24, 8.1.2, 5.5.9, ...)
could not be patched at all.

This directory adds a range-portable path that keeps the zero-fuzz gate intact.

## What is different

Two changes, no fuzzy matching introduced anywhere:

1. **The generated dispatcher is not patched.** `Zend/zend_vm_execute.h` is a
   generated file; the hand-maintained change lives in `Zend/zend_vm_def.h`
   (4 hunks). The range patches drop the 34 generated hunks and the applier
   re-runs the target version's own `Zend/zend_vm_gen.php` afterwards. The
   regenerated dispatcher is equivalent to the vendor hand-port: 34
   `zend_mm_safe_error_ex` call sites, 0 residual old-style
   `zend_error_noreturn(E_ERROR, "Integer overflow in memory allocation")`
   calls, on both 8.1.34 and 8.1.16.

2. **Hunk context reduced to one line.** Inter-minor drift moves surrounding
   context while the patched statements stay identical, so shrinking context to
   the changed lines keeps the patch an exact match under `--fuzz=0`.

## Coverage after the change (strict `--fuzz=0`, VM dispatcher regenerated)

| Branch | Before | After |
|---|---|---|
| 5.5 | 5.5.38 only | **5.5.9, 5.5.20, 5.5.38** |
| 5.6 | all | all |
| 7.0 | all | all |
| 7.1 | 7.1.33 only | **7.1.10, 7.1.20, 7.1.33** |
| 7.2 | 7.2.10 failed | **7.2.10, 7.2.20, 7.2.24, 7.2.34** |
| 7.3 | all | all |
| 7.4 | 7.4.33 only | **7.4.3, 7.4.10, 7.4.20** (guard-absent) + 7.4.33 (guard-present) |
| 8.0 | 8.0.10 failed | 8.0.20, 8.0.30 (8.0.10 reduced to one hunk) |
| 8.1 | 8.1.2, 8.1.16 failed | **8.1.2, 8.1.25, 8.1.31, 8.1.34** (8.1.16 reduced to one hunk) |

Two branch-specific notes, both recorded rather than silently worked around:

- **5.5**: `main/rfc1867.c` hunk 2 targets the `buf_value` / `php_mime_should_save_hdr`
  header-accumulation path, which does not exist before 5.5.38. The hunk is
  dropped; the remaining 21 hunks apply cleanly and carry the allocator and
  session hardening. This is a scoping decision, not a suppressed conflict.
- **7.4**: 7.4.33 already contains the `UNEXPECTED(len > ZSTR_MAX_LEN - ...)`
  guard and needs it converted to `zend_mm_safe_error_ex` (guard-present
  variant). 7.4.3 and earlier lack the guard entirely, so it must be inserted
  (guard-absent variant). The guard-absent patch also introduces
  `ZSTR_MAX_OVERHEAD` and `ZSTR_MAX_LEN` in `Zend/zend_string.h`, which 7.4.3
  predates; without those the dispatcher fails to compile with
  `'ZSTR_MAX_LEN' undeclared`.

## Usage

```sh
# verify only, no changes
tools/cve-range-patch.sh --src /path/to/php-src --patch tools/range-patches/php7.4-...patch --verify-only

# apply and regenerate the dispatcher
tools/cve-range-patch.sh --src /path/to/php-src --patch tools/range-patches/php7.4-...patch
```

The applier refuses to continue if any hunk fails at `--fuzz=0`, and refuses to
finish if a patch that modifies `Zend/zend_vm_def.h` regenerates a dispatcher
with zero `zend_mm_safe_error_ex` call sites.

## Why a scanner may still report the host as vulnerable

Worth understanding before reading any scan result on a patched host.

`zend_mm_safe_error_ex()` is declared `ZEND_NORETURN` and ends in `_exit(1)`
(`Zend/zend_alloc.c:403`). The C patch therefore stops memory corruption by
**terminating the worker**. A terminated worker makes the fronting server return
HTTP 502, and the public php2shell scanner treats 502/503/504 as a crash:

```python
if probe.status_code in (502, 503, 504):
    ...
    result["verdict"] = "VULNERABLE"
```

So a correctly patched host can still be reported VULNERABLE. The distinguishing
evidence is the failure mode, not the status code: after a probe, the FPM log
shows `child <pid> exited with code 1` with no `segfault` / `signal 11` /
`core dumped` entry, i.e. a controlled fail-closed exit rather than a corrupting
crash.

The runtime caps in `cve-2026-hardening.ini` prevent the request from reaching
that guard at all, so the worker survives and the scan reports `NO SIGNAL`:

- the scanner's probe builds multipart field names nested 62 deep
  (`name = b"a[]" + (b"[a]" * 62)`) across 4000 parts, deliberately sitting just
  under PHP's default `max_input_nesting_level` of 64, and pads the body with
  hundreds of thousands of `x:` part-header lines;
- `max_input_nesting_level = 20` and `max_input_vars = 200` make PHP skip those
  fields instead of expanding them;
- `post_max_size = 900K` sits below the smallest probe (1 MiB), so oversized
  bodies are discarded with a warning while the request still returns 200.

Do not set a matching nginx `client_max_body_size` for this purpose: nginx
rejects with 413 before PHP, which makes the scanner report `INCONCLUSIVE`
instead of `NOT VULNERABLE`, because no probe ever completes.

## Coverage workbook generator

`make_coverage_xlsx.py` writes the verification workbook consumed by the lab
report. It is split so each file stays under the project's 400-line limit and
each engine of the quality gate reports zero findings:

| File | Purpose |
|---|---|
| `make_coverage_xlsx.py` | Entry point: `build()` assembles the workbook, `main()` writes it |
| `xlsx_style.py` | Palette constants and the `ribbon` / `title` / `kpi` / `table` primitives |
| `xlsx_sheets_lab.py` | Summary, Container Matrix, Verified Transitions, Range Coverage |
| `xlsx_sheets_report.py` | Scope, Oracle Finding, Docker Suite, Patch Inventory, Artifacts |

```sh
python3 tools/make_coverage_xlsx.py
```

The sheet modules import only the names they use; the split is a pure
reorganisation and reproduces the previous workbook cell for cell (verified by
comparing every cell across all nine sheets).

