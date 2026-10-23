#!/usr/bin/env bash
# ==============================================================================
# local-lab/setup.sh
#
# One-shot orchestrator for the PHP2Shell local lab.
#
# Every phase is a separate script so it can be run, inspected, and re-run on
# its own. This just sequences them and stops at the first failure, because a
# half-built lab produces scan results that look real and are not.
#
# Usage:
#   ./setup.sh                 # full build: preflight -> provision -> harden -> scan
#   ./setup.sh preflight       # host capability checks only
#   ./setup.sh provision       # bridges + targets + hardening
#   ./setup.sh scan            # scan only (lab must already be built)
#   ./setup.sh verify          # re-check containment without rebuilding
#   ./setup.sh teardown        # destroy everything this lab created
#
# Prerequisites: see docs/01-prerequisites.md
# ==============================================================================
set -euo pipefail

LOCAL_LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${LOCAL_LAB_ROOT}/scripts"
# shellcheck source=scripts/_common.sh
. "${SCRIPTS}/_common.sh"

phase_preflight() {
  log_step "PHASE 1 — Host preflight"
  bash "${SCRIPTS}/00-preflight.sh"
}

phase_network() {
  log_step "PHASE 2 — Isolated network"
  bash "${SCRIPTS}/01-isolated-bridge.sh"
  bash "${SCRIPTS}/02-de-nat-legacy-bridge.sh"
}

phase_targets() {
  log_step "PHASE 3 — Provision targets"
  bash "${SCRIPTS}/10-open-provisioning.sh"
  bash "${SCRIPTS}/20-provision-targets.sh"
  bash "${SCRIPTS}/21-fix-nics.sh"
  bash "${SCRIPTS}/30-harden-targets.sh"

  # The provisioning bridge must close BEFORE any scan. A target that can still
  # reach the internet is not the target under test.
  log_step "PHASE 3b — Close provisioning and re-verify containment"
  bash "${SCRIPTS}/11-close-provisioning.sh"
}

phase_attacker() {
  log_step "PHASE 4 — Attacker box"
  bash "${SCRIPTS}/40-attacker-box.sh"
}

phase_snapshot() {
  log_step "PHASE 5 — Baselines"
  bash "${SCRIPTS}/50-snapshot.sh"
}

phase_scan() {
  log_step "PHASE 6 — Verification scan"
  bash "${SCRIPTS}/70-scan-all.sh"
}

phase_verify() {
  log_step "PHASE — Containment verification"
  bash "${SCRIPTS}/11-close-provisioning.sh"
}

phase_teardown() {
  log_step "PHASE — Teardown"
  bash "${SCRIPTS}/90-teardown.sh"
}

main() {
  local phase="${1:-all}"

  echo "${_c_bld}======================================================================${_c_off}"
  echo "${_c_bld}  PHP2Shell Local Lab — CVE-2026-109618 / CVE-2026-109619           ${_c_off}"
  echo "${_c_bld}======================================================================${_c_off}"
  log_info "Phase requested: ${phase}"
  log_info "Lab bridge:      ${LAB_BRIDGE} (${LAB_SUBNET}), NAT off"
  log_info "Targets:         ${#TARGETS[@]}"

  case "${phase}" in
    preflight) phase_preflight ;;
    provision) phase_preflight; phase_network; phase_targets; phase_attacker; phase_snapshot ;;
    scan)      phase_scan ;;
    verify)    phase_verify ;;
    teardown)  phase_teardown ;;
    all)
      phase_preflight
      phase_network
      phase_targets
      phase_attacker
      phase_snapshot
      phase_scan
      ;;
    *)
      echo "Usage: $0 [all|preflight|provision|scan|verify|teardown]"
      exit 1
      ;;
  esac

  echo
  log_ok "Phase '${phase}' complete."
  [ "${phase}" != "all" ] && log_info "Next: ./setup.sh scan" || true
}

main "$@"
