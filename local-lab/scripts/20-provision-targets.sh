#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/20-provision-targets.sh
#
# Create every target in TARGETS, install PHP, then move it onto the isolated
# lab bridge.
#
# Order matters and is deliberate:
#   1. Launch on the provisioning bridge (needs package downloads).
#   2. Install PHP + FPM + web server.
#   3. Move to the isolated bridge.
#   4. Bring the NIC up (containers boot with eth0 down after a network change).
#
# Targets are created on the provisioning bridge and finish on the lab bridge.
# By the time this script exits, no target can reach the internet.
#
# Prerequisites: scripts/10-open-provisioning.sh has run.
# Idempotent: existing containers are skipped, not recreated.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

if ! network_exists "${PROV_BRIDGE}"; then
  log_fail "Provisioning bridge ${PROV_BRIDGE} does not exist."
  log_fail "Run scripts/10-open-provisioning.sh first."
  exit 1
fi

log_step "Provisioning ${#TARGETS[@]} targets"

created=0; skipped=0; failed=0

for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name image memory cpus install_cmd <<< "${entry}"

  if container_exists "${name}"; then
    log_info "${name}: already exists, skipping creation."
    skipped=$((skipped + 1))
  else
    log_info "${name}: launching from ${image} (${memory}, ${cpus} cpu)"

    # Ubuntu images live on the `ubuntu:` remote; `images:ubuntu/18.04` 404s.
    if ! lxc launch "${image}" "${name}" -n "${PROV_BRIDGE}" \
           -c "limits.memory=${memory}" -c "limits.cpu=${cpus}"; then
      log_fail "${name}: launch failed. If the image does not resolve, check"
      log_fail "          'lxc image info ${image}' and adjust lab.conf."
      failed=$((failed + 1))
      continue
    fi
    created=$((created + 1))
  fi

  if ! wait_for_exec "${name}"; then
    failed=$((failed + 1)); continue
  fi

  log_info "${name}: installing PHP and web server"
  if ! lxc exec "${name}" -- bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        if command -v apt-get >/dev/null 2>&1; then
          apt-get -o Acquire::ForceIPv4=true update -qq
          ${install_cmd}
          systemctl enable --now php*-fpm 2>/dev/null || systemctl enable --now php-fpm 2>/dev/null || true
          systemctl enable --now nginx 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
          ${install_cmd}
          systemctl enable --now php-fpm 2>/dev/null || true
          systemctl enable --now nginx 2>/dev/null || true
        elif command -v apk >/dev/null 2>&1; then
          ${install_cmd}
          rc-update add php-fpm83 default 2>/dev/null || rc-update add php-fpm default 2>/dev/null || true
          rc-update add nginx default 2>/dev/null || true
          rc-service php-fpm83 start 2>/dev/null || rc-service php-fpm start 2>/dev/null || true
          rc-service nginx start 2>/dev/null || true
        fi
      " >/dev/null 2>&1; then
    log_fail "${name}: PHP install failed."
    failed=$((failed + 1)); continue
  fi

  php_ver="$(container_php_version "${name}" || true)"
  if [ -n "${php_ver}" ]; then
    log_ok "${name}: PHP ${php_ver} installed"
  else
    log_warn "${name}: PHP not detected on PATH after install"
  fi

  # --- Move onto the isolated bridge -----------------------------------------
  # The containers created earlier share the `default` profile, so a profile edit
  # moves all of them at once; anything with an instance-level eth0 is moved
  # directly. Both paths are handled by attach_to_network.
  log_info "${name}: moving to ${LAB_BRIDGE}"
  lxc config device remove "${name}" eth0 >/dev/null 2>&1 || true
  lxc config device add "${name}" eth0 nic network="${LAB_BRIDGE}" name=eth0 >/dev/null 2>&1 || {
    log_fail "${name}: could not attach to ${LAB_BRIDGE}"
    failed=$((failed + 1)); continue
  }

  lxc restart "${name}" >/dev/null 2>&1 || true
  wait_for_exec "${name}" >/dev/null 2>&1 || true
  fix_nic "${name}"

  ip="$(wait_for_ip "${name}" 30 || true)"
  if [ -n "${ip}" ]; then
    log_ok "${name}: on ${LAB_BRIDGE} as ${ip}"
  else
    log_warn "${name}: no IP yet on ${LAB_BRIDGE}; scripts/21-fix-nics.sh can retry"
  fi
done

log_step "Provisioning summary: ${created} created, ${skipped} skipped, ${failed} failed"

if [ "${failed}" -gt 0 ]; then
  log_fail "${failed} target(s) failed. Resolve before scanning; a half-built"
  log_fail "target produces misleading scan results."
  exit 1
fi

log_step "Done. Next: scripts/30-harden-targets.sh, then scripts/11-close-provisioning.sh"
