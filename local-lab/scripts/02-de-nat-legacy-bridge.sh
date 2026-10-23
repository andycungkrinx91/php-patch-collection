#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/02-de-nat-legacy-bridge.sh
#
# Remove masquerade from any pre-existing LXD bridge that targets used to sit on.
#
# The stock LXD default profile publishes a bridge with ipv4.nat=true, which
# installs a masquerade rule onto the host uplink. Creating the isolated lab
# bridge does not remove that rule, so a host that previously used the default
# bridge still leaks. This script closes it.
#
# Safety: only bridges with no remaining members are de-NATed. A bridge still in
# use is reported and skipped rather than yanked out from under a workload.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

log_step "Scanning LXD bridges for leftover masquerade"

# The lab bridge is meant to have NAT off; everything else is a candidate.
found_any=false

while IFS= read -r net; do
  [ -n "${net}" ] || continue
  [ "${net}" = "${LAB_BRIDGE}" ] && continue
  [ "${net}" = "${PROV_BRIDGE}" ] && continue

  nat="$(lxc network get "${net}" ipv4.nat 2>/dev/null || echo unknown)"
  [ "${nat}" = "true" ] || continue

  found_any=true
  members="$(lxc network show "${net}" --format json 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("used_by") or []))' 2>/dev/null || echo 0)"

  if [ "${members}" != "0" ]; then
    log_warn "Bridge ${net} still has ${members} member(s); NOT de-NATing it."
    log_warn "         Move those instances to ${LAB_BRIDGE} first, then re-run."
    continue
  fi

  log_info "Bridge ${net}: ipv4.nat=true, 0 members -> disabling NAT"
  lxc network set "${net}" ipv4.nat false
  lxc network set "${net}" ipv6.nat false 2>/dev/null || true
  log_ok "Bridge ${net}: NAT disabled"
done < <(lxc network list --format csv -c n 2>/dev/null)

if [ "${found_any}" = "false" ]; then
  log_ok "No leftover NAT bridges found."
fi

# --- Verify against the live ruleset ------------------------------------------
log_step "Verifying no masquerade rule references the lab subnet"

# nft needs root. The read-only sudoers drop-in documented in docs/01-prerequisites.md
# grants exactly this and nothing more.
if sudo -n nft list ruleset >/dev/null 2>&1; then
  if sudo -n nft list ruleset | grep -q "${LAB_SUBNET%/*}"; then
    if sudo -n nft list ruleset | grep "${LAB_SUBNET%/*}" | grep -q masquerade; then
      log_fail "A masquerade rule still references ${LAB_SUBNET}. Containment is NOT in place."
      sudo -n nft list ruleset | grep "${LAB_SUBNET%/*}" | grep masquerade
      exit 1
    fi
    log_info "Lab subnet appears in the ruleset (expected: the ACL reject chain), no masquerade."
  else
    log_info "Lab subnet absent from the ruleset; no NAT path exists."
  fi
  log_ok "No masquerade for ${LAB_SUBNET}."
else
  log_warn "Cannot read the nft ruleset without a sudo password."
  log_warn "Install the read-only drop-in from docs/01-prerequisites.md, or verify manually:"
  log_warn "  sudo nft list ruleset | grep ${LAB_SUBNET%/*}"
fi

log_step "Done. Next: scripts/20-provision-targets.sh"
