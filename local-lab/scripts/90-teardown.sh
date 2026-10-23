#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/90-teardown.sh
#
# Destroy everything this lab created, in dependency order.
#
# Order matters:
#   1. Delete containers (a network cannot be deleted while it has members).
#   2. Delete the provisioning bridge if it is somehow still up.
#   3. Delete the lab bridge and its ACL.
#   4. Remove the report directory, databases first.
#
# This is destructive and irreversible. It refuses to run without --yes.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

CONFIRM="${1:-}"

log_step "Teardown plan"

echo "  Containers to delete:"
for name in $(target_names) "${ATTACKER_NAME}"; do
  container_exists "${name}" && echo "    - ${name}"
done
echo "  Networks:   ${PROV_BRIDGE} (if present), ${LAB_BRIDGE}"
echo "  ACLs:       ${PROV_ACL} (if present), ${LAB_ACL}"
echo "  Report dir: ${REPORTS_HOST_DIR}"
echo
log_warn "This deletes the containers AND their snapshots. It cannot be undone."

if [ "${CONFIRM}" != "--yes" ]; then
  echo
  log_info "Re-run with --yes to proceed:  $0 --yes"
  exit 0
fi

log_step "Deleting containers"
for name in $(target_names) "${ATTACKER_NAME}"; do
  if container_exists "${name}"; then
    lxc delete -f "${name}" >/dev/null 2>&1 && log_ok "deleted ${name}" || log_warn "could not delete ${name}"
  fi
done

# Any container still sitting on a lab network, whatever its name.
for net in "${PROV_BRIDGE}" "${LAB_BRIDGE}"; do
  network_exists "${net}" || continue
  while IFS= read -r c; do
    [ -n "${c}" ] || continue
    log_warn "${c} is still attached to ${net}; detaching"
    lxc network detach "${net}" "${c}" >/dev/null 2>&1 || true
  done < <(lxc list --format csv -c n 2>/dev/null || true)
done

log_step "Deleting networks"
for net in "${PROV_BRIDGE}" "${LAB_BRIDGE}"; do
  if network_exists "${net}"; then
    lxc network delete "${net}" >/dev/null 2>&1 && log_ok "deleted network ${net}" || log_warn "could not delete ${net}"
  fi
done

log_step "Deleting ACLs"
for acl in "${PROV_ACL}" "${LAB_ACL}"; do
  if acl_exists "${acl}"; then
    lxc network acl delete "${acl}" >/dev/null 2>&1 && log_ok "deleted ACL ${acl}" || log_warn "could not delete ${acl}"
  fi
done

log_step "Removing report directory"
if [ -d "${REPORTS_HOST_DIR}" ]; then
  # Remove database files first: they may be root-owned inside the idmap.
  sudo -n rm -f "${REPORTS_HOST_DIR}"/*.db 2>/dev/null || true
  sudo -n rm -rf "${REPORTS_HOST_DIR}" 2>/dev/null && log_ok "removed ${REPORTS_HOST_DIR}" \
    || log_warn "could not remove ${REPORTS_HOST_DIR} (may need sudo)"
fi

log_step "Teardown complete."
log_info "Verify no stray NAT remains:  sudo nft list ruleset | grep ${LAB_SUBNET%/*}"
