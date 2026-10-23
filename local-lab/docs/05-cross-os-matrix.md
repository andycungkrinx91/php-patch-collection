# Cross-OS Coverage Matrix

Which operating system is tested, by which harness, and what that test can and
cannot prove.

---

## Two independent harnesses

| Harness | Runs | Tests | Proves |
|---|---|---|---|
| **LXC lab** (`local-lab/`) | Full VMs on an isolated bridge | Patched binaries, runtime caps, live SAPI behaviour | The host is no longer exploitable |
| **Docker suite** (`test-cross-os-e2e.sh`) | Throwaway containers | Configuration drop-in lifecycle | The hardening drop-in applies and rolls back cleanly |

They answer different questions. The Docker suite is fast and runs on any machine
with Docker; it verifies the configuration path. The LXC lab is heavier and
verifies the actual mitigation.

A distribution appearing in one but not the other is not an inconsistency — it
reflects which question that platform needed answering.

---

## LXC lab matrix

| Target | Base | PHP | PHP SAPI | Config layout | Verification mode |
|---|---|---|---|---|---|
| `php-trusty-lxc` | Ubuntu 14.04 | 5.5.9 | fpm-fcgi | `/etc/php5/fpm/conf.d` | Patched binary |
| `php56-test-lxc` | Ubuntu 18.04 | 5.6.40 | fpm-fcgi | `/etc/php/5.6/fpm/conf.d` | Patched binary |
| `php-legacy-lxc` | Ubuntu 16.04 | 7.0.33 | fpm-fcgi | `/etc/php/7.0/fpm/conf.d` | Patched binary |
| `php71-test-lxc` | Ubuntu 18.04 | 7.1.33 | fpm-fcgi | `/etc/php/7.1/fpm/conf.d` | Patched binary |
| `bionic-test-lxc` | Ubuntu 18.04 | 7.2.24 | fpm-fcgi | `/etc/php/7.2/fpm/conf.d` | Patched binary |
| `php73-test-lxc` | Ubuntu 20.04 | 7.3.33 | fpm-fcgi | `/etc/php/7.3/fpm/conf.d` | Patched binary |
| `php74-mitigation` | Ubuntu 20.04 | 7.4.33 | fpm-fcgi | `/etc/php/7.4/fpm/conf.d` | Patched binary |
| `php80-mitigation` | Ubuntu 22.04 | 8.0.30 | fpm-fcgi | `/etc/php/8.0/fpm/conf.d` | Patched binary |
| `php81-mitigation` | Ubuntu 22.04 | 8.1.34 | fpm-fcgi | `/etc/php/8.1/fpm/conf.d` | Patched binary |

One target per PHP branch, 5.5 through 8.1. Every row is a branch we patched
ourselves, so every row reads PATCHED / NOT VULNERABLE / PASS. The 5.6, 7.1 and
7.3 hosts are clones of the 7.2 and 7.4 hosts: they inherit a working toolchain
without needing package access, and serve our build through a dedicated FPM pool
on a loopback port rather than the packaged socket.

PHP versions in the table are the values observed from the binary actually
serving, not from the host's default `php` CLI — on the clone hosts those are
different versions.

---

## Patch Architecture: Canonical Patches vs. Range-Portable Patches

The repository manages two distinct categories of patch files with dedicated file locations:

### 1. File Locations

- **Canonical Point-Release Patches**: Located in `cve-2026-109618-109619/php<ver>-cve-109618-109619.patch` (mirrored in `docker-image/` and `docker-image/patch-cve/`). Authored strictly against the latest official point release of each branch (`5.5.38`, `5.6.40`, `7.0.33`, `7.1.33`, `7.2.34`, `7.3.33`, `7.4.33`, `8.0.30`, `8.1.31`).
- **Range-Portable Patches**: Located in `cve-2026-109618-109619/tools/range-patches/` (mirrored in `local-lab/codebase/tools/range-patches/`). Includes 10 patches: `php5.5` through `php8.1` `.range.patch` plus `php7.4-cve-109618-109619.guardabsent.patch`. Engineered to span multiple point releases per major branch at strict `--fuzz=0`.

### 2. Core Differences

1. **Target Span**: Canonical patches target exactly one point release. Range patches target the entire minor spectrum of the branch (e.g. PHP 5.5: `5.5.9–5.5.38`; PHP 7.2: `7.2.10–7.2.34`; PHP 7.4: `7.4.3–7.4.33`; PHP 8.1: `8.1.2–8.1.34`).
2. **VM Dispatcher Generation**: Canonical patches directly modify the generated `Zend/zend_vm_execute.h` (34+ hunks), which breaks on earlier minors where opcodes shifted. Range patches drop all `zend_vm_execute.h` hunks, patch only `Zend/zend_vm_def.h` (4 hunks), and dynamically regenerate `zend_vm_execute.h` via `Zend/zend_vm_gen.php` on the target machine.
3. **Context Reduction**: Canonical patches use standard 3-line unified diff context. Range patches use 1-line context boundaries to prevent rejection from minor comment/whitespace shifts while preserving zero-fuzz integrity.
4. **Scoping Decisions**: In PHP 5.5, range patches omit the `buf_value` header accumulation hunk in `main/rfc1867.c` (absent before 5.5.38). In PHP 7.4, a `guardabsent` variant introduces missing `ZSTR_MAX_OVERHEAD` and `ZSTR_MAX_LEN` macros for PHP 7.4.3–7.4.10.
5. **Execution**: Canonical patches apply via `patch -p1 --fuzz=0`. Range patches are deployed via `tools/cve-range-patch.sh`, which automates patching, VM dispatcher regeneration, and asserts all 34 `zend_mm_safe_error_ex` sites are present.

---

## Scope: PHP 5.5 through 8.1

The collection targets **PHP 5.5 through 8.1 only**. Two separate reasons put
everything else outside the matrix.

**PHP 8.2 and above has no patch of ours.** The 8.2.34 → 8.2.35 security delta is
a 2,903-line change across 12 files that also *renames* the guard
(`zend_mm_safe_error` becomes `zend_mm_delayed_error` and friends). No minimal
portable backport can be derived from it, so 8.2+ is documented as out of scope
rather than claimed.

**The RHEL family has a vendor fix already.** Applying a third-party backport on a
package-managed host is redundant and risks conflicting with the vendor package.
The correct action there is `dnf update`, not this collection.

| Distribution | Status | Reason |
|---|---|---|
| RHEL 8 | Refused by the engine | Official errata: `ALSA-2026:87073` (php:8.2), `ALSA-2026:87080` (php:7.4) |
| RHEL 9 | Refused by the engine | Official errata: `ALSA-2026:87072` (php:8.2), `ALSA-2026:87079` (php:8.3) |
| AlmaLinux 8 / 9 | Refused by the engine | Rebuilds of RHEL; inherit the same fixes |
| Rocky Linux | Refused by the engine | Rebuild of RHEL |
| Oracle Linux | Refused by the engine | Rebuild of RHEL |
| Debian 12, Alpine 3.21 / 3.22, CentOS Stream 10 | Out of scope | Ship PHP 8.2+ only |

`universal-autopatch-*.sh` and `compile-and-patch-vm-cve.sh` **fail closed** on a
Red Hat family host: if `/etc/redhat-release` is present but the platform is not
CentOS, the script prints the reason and exits rather than guessing. CentOS is
kept because it shares the `dnf` path and is a legitimate EL-family target; the
Red Hat *alternatives* are what got narrowed, not the package manager.

CentOS Stream 9 remains reachable as a patch target — it runs PHP 8.0.30, which is
in range — but it needs its own toolchain to build against, so it is verified as
an OS-family check rather than as one of the nine branch rows.

---

## Docker suite matrix

`test-cross-os-e2e.sh` — each target verifies preview, apply, drop-in contents,
live FPM SAPI, and rollback.

| Target | Image | Repo source | Layout |
|---|---|---|---|
| `debian9` | `debian:9` | `archive.debian.org` (Stretch is EOL) | `/etc/php/7.0/fpm/conf.d` |
| `ubuntu18` | `ubuntu:18.04` | live | `/etc/php/7.2/fpm/conf.d` |
| `debian12` | `debian:12` | live | `/etc/php/8.1/fpm/conf.d` |
| `alpine` | `alpine:3.21` | live | `/etc/php81/conf.d` |
| `centos7` | `centos:7` | `vault.centos.org` (EOL) | `/etc/php.d` |
| `centos8` | `centos:8` | `vault.centos.org` (EOL) | `/etc/php.d` |
| `centos9` | `quay.io/centos/centos:stream9` | live | `/etc/php.d` |

```bash
cd cve-2026-109618-109619
./test-cross-os-e2e.sh all
```

### EOL repositories

Three targets sit on EOL distributions whose original mirrors no longer serve
packages. They must be repointed before any install succeeds:

| Target | Repoint to |
|---|---|
| `debian9` | `archive.debian.org` |
| `centos7` | `vault.centos.org/7.9.2009` |
| `centos8` | `vault.centos.org/8.5.2111` |

Without this, every install fails with a 404 on the repository metadata and the
test reports a failure that says nothing about the patch.

### CentOS 7 and in-range PHP

CentOS 7's vault ships **PHP 5.4.16**, which is outside the collection's
supported range (5.5–8.1). The autopatch engine detects this and refuses:

```
[ERROR] No supported legacy PHP runtime (5.5 through 8.1) detected on this system.
```

That is the engine behaving correctly — it declines to guess at an unsupported
runtime. To test CentOS 7 as a patch target rather than a capability check, an
in-range PHP must be installed first (for example from Remi). Without that, the
honest result for stock CentOS 7 is **out of range**, not pass and not fail.

---

## What the harnesses cannot prove

| Claim | Status |
|---|---|
| The patch applies at `--fuzz=0` | Proven by the build |
| The drop-in installs and rolls back | Proven by the Docker suite |
| The host no longer crashes on the probe | Proven by the LXC lab |
| The host is immune to all variants | **Not proven.** `NO SIGNAL` means no crash was observed |
| The patched binary is the one serving | Proven by hash comparison |
| Nothing else on the host changed | Proven only for the paths the scripts touch |

The distinction between "no crash observed" and "immune" matters and is not
papered over anywhere in the reports.
