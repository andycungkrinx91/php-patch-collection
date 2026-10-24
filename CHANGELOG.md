# Changelog

All notable changes to the PHP Core CVE Patch Collection will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-10-24

### Added
- **CVE-2026-115560 Mitigation Package**:
  - Unified C-source patches and standalone range patches covering PHP 5.5 through 8.4 (`cve-2026-115560/`).
  - Surgical key sanitization in `ext/session/session.c` restricting upload progress keys to `[a-zA-Z0-9_.-]` (length 1–128) and blocking serializer delimiters while preserving legitimate upload progress.
  - SAPI runtime hardening INI drop-in (`99-cve-2026-115560-hardening.ini`) disabling `session.upload_progress.enabled` with isolated configuration namespaces.
  - Perimeter defense snippet (`cve-2026-115560-hardening.conf`) dropping query string markers and blocking CRLF multipart boundary injection with HTTP 403.
  - Universal autopatch CLI driver (`universal-autopatch-115560.sh`) with `--preview`, `--apply`, `--rollback`, non-blocking SIGUSR2 reload, and FPM listen autodetection (TCP & UNIX sockets).
  - Cross-OS container regression harness (`test-cross-os-e2e.sh`) verifying Debian 12, Alpine Linux 3.21, and PHP 8.4 FPM.
  - Multi-stage Docker builder samples for Ubuntu 24.04 and Alpine Linux (`docker-image/`).
  - Dedicated tooling suite under `cve-2026-115560/tools/` enforcing strict per-CVE tooling isolation.
  - Formal audit reports published under `docs/test-report/`:
    - `cve-2026-115560_session-upload-progress_20261024.pdf`
    - `cve-2026-115560-coverage-metrix.xlsx`
    - `cve-2026-115560-patch-verify.pdf`
  - High-resolution SVG diagrams (`cve-115560-defense-in-depth.svg`, `autopatch-flow.svg`, `lab-topology.svg`).

### Changed
- **Multi-CVE Coexistence Analysis**:
  - Documented sequential patchability of CVE-109618-109619 and CVE-2026-115560 on shared PHP 8.1 trees without clobbering (`--fuzz=0`).
  - Isolated SAPI configuration drop-in filenames to prevent clobbering input nesting limits.

---

## [1.1.0] - 2026-10-24

### Added
- **Animated Architecture & Workflow Visuals**:
  - `autopatch-flow`: Responsive 6-stage lifecycle animation (WebP, GIF, SVG) modeling preview, FPM hardening, C-binary rebuild, and rollback branches.
  - `lab-topology`: Network containment architecture diagram illustrating `labbr0`, egress ACLs, and isolated attacker/target nodes.
  - `anbu-pentest-flow`: 5-phase controlled verification lifecycle diagram covering recon, vulnerability scanning, exploit QA, teardown, and 3-layer review gates.
- **Range-Portable Patching Toolchain**:
  - Added `tools/cve-range-patch.sh`, `range-patches/`, and Zend VM dispatcher regeneration scripts (`tools/build_range_patches.py`).
  - Enables clean application at strict `--fuzz=0` across distro-specific minor releases (PHP 5.5.9, 7.2.24, 7.4.3, 8.1.2) by patching `Zend/zend_vm_def.h` and regenerating `zend_vm_execute.h`.
- **Differential Module Verification**:
  - Documented `REQUIRED_MODULES` protocol in Section 4.5 of CVE guide, enforcing baseline extension comparison, ionCube probe detection, static module deduplication, and manual rollback warnings on module drop.
- **Step-by-Step Operator Runbooks**:
  - Added explicit `git clone` to execution steps in root `README.md`, `cve-2026-109618-109619/README.md`, and `local-lab/README.md`.

### Changed
- **OS Support Matrix Alignment & Demarcation**:
  - Aligned all documentation and badges to reflect exact empirical test evidence across Ubuntu (14.04–24.04 LTS), Debian (9, 12), CentOS Stream (9), CentOS EOL (7, 8), and Alpine Linux (3.21, 3.22).
  - Explicitly documented Red Hat Enterprise Linux (RHEL 7, 8, 9) and enterprise rebuilds (AlmaLinux, Rocky, Oracle Linux) as out of scope due to existing vendor errata (`ALSA-2026:87072` through `87080`).
  - Demarcated distributions verified natively in LXC vs. simulated/unverified native releases (Debian 7/8/10/11/13, CentOS 6).
- **Mermaid Syntax & Parser Compatibility**:
  - Resolved syntax errors in Mermaid flowchart and sequence diagrams for headless Chromium and GitHub web rendering.
- **Diagram Typography & Self-Containment**:
  - Replaced ambiguous Unicode section symbols (`§`) with explicit "Section" text to prevent font rendering ambiguities.
  - Decoupled diagrams and captions from private test specification section numbers, establishing self-contained phase descriptions.

### Fixed
- Fixed residual references to RHEL/AlmaLinux in CLI autodetection descriptions across root documentation.

---

## [1.0.0] - 2026-10-23

### Added
- **CVE-2026-109618 & CVE-2026-109619 Mitigation Suite**:
  - Zero-fuzz C-source patches covering PHP 5.5 through 8.1 (`php5.5-cve-109618-109619.patch` through `php8.1-cve-109618-109619.patch`).
  - Fixes multipart parser heap corruption caused by `longjmp()` allocator bailout (`Zend/zend_alloc.c`).
  - Fixes pre-RINIT session upload progress poisoning via `PHP_SESSION_UPLOAD_PROGRESS` (`ext/session/session.c`).
- **Universal Autopatcher CLI (`universal-autopatch-109618-109619.sh`)**:
  - Multi-OS autodetection across Ubuntu, Debian, CentOS, and Alpine Linux.
  - Safe `--preview` dry-run mode with zero system modification.
  - Fast FPM runtime configuration hardening (`--apply`) with automated timestamped backups to `/var/backups/php-cve-mitigation/`.
  - Lossless `--rollback` restoration mode.
  - Automated C compiler invocation (`--build-binary`).
- **Dynamic C Compiler (`compile-and-patch-vm-cve.sh`)**:
  - Automated dependency resolution, pristine upstream source retrieval, zero-fuzz patch application, and atomic binary replacement for Ubuntu and Debian hosts.
- **Edge Perimeter Hardening**:
  - Nginx reverse-proxy configuration snippet (`cve-2026-hardening.conf`) blocking multipart upload progress abuse and malformed headers at the perimeter.
- **Container Build Recipes**:
  - Multi-stage container recipes for Ubuntu 24.04 glibc (`Dockerfile.sample`) and Alpine musl libc (`Dockerfile.alpine`).
- **Automated Regression Harness**:
  - Containerized test suite (`test-cross-os-e2e.sh`) verifying preview, apply, SAPI flags, and rollback in ephemeral Docker sandboxes.
- **Isolated Local Verification Lab (`local-lab/`)**:
  - Network-isolated LXC testbed (`labbr0`, `10.77.77.0/24`, NAT disabled, egress drop ACL).
  - Provisioning automation (`setup.sh`) and scanner test integration.
