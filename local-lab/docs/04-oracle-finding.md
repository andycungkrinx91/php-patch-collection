# The Scanner Oracle: Why a Fixed Host Still Returns HTTP 502

Read this before interpreting any `VULNERABLE` result from the scanner. It is the
single most misread output this lab produces.

---

## The observation

After applying the upstream fix and confirming the patched binary is the one
actually serving requests, the scanner still reported:

```
[VULNERABLE] http://10.77.77.208/index.php - Status: 502 - SAPI: PHP-FPM
```

The host was patched. The hash of the running binary matched the hash of the
binary that had been built from patched source. The PHP version string was
unchanged. By every measure the fix was applied — and the scanner still said
vulnerable.

---

## What is actually happening

The fix for CVE-2026-109618 / CVE-2026-109619 works by **refusing to continue**
when it detects the corrupted state the vulnerability creates. The refusal is
implemented through:

```c
/* Zend/zend_alloc.c:403 */
ZEND_NORETURN void zend_mm_safe_error_ex(...)
{
    ...
    _exit(1);
}
```

`ZEND_NORETURN` tells the compiler this function does not return. `_exit(1)`
terminates the process **immediately**, without running cleanup handlers,
without unwinding, and without a core dump.

So when the probe trips the guard, the fix does exactly what it was written to do:
it kills the FPM worker rather than allowing the corrupted state to be used.

FPM sees a worker die without finishing its request. It cannot produce a response,
so the client gets **Bad Gateway**. The scanner interprets 502 as a crash, and a
crash is what it was built to detect. It reports `VULNERABLE`.

The scanner is not malfunctioning. Its signal is "did the worker die", and the
worker *did* die. The signal simply cannot distinguish the two reasons a worker
can die.

---

## The discriminator

The FPM log separates the two cases. This is the check that matters:

```bash
lxc exec <target> -- journalctl -u php8.1-fpm --no-pager -n 40
```

**Patched host — the fix working:**

```
WARNING: [pool www] child 412 exited with code 1 after 0.021 seconds from start
```

Exit code `1`. That is `_exit(1)` from the guard. No signal, no core dumped.

**Vulnerable host — memory corruption:**

```
WARNING: [pool www] child 412 exited on signal 11 (SIGSEGV) after 0.021 seconds from start
```

Signal 11. That is a segfault from the corruption the CVE causes.

| Log line | Meaning |
|---|---|
| `exited with code 1` | Guard tripped, worker terminated deliberately → **fix is working** |
| `exited on signal 11 (SIGSEGV)` | Memory corruption → **still vulnerable** |
| `exited on signal 6 (SIGABRT)` | Assertion or abort → inspect further |
| `core dumped` present | Crash, not a controlled exit → **still vulnerable** |

---

## Why the fix terminates instead of recovering

This is a deliberate engineering trade-off, not an oversight. Once memory
allocator state is corrupted, there is no safe way to continue: any subsequent
allocation could return a pointer into attacker-controlled memory. Attempting to
recover would trade a clean denial of service for a potential code-execution
primitive.

Terminating the worker is the conservative choice. FPM restarts it, the attacker
gets nothing, and the failure is loud rather than silent.

The upstream patch's own subject line says as much:

```
Avoid state corruption via bailout
Minimal mitigation for EOL version.
```

---

## Consequences for this lab

### 1. 502 alone is not a verdict

A 502 requires a log check before it is called a failure. Any scan summary that
reports 502 as vulnerable without reading the log is overstating its finding.

### 2. Absence of a crash is not proof of a fix

The scanner reports `NO SIGNAL` when nothing crashed. That means *no crash was
observed* — it does not mean the host is immune. A host that never reaches the
vulnerable code path (because a runtime cap rejected the request, for instance)
also produces `NO SIGNAL`. Those two situations are indistinguishable from the
scanner's output alone.

This is why the lab uses two independent evidence sources: the scanner's verdict,
and the confirmation that the patched binary is the one serving requests
(SHA-256 of the running binary versus the built binary).

### 3. The runtime caps mask the probe entirely

With `max_input_nesting_level = 20` and `max_input_vars = 200`, the probe is
rejected before it reaches the parser. The host returns 200 with a warning and the
scanner sees nothing. That is a mitigation working, but it is a different
mechanism from the source fix, and it should be reported as such — as a
mitigation, not as a patch.

---

## Reproducing the distinction

```bash
# 1. Confirm the patched binary is serving.
lxc exec php74-mitigation -- sha256sum /usr/sbin/php-fpm7.4
lxc exec php81-mitigation -- sha256sum /usr/sbin/php-fpm8.1

# 2. Confirm the version string is unchanged (the fix is a backport, not an upgrade).
lxc exec php74-mitigation -- /usr/sbin/php-fpm7.4 -v
lxc exec php81-mitigation -- /usr/sbin/php-fpm8.1 -v

# 3. Send the probe.
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  --data-binary @probe.bin http://10.77.77.128/index.php

# 4. Read the log. This is the step that produces the verdict.
lxc exec php74-mitigation -- tail -20 /var/log/php7.4-fpm.log
```

Step 4 deliberately reads the FPM error log rather than `journalctl`. The log
belongs to the pool under test, so an entry there is unambiguously from this run;
a journal query would also pick up unrelated restarts and make the exit code
impossible to attribute.

---

## Summary

| Evidence | Vulnerable | Patched |
|---|---|---|
| Scanner verdict | VULNERABLE | VULNERABLE |
| HTTP status | 502 | 502 |
| FPM log exit | signal 11 (SIGSEGV) | code 1 |
| Core dumped | yes | no |
| Running binary hash | pre-patch | post-patch |

The scanner cannot tell these apart. The log can. Use the log.
