#!/usr/bin/env python3
"""Workbook sheets: scope, oracle finding, docker suite, patch inventory, artifacts."""

from openpyxl.styles import Font
from xlsx_style import MUTED, table, title


def sheet_scope(wb):
    ws = wb.create_sheet("Scope")
    title(
        ws,
        "Scope Decisions",
        "Why each platform is in or out of the patch target set",
        span=4,
    )
    table(
        ws,
        5,
        ["Platform", "In scope", "Reason", "Reference"],
        [
            [
                "Ubuntu 14.04 / 16.04 / 18.04 / 20.04 / 22.04",
                "YES",
                "In scope (PHP 5.5 - 8.1). All branches patched in place and verified.",
                "local-lab matrix",
            ],
            [
                "Debian 9",
                "YES",
                "EOL PHP 7.0; configuration hardening verified in Docker suite",
                "archive.debian.org",
            ],
            [
                "CentOS 7 / 8",
                "YES",
                "EOL; configuration hardening verified in Docker suite",
                "vault.centos.org",
            ],
            [
                "CentOS Stream 9",
                "YES",
                "EL9 running PHP 8.0.30; in-place C-source rebuild verified with our patch (502 -> 200)",
                "local-lab centos9-test-lxc",
            ],
            [
                "Debian 12, Alpine 3.21 / 3.22, CentOS Stream 10",
                "NO — OUT OF SCOPE",
                "Ship PHP 8.2+ only; outside declared 5.5–8.1 scope",
                "DLA-4848-1 / upstream releases",
            ],
            [
                "RHEL / AlmaLinux / Rocky / Oracle Linux",
                "NO — OUT OF SCOPE",
                "Official vendor errata available (ALSA-2026:87072/87073/87079/87080); third-party backport refused",
                "Vendor update channels",
            ],
            [
                "PHP 8.2 and above",
                "NO — OUT OF SCOPE",
                "Supported upstream; 8.2.34->8.2.35 delta is a 2,903-line guard refactor with no minimal portable patch",
                "Upstream git diff",
            ],
        ],
        [34, 16, 76, 30],
        tint_col=2,
    )


def sheet_oracle_finding(wb):
    ws = wb.create_sheet("Oracle Finding")
    title(
        ws,
        "Scanner Oracle Finding",
        "A correctly patched host returns HTTP 502 — the discriminator is the FPM log",
        span=3,
    )
    table(
        ws,
        5,
        ["Evidence", "Vulnerable host", "Patched host"],
        [
            ["Scanner verdict", "VULNERABLE", "VULNERABLE — identical"],
            ["HTTP status", "502", "502 — identical"],
            [
                "FPM log",
                "child exited on signal 11 (SIGSEGV)",
                "child exited with code 1",
            ],
            ["Core dumped", "yes", "no"],
            ["Running binary SHA-256", "pre-patch", "post-patch"],
            [
                "Root cause",
                "Memory corruption",
                "zend_mm_safe_error_ex() is ZEND_NORETURN and calls _exit(1)",
            ],
            ["Source", "Zend/zend_alloc.c:403", "Zend/zend_alloc.c:403"],
            [
                "Measured (isolated log)",
                "signal 11 / SIGSEGV",
                "focal-builder: code 1 after 4.469606s",
            ],
            [
                "Measured (isolated log)",
                "not applicable",
                "php74-mitigation: code 1 after 4.466688s",
            ],
            [
                "Flawed method, rejected",
                "journalctl --since surfaced 686s / 2091s / 2100s old exits — normal recycles, code 70",
                "isolating FPM error_log removed all ambiguity",
            ],
        ],
        [26, 42, 60],
    )
    ws.cell(
        row=13,
        column=1,
        value="Verdict: scanner output alone cannot distinguish these two states. Read the FPM log.",
    ).font = Font(name="Calibri", size=10, italic=True, color=MUTED)
    ws.merge_cells(start_row=13, start_column=1, end_row=13, end_column=3)


def sheet_docker_suite(wb):
    ws = wb.create_sheet("Docker Suite")
    title(
        ws,
        "Cross-OS Docker Regression Suite",
        "test-cross-os-e2e.sh all - 7 targets, drop-in lifecycle verification",
        span=5,
    )
    table(
        ws,
        5,
        ["Target", "Image", "Repo source", "Layout", "Result"],
        [
            [
                "debian9",
                "debian:9",
                "archive.debian.org (EOL)",
                "/etc/php/7.0/fpm/conf.d",
                "PASS",
            ],
            ["ubuntu18", "ubuntu:18.04", "live", "/etc/php/7.2/fpm/conf.d", "PASS"],
            ["debian12", "debian:12", "live", "/etc/php/8.1/fpm/conf.d", "PASS"],
            ["alpine", "alpine:3.21", "live", "/etc/php81/conf.d", "PASS"],
            [
                "centos7",
                "centos:7",
                "vault.centos.org + remi-php74",
                "/etc/php.d",
                "PASS",
            ],
            ["centos8", "centos:8", "vault.centos.org", "/etc/php.d", "PASS"],
            ["centos9", "quay.io/centos/centos:stream9", "live", "/etc/php.d", "PASS"],
        ],
        [14, 32, 32, 28, 10],
        tint_col=5,
    )
    ws.cell(
        row=14,
        column=1,
        value="Each target verifies: --preview, --apply, drop-in contents incl. runtime caps, live FPM SAPI, --rollback.",
    ).font = Font(name="Calibri", size=10, italic=True, color=MUTED)
    ws.merge_cells(start_row=14, start_column=1, end_row=14, end_column=5)


def sheet_patch_inventory(wb):
    ws = wb.create_sheet("Patch Inventory")
    title(
        ws,
        "Patch Inventory & Duplicate Audit",
        "Every .patch grouped by content hash - canonical copy identified, gates reconciled",
        span=4,
    )
    table(
        ws,
        5,
        ["Property", "Value", "Interpretation", "Status"],
        [
            ["Total .patch files", 47, "Across 55 directories", "n/a"],
            [
                "Unique contents (by sha256)",
                19,
                "9 canonical branches + 10 range patches",
                "PASS",
            ],
            [
                "Canonical patch copies",
                "9 x 3",
                "cve-<id>/, docker-image/, docker-image/patch-cve/",
                "PASS",
            ],
            [
                "Range patch copies",
                "10 x 2",
                "tools/range-patches/ + generated local-lab mirror",
                "PASS",
            ],
            [
                "Singletons (content appearing once)",
                0,
                "No patch exists in only one place unexpectedly",
                "PASS",
            ],
            [
                "Documented gates unmatched",
                0,
                "All nine README SHA-256 gates match a real file",
                "PASS",
            ],
            [
                "Canonical location",
                "cve-2026-109618-109619/<branch>-cve-109618-109619.patch",
                "Always authoritative; other copies are build-context mirrors",
                "n/a",
            ],
            [
                "Drift detection",
                "local-lab/sync-codebase.sh --check",
                "Verifies the generated mirror against source",
                "PASS",
            ],
            [
                "Vendor-changelog fixes found",
                "centos9 (8.0.30-9.el9)",
                "RPM changelog names both CVE ids, dated 2026-10-21",
                "FIXED",
            ],
        ],
        [36, 48, 52, 12],
        tint_col=4,
    )


def sheet_artifacts(wb):
    ws = wb.create_sheet("Artifacts")
    title(
        ws,
        "Artifacts Produced",
        "Everything generated by this verification run",
        span=4,
    )
    table(
        ws,
        5,
        ["Artifact", "Path", "Type", "Purpose"],
        [
            [
                "Lab kit",
                "local-lab/",
                "tooling",
                "Auto-setup, docs, diagrams, pentest flow",
            ],
            [
                "Lab config",
                "local-lab/lab.conf",
                "config",
                "Single source of truth for the topology",
            ],
            [
                "Setup orchestrator",
                "local-lab/setup.sh",
                "script",
                "One-shot lab build",
            ],
            [
                "Range patch tooling",
                "cve-2026-109618-109619/tools/",
                "tooling",
                "Cross-minor patch generation and validation",
            ],
            [
                "Range patches",
                "cve-2026-109618-109619/tools/range-patches/",
                "patches",
                "10 patches, one per branch (7.4 has two variants)",
            ],
            [
                "Cross-OS Docker suite",
                "cve-2026-109618-109619/test-cross-os-e2e.sh",
                "script",
                "7 suites including CentOS 7/8/9",
            ],
            [
                "Hardening drop-in",
                "cve-2026-109618-109619/docker-image/cve-2026-hardening.ini",
                "config",
                "Runtime caps",
            ],
            ["Coverage workbook", "docs/test-report/*.xlsx", "report", "This workbook"],
            [
                "Remediation report",
                "docs/test-report/php2shell-lab-remediation-report-2026-10-24.pdf",
                "report",
                "Consolidated findings",
            ],
        ],
        [26, 58, 12, 56],
    )

    wb.properties.creator = "Andy Setiyawan | Security Engineering"
    wb.properties.lastModifiedBy = "Andy Setiyawan | Security Engineering"
    wb.properties.title = "CVE-2026-109618 / CVE-2026-109619 Verification Coverage"
    wb.properties.subject = "PHP2Shell local lab verification results"
    wb.properties.description = (
        "Cross-OS verification coverage for CVE-2026-109618 and "
        "CVE-2026-109619. Evidence collected 2026-10-24."
    )
    wb.properties.category = "Security Verification"
    wb.properties.keywords = "CVE-2026-109618, CVE-2026-109619, PHP, verification"
