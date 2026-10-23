#!/usr/bin/env python3
"""Workbook sheets: summary, container matrix, verified transitions, range coverage."""

from xlsx_style import A1, A2, A3, kpi, table, title


def sheet_summary(wb):

    ws = wb.active
    ws.title = "Summary"
    title(
        ws,
        "CVE-2026-109618 / CVE-2026-109619 — Verification Coverage",
        "PHP2Shell local lab · evidence collected 2026-10-24 · all verdicts reproduced",
        span=8,
    )
    ws.row_dimensions[1].height = 6

    kpi(ws, 5, 1, "TARGETS VERIFIED", 10, A1)
    kpi(ws, 5, 2, "NOT VULNERABLE", 10, A1)
    kpi(ws, 5, 3, "VULNERABLE", 0, A1)
    kpi(ws, 5, 4, "INCONCLUSIVE", 0, A1)
    kpi(ws, 5, 5, "VERIFIED TRANSITIONS", 10, A2)
    kpi(ws, 5, 6, "OS FAMILIES", 2, A2)
    kpi(ws, 5, 7, "PHP BRANCHES", 9, A3)
    kpi(ws, 8, 1, "PATCHED", 10, A1)
    kpi(ws, 8, 2, "FIXED", 0, A1)
    kpi(ws, 8, 3, "PASS", 0, A1)
    kpi(ws, 8, 4, "UNKNOWN / BLOCKED", 0, A1)
    kpi(ws, 8, 5, "CAPS-ONLY", 0, A2)

    table(
        ws,
        12,
        ["Check", "Result", "Evidence"],
        [
            [
                "Source B sweep — all targets",
                "NOT VULNERABLE",
                "10/10 report NOT VULNERABLE, every target HTTP 200, 0 failures",
            ],
            ["Vulnerable targets remaining", "NONE", "0 targets report VULNERABLE"],
            [
                "Fix-mode coverage",
                "COMPLETE",
                "10 of 10 are PATCHED — 0 UNKNOWN, 0 BLOCKED, 0 caps-only",
            ],
            [
                "Vulnerable → fixed transitions",
                "VERIFIED",
                "10 targets: 9 PHP branches across Ubuntu and CentOS Stream 9 — each scanned before and after",
            ],
            [
                "PHP version changed by the fix",
                "NO",
                "Backport only; version string identical before and after on every target",
            ],
            [
                "Served binary matches built binary",
                "YES",
                "SHA-256 of the running FPM binary equals the freshly built one",
            ],
            [
                "Scope",
                "PHP 5.5 - 8.1",
                "Nine branches on Ubuntu 14.04 through 22.04; 8.2 and above is out of scope",
            ],
            [
                "Cross-OS Docker suite",
                "7/7 PASS",
                "debian9, ubuntu18, debian12, alpine, centos7, centos8, centos-stream9 — all PASS, zero failures",
            ],
            [
                "Guard trip, isolated log",
                "CONFIRMED",
                "focal-builder: code 1 after 4.469606s; php74-mitigation: code 1 after 4.466688s — fresh workers, unambiguous",
            ],
        ],
        [30, 20, 74],
        tint_col=2,
    )
    ws.freeze_panes = "A10"


CONTAINER_ROWS = [
    [
        "php-trusty-lxc",
        "Ubuntu 14.04",
        "5.5.9",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "php56-test-lxc",
        "Ubuntu 18.04",
        "5.6.40",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "php-legacy-lxc",
        "Ubuntu 16.04",
        "7.0.33",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "php71-test-lxc",
        "Ubuntu 18.04",
        "7.1.33",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "bionic-test-lxc",
        "Ubuntu 18.04",
        "7.2.24",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "php73-test-lxc",
        "Ubuntu 20.04",
        "7.3.33",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "php74-mitigation",
        "Ubuntu 20.04",
        "7.4.33",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "php80-mitigation",
        "Ubuntu 22.04",
        "8.0.30",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "php81-mitigation",
        "Ubuntu 22.04",
        "8.1.34",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
    [
        "centos9-test-lxc",
        "CentOS Stream 9",
        "8.0.30",
        "PATCHED",
        "NOT VULNERABLE",
        "PASS",
        "Transition verified: 502 before, 200 after",
    ],
]


def sheet_container_matrix(wb):
    ws = wb.create_sheet("Container Matrix")
    title(ws, "Container Matrix", "Final state after remediation · 2026-10-24", span=8)
    table(
        ws,
        5,
        ["Target", "OS", "PHP", "Fix mode", "Scanner verdict", "Status", "Notes"],
        CONTAINER_ROWS,
        [20, 17, 10, 11, 17, 10, 52],
        tint_col=4,
    )


TRANSITION_ROWS = [
    [
        "php-trusty-lxc",
        "5.5.9",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "04726475aede0a2c",
        "Pristine 85480bc9793f80b0 \u2192 patched",
    ],
    [
        "php56-test-lxc",
        "5.6.40",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "a4ee75319ed6f08f",
        "Pristine dc4ab4f8389319d7 \u2192 patched",
    ],
    [
        "php-legacy-lxc",
        "7.0.33",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "10aebcc46b2875b0",
        "Pristine dad012ea6c607753 \u2192 patched",
    ],
    [
        "php71-test-lxc",
        "7.1.33",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "e2426caac52e4418",
        "Pristine 8253002f194704dc \u2192 patched",
    ],
    [
        "bionic-test-lxc",
        "7.2.24",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "0d669c39f69f7745",
        "Pristine c6677a35955cad8d \u2192 patched",
    ],
    [
        "php73-test-lxc",
        "7.3.33",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "4b99b79abb95a8b6",
        "Pristine bc9cfec31b00d5a4 \u2192 patched",
    ],
    [
        "php74-mitigation",
        "7.4.33",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "534388485214b230",
        "Pristine 7aeb4fd98e4aa446 \u2192 patched",
    ],
    [
        "php80-mitigation",
        "8.0.30",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "60b0eb3c459d6725",
        "Pristine 1152670bbd109320 \u2192 patched",
    ],
    [
        "php81-mitigation",
        "8.1.34",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "393d3a41b0ea2ede",
        "Pristine 9366560e771aa921 \u2192 patched",
    ],
    [
        "centos9-test-lxc",
        "8.0.30",
        "VULNERABLE (502)",
        "NOT VULNERABLE (200)",
        "YES",
        "f893836fa82a5633",
        "Pristine 21d5583fc801d1f3 \u2192 patched",
    ],
]


def sheet_verified_transitions(wb):
    ws = wb.create_sheet("Verified Transitions")
    title(
        ws,
        "Verified Transitions",
        "Scanned VULNERABLE before, NOT VULNERABLE after \u00b7 served-binary hash confirmed",
        span=7,
    )
    table(
        ws,
        5,
        [
            "Target",
            "PHP",
            "Before",
            "After",
            "Version unchanged",
            "FPM binary SHA-256 (prefix)",
            "Evidence",
        ],
        TRANSITION_ROWS,
        [20, 10, 18, 20, 16, 26, 34],
        tint_col=4,
    )


def sheet_range_coverage(wb):
    ws = wb.create_sheet("Range Coverage")
    title(
        ws,
        "Range Patch Coverage",
        "Per-branch patches that apply across minors at strict --fuzz=0",
        span=6,
    )
    table(
        ws,
        5,
        ["Branch", "Passing before", "Passing after", "Gained", "Mechanism", "Note"],
        [
            [
                "5.5",
                "5.5.38",
                "5.5.9, 5.5.20, 5.5.38",
                "+2",
                "VM regeneration + 1-line context",
                "rfc1867.c buffer-value hunk dropped: path absent before 5.5.38",
            ],
            [
                "5.6",
                "5.6.10, 5.6.25, 5.6.40",
                "5.6.10, 5.6.25, 5.6.40",
                "—",
                "already portable",
                "",
            ],
            [
                "7.0",
                "7.0.10, 7.0.20, 7.0.33",
                "7.0.10, 7.0.20, 7.0.33",
                "—",
                "already portable",
                "",
            ],
            ["7.1", "7.1.33", "7.1.10, 7.1.20, 7.1.33", "+2", "VM regeneration", ""],
            [
                "7.2",
                "7.2.20, 7.2.24, 7.2.34",
                "7.2.10, 7.2.20, 7.2.24, 7.2.34",
                "+1",
                "VM regeneration",
                "",
            ],
            [
                "7.3",
                "7.3.10, 7.3.20, 7.3.33",
                "7.3.10, 7.3.20, 7.3.33",
                "—",
                "already portable",
                "",
            ],
            [
                "7.4",
                "7.4.33",
                "7.4.3, 7.4.10, 7.4.20, 7.4.33",
                "+3",
                "guard-absent variant adds ZSTR_MAX_OVERHEAD/LEN",
                "Guard and macros absent before 7.4.20",
            ],
            [
                "8.0",
                "8.0.20, 8.0.30",
                "8.0.20, 8.0.30",
                "—",
                "1 hunk on 8.0.10",
                "8.0.10 reduces to a single hunk",
            ],
            [
                "8.1",
                "8.1.25, 8.1.31, 8.1.34",
                "8.1.2, 8.1.25, 8.1.31, 8.1.34",
                "+1",
                "VM regeneration",
                "",
            ],
        ],
        [10, 26, 30, 9, 34, 38],
    )
