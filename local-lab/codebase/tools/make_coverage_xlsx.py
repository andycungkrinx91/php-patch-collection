#!/usr/bin/env python3
"""Regenerate the CVE-2026-109618 / CVE-2026-109619 coverage workbook."""

import logging

from openpyxl import Workbook

from xlsx_sheets_lab import (
    sheet_container_matrix,
    sheet_range_coverage,
    sheet_summary,
    sheet_verified_transitions,
)
from xlsx_sheets_report import (
    sheet_artifacts,
    sheet_docker_suite,
    sheet_oracle_finding,
    sheet_patch_inventory,
    sheet_scope,
)
from xlsx_style import OUT


def build():
    """Assemble the coverage workbook and return it."""
    wb = Workbook()
    sheet_summary(wb)
    sheet_container_matrix(wb)
    sheet_verified_transitions(wb)
    sheet_range_coverage(wb)
    sheet_scope(wb)
    sheet_oracle_finding(wb)
    sheet_docker_suite(wb)
    sheet_patch_inventory(wb)
    sheet_artifacts(wb)
    return wb


def main():
    """Write the coverage workbook to OUT."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    log = logging.getLogger("make_coverage_xlsx")
    wb = build()
    wb.save(OUT)
    log.info("wrote %s", OUT)
    log.info("sheets: %s", wb.sheetnames)


if __name__ == "__main__":
    main()
