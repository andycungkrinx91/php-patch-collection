#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/50-snapshot.sh
#
# Take a baseline snapshot of every container.
#
# Snapshots are the rollback point. Without one, a failed remediation leaves the
# container in an unknown state and the only recovery is rebuilding it, which
# also destroys the evidence of what went wrong.
#
# One caveat worth knowing: `lxc snapshot` freezes the container briefly. If a
# health check or collector is running, take the snapshot first and collect after,
# not the other way around.
#
# Idempotent: an existing snapshot of the same name is left alone.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

log_step "Taking baseline snapshots (${SNAPSHOT_PREFIX})"

taken=0; existing=0; failed=0

snapshot_one() { # snapshot_one <name>
  local name="$1"

  if ! container_exists "${name}"; then
    log_info "${name}: absent, skipping"
    return 0
  fi

  if lxc info "${name}" 2>/dev/null | grep -q "${SNAPSHOT_PREFIX}"; then
    log_info "${name}: snapshot ${SNAPSHOT_PREFIX} already exists"
    existing=$((existing + 1))
    return 0
  fi

  if lxc snapshot "${name}" "${SNAPSHOT_PREFIX}" >/dev/null 2>&1; then
    log_ok "${name}: ${SNAPSHOT_PREFIX}"
    taken=$((taken + 1))
  else
    log_fail "${name}: snapshot failed"
    failed=$((failed + 1))
  fi
}

for name in $(target_names); do snapshot_one "${name}"; done
snapshot_one "${ATTACKER_NAME}"

log_step "Snapshot summary: ${taken} taken, ${existing} already present, ${failed} failed"

# --- Verify -------------------------------------------------------------------
log_step "Verifying snapshots are listed"
verified=0; missing=0

for name in $(target_names) "${ATTACKER_NAME}"; do
  container_exists "${name}" || continue
  if lxc info "${name}" 2>/dev/null | grep -q "${SNAPSHOT_PREFIX}"; then
    verified=$((verified + 1))
  else
    log_warn "${name}: no ${SNAPSHOT_PREFIX} snapshot"
    missing=$((missing + 1))
  fi
done

log_info "${verified} container(s) have a baseline snapshot; ${missing} do not."

if [ "${failed}" -gt 0 ] || [ "${missing}" -gt 0 ]; then
  log_fail "Not every container has a rollback point. Fix this before remediating,"
  log_fail "because a failed change on a container with no snapshot is unrecoverable."
  exit 1
fi

log_ok "Every container has a rollback point."
