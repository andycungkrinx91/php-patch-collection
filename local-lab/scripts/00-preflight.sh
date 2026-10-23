#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/00-preflight.sh
#
# Host capability checks. Run this before anything else.
#
# Every check here has a concrete failure mode that costs real time if missed:
# the default LXD storage driver cannot enforce size limits, the attacker box
# needs more memory than the targets, and without read access to the firewall
# ruleset the containment claim cannot be verified at all.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

log_step "Host preflight"

failures=0
warnings=0

check_pass() { log_ok   "$1"; }
check_warn() { log_warn "$1"; warnings=$((warnings + 1)); }
check_fail() { log_fail "$1"; failures=$((failures + 1)); }

# --- 1. LXD access ------------------------------------------------------------
if is_lxc_root || running_as_lxd_group; then
  check_pass "LXD access available ($(lxc version --format csv 2>/dev/null | tr -d '\n' || echo 'lxc present'))"
else
  check_fail "No LXD access. Run: sudo usermod -aG lxd \$USER  (then re-login)"
fi

if network_exists "${LAB_BRIDGE}"; then
  log_info "  Lab bridge ${LAB_BRIDGE} already exists (re-run is fine)."
fi

# --- 2. Storage capacity ------------------------------------------------------
avail_kb="$(df -Pk /var/snap/lxd 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
[ "${avail_kb}" -eq 0 ] 2>/dev/null && avail_kb="$(df -Pk / 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
avail_gb=$((avail_kb / 1024 / 1024))

if [ "${avail_gb}" -ge 40 ]; then
  check_pass "Disk headroom: ${avail_gb} GiB free"
elif [ "${avail_gb}" -ge 20 ]; then
  check_warn "Disk headroom: ${avail_gb} GiB free. Roughly ${#TARGETS[@]} targets need ~20 GiB."
else
  check_fail "Disk headroom: ${avail_gb} GiB free. Too little for ${#TARGETS[@]} targets."
fi

# --- 3. Storage driver --------------------------------------------------------
driver="$(lxc storage show default --format csv -c driver 2>/dev/null | tr -d ' \r\n' || echo unknown)"
if [ "${driver}" = "dir" ]; then
  check_warn "Storage driver is 'dir': per-container rootfs quota is NOT enforceable."
  check_warn "  Record this as a known deviation if you document size limits."
elif [ "${driver}" = "unknown" ]; then
  check_warn "Could not determine the default storage driver."
else
  check_pass "Storage driver: ${driver} (size limits supported)"
fi

# --- 4. Container runtime -----------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  check_pass "Docker available (needed for test-cross-os-e2e.sh)"
else
  check_warn "Docker not available; the Docker cross-OS suite will not run."
fi

# --- 5. Firewall read access --------------------------------------------------
# Without this the containment claim cannot be checked at the ruleset level.
if sudo -n nft list ruleset >/dev/null 2>&1; then
  check_pass "Firewall ruleset is readable without a password"
elif command -v nft >/dev/null 2>&1; then
  check_warn "Cannot read the nft ruleset unprivileged."
  check_warn "  Install the read-only drop-in from docs/01-prerequisites.md to verify containment."
else
  check_warn "nft not found; containment will be verified behaviourally only."
fi

# --- 6. Host internet ---------------------------------------------------------
# The host needs internet for image pulls and package pre-staging. The lab does not.
if curl -s -o /dev/null --max-time 10 https://images.linuxcontainers.org; then
  check_pass "Host has internet (required for image pulls)"
else
  check_fail "Host has no internet. Image pulls and package installs will fail."
fi

# --- 7. Image availability ----------------------------------------------------
log_info "Resolving target images:"
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name image _ <<< "${entry}"
  if lxc image info "${image}" >/dev/null 2>&1; then
    log_info "  ok   ${image}"
  else
    check_fail "  MISS ${image} (target ${name} cannot be created)"
  fi
done

# --- Summary ------------------------------------------------------------------
log_step "Preflight summary: ${failures} failure(s), ${warnings} warning(s)"

if [ "${failures}" -gt 0 ]; then
  log_fail "Resolve the failures above before continuing."
  log_fail "A lab built on a failed preflight produces results that look valid and are not."
  exit 1
fi

log_ok "Preflight passed."
[ "${warnings}" -gt 0 ] && log_info "Warnings are non-blocking but should be documented."
exit 0
