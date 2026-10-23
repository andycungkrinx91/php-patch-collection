#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/01-isolated-bridge.sh
#
# Create the isolated lab bridge and its default-deny egress ACL.
#
# This is the step that makes the containment claim true. Two separate mechanisms
# are required, and neither alone is sufficient:
#
#   1. ipv4.nat=false  -> LXD installs no masquerade rule, so nothing is
#                         translated onto the host uplink.
#   2. egress ACL with a terminal reject -> even without NAT, a bridge would
#                         still forward packets between its own subnet and the
#                         uplink unless filtering rejects them.
#
# A third LXD detail matters in practice: rules that specify no destination are
# hoisted to the top of the generated ruleset. Writing the catch-all reject first
# therefore rejects everything, including intra-subnet traffic. The rules are
# added in this order instead: one scoped allow per destination, then the
# catch-all reject last.
#
# Idempotent: safe to re-run.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

log_step "Creating isolated lab bridge ${LAB_BRIDGE} (${LAB_SUBNET})"

if network_exists "${LAB_BRIDGE}"; then
  log_info "Bridge ${LAB_BRIDGE} already exists; reusing it."
else
  lxc network create "${LAB_BRIDGE}" \
    ipv4.address="${LAB_GATEWAY}/24" \
    ipv4.nat=false \
    ipv4.dhcp=true \
    ipv4.firewall=true \
    ipv6.address=none \
    ipv6.nat=false
  log_ok "Bridge ${LAB_BRIDGE} created with ipv4.nat=false."
fi

# --- Egress ACL ---------------------------------------------------------------
if acl_exists "${LAB_ACL}"; then
  log_info "ACL ${LAB_ACL} already exists; leaving its rules untouched."
else
  lxc network acl create "${LAB_ACL}"

  # Scoped allow first: hosts on the lab subnet may talk to each other.
  lxc network acl rule add "${LAB_ACL}" egress action=allow destination="${LAB_SUBNET}"
  # Terminal reject last: everything else dies here.
  lxc network acl rule add "${LAB_ACL}" egress action=reject
  # Ingress stays open so the attacker box can reach targets.
  lxc network acl rule add "${LAB_ACL}" ingress action=allow

  log_ok "ACL ${LAB_ACL} created: allow ${LAB_SUBNET}, reject everything else."
fi

lxc network set "${LAB_BRIDGE}" security.acls="${LAB_ACL}"
lxc network set "${LAB_BRIDGE}" security.acls.default.egress.action=reject
lxc network set "${LAB_BRIDGE}" security.acls.default.ingress.action=allow

# --- Verify -------------------------------------------------------------------
log_step "Verifying bridge configuration"
nat_state="$(lxc network get "${LAB_BRIDGE}" ipv4.nat 2>/dev/null || echo unknown)"
acl_state="$(lxc network get "${LAB_BRIDGE}" security.acls 2>/dev/null || echo unknown)"

if [ "${nat_state}" != "false" ]; then
  log_fail "ipv4.nat is '${nat_state}', expected 'false'. Containment is not in place."
  exit 1
fi
log_ok "ipv4.nat = false"

if [ "${acl_state}" != "${LAB_ACL}" ]; then
  log_fail "security.acls is '${acl_state}', expected '${LAB_ACL}'."
  exit 1
fi
log_ok "security.acls = ${LAB_ACL}"

bridge_state="$(lxc network show "${LAB_BRIDGE}" --format csv -c status 2>/dev/null || echo unknown)"
log_info "Bridge status: ${bridge_state}"

log_step "Done. Next: scripts/02-de-nat-legacy-bridge.sh if an old NAT bridge exists, then scripts/20-provision-targets.sh"
