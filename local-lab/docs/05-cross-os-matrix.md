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
