#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/21-fix-nics.sh
#
# Bring eth0 up on every target and re-acquire a DHCP lease.
#
# This exists as its own script because it is the single most common failure in
# this lab. After a target's network is reassigned, the container boots with
# eth0 administratively down and no address. Everything downstream then fails
# with a misleading symptom: the web server is up but nothing can reach it, and
# scans report connection refused rather than a real verdict.
#
# Safe to run repeatedly, and worth running whenever a scan returns "no route"
# or "connection refused" for a target that should be up.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

log_step "Repairing network interfaces on all targets"

fixed=0; ok=0; unreachable=0

for name in $(target_names); do
  container_exists "${name}" || continue

  state="$(lxc list "${name}" --format csv -c s 2>/dev/null | tr -d ' \r\n')"
  if [ "${state}" != "RUNNING" ]; then
    log_info "${name}: not running (${state}), starting"
    lxc start "${name}" >/dev/null 2>&1 || true
    wait_for_exec "${name}" >/dev/null 2>&1 || true
  fi

  before="$(container_ip "${name}" || true)"
  fix_nic "${name}"
  sleep 1
  after="$(container_ip "${name}" || true)"

  if [ -n "${after}" ]; then
    if [ "${before}" != "${after}" ]; then
      log_ok "${name}: address is now ${after} (was '${before}')"
      fixed=$((fixed + 1))
    else
      log_info "${name}: ${after}"
      ok=$((ok + 1))
    fi
  else
    log_warn "${name}: still no address"
    unreachable=$((unreachable + 1))
  fi
done

log_step "Interface repair summary: ${ok} already up, ${fixed} fixed, ${unreachable} still down"

if [ "${unreachable}" -gt 0 ]; then
  log_warn "Containers with no address cannot be scanned. Check that they are on"
  log_warn "${LAB_BRIDGE} and that dnsmasq is serving that subnet."
  exit 1
fi
