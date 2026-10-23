#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/40-attacker-box.sh
#
# Create the attacker/verification box and give it a report directory.
#
# The box starts on the provisioning bridge so tooling can be fetched, then moves
# to the isolated bridge like every target. The report directory is a single bind
# mount; it is the only host path any container can see.
#
# Idempotent.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

log_step "Provisioning attacker box ${ATTACKER_NAME}"

if container_exists "${ATTACKER_NAME}"; then
  log_info "${ATTACKER_NAME} already exists; skipping creation."
else
  if ! network_exists "${PROV_BRIDGE}"; then
    log_fail "Provisioning bridge ${PROV_BRIDGE} is not up."
    log_fail "Run scripts/10-open-provisioning.sh first."
    exit 1
  fi
  lxc launch "${ATTACKER_IMAGE}" "${ATTACKER_NAME}" -n "${PROV_BRIDGE}" \
    -c "limits.memory=${ATTACKER_MEMORY}" -c "limits.cpu=${ATTACKER_CPUS}"
  wait_for_exec "${ATTACKER_NAME}"
  log_ok "${ATTACKER_NAME} created."
fi

# --- Base tooling -------------------------------------------------------------
log_info "Installing base tooling..."
lxc exec "${ATTACKER_NAME}" -- bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  if command -v apt-get >/dev/null 2>&1; then
    apt-get -o Acquire::ForceIPv4=true update -qq
    apt-get -o Acquire::ForceIPv4=true install -y -q \
      curl wget git python3 python3-pip jq nmap netcat-openbsd dnsutils \
      ca-certificates procps patch >/dev/null
  fi
' >/dev/null 2>&1 && log_ok "Base tooling installed." || log_warn "Base tooling install reported errors."

# --- Report bind mount --------------------------------------------------------
# Under the default LXD idmap the container's root maps to host uid 1000000, so
# the host directory must be owned by that uid or the container cannot write.
log_info "Attaching report directory ${REPORTS_HOST_DIR} -> ${REPORTS_MOUNT_PATH}"
mkdir -p "${REPORTS_HOST_DIR}"
if sudo -n chown "${IDMAP_HOST_UID}:${IDMAP_HOST_GID}" "${REPORTS_HOST_DIR}" 2>/dev/null; then
  log_ok "Report dir owned by ${IDMAP_HOST_UID}:${IDMAP_HOST_GID} (matches the container idmap)."
else
  log_warn "Could not chown the report dir without a password."
  log_warn "  Run: sudo chown ${IDMAP_HOST_UID}:${IDMAP_HOST_GID} ${REPORTS_HOST_DIR}"
fi

lxc config device remove "${ATTACKER_NAME}" reports >/dev/null 2>&1 || true
lxc config device add "${ATTACKER_NAME}" reports disk \
  source="${REPORTS_HOST_DIR}" path="${REPORTS_MOUNT_PATH}" >/dev/null
log_ok "Report directory mounted."

# --- Move to the isolated bridge ----------------------------------------------
if [ "$(container_ip "${ATTACKER_NAME}" | cut -d. -f1-3)" != "10.77.77" ]; then
  log_info "Moving ${ATTACKER_NAME} to ${LAB_BRIDGE}"
  lxc config device remove "${ATTACKER_NAME}" eth0 >/dev/null 2>&1 || true
  lxc config device add "${ATTACKER_NAME}" eth0 nic network="${LAB_BRIDGE}" name=eth0 >/dev/null
  lxc restart "${ATTACKER_NAME}" >/dev/null 2>&1 || true
  wait_for_exec "${ATTACKER_NAME}" >/dev/null 2>&1 || true
  fix_nic "${ATTACKER_NAME}"
fi

ip="$(wait_for_ip "${ATTACKER_NAME}" 30 || true)"
[ -n "${ip}" ] && log_ok "${ATTACKER_NAME} is at ${ip}" || log_warn "${ATTACKER_NAME} has no address yet."

# --- Verify the mount is the only one ----------------------------------------
log_step "Verifying mount isolation"
mounts="$(lxc exec "${ATTACKER_NAME}" -- findmnt -rn -t none,autofs,bind -o TARGET 2>/dev/null || true)"
if [ "${mounts}" = "${REPORTS_MOUNT_PATH}" ]; then
  log_ok "Only ${REPORTS_MOUNT_PATH} is bind-mounted. No host path is exposed."
else
  log_warn "Unexpected mounts inside ${ATTACKER_NAME}:"
  echo "${mounts}" | sed 's/^/    /'
  log_warn "Expected exactly: ${REPORTS_MOUNT_PATH}"
fi

log_step "Done. Install the scanner toolkit with scripts/41-install-toolkit.sh"
