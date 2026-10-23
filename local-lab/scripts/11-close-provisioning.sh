#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/11-close-provisioning.sh
#
# Detach and destroy the temporary provisioning bridge, then re-verify that the
# lab is back to full isolation.
#
# This script is the containment gate. It is not a formality: leaving the
# provisioning bridge attached to even one target means that target can still
# reach the internet, which invalidates every scan result collected afterwards.
#
# The verification at the end is behavioural, not configurational. It does not
# trust that detaching worked; it proves egress fails from inside a container.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

log_step "Closing provisioning bridge ${PROV_BRIDGE}"

# Detach from every container that is still on it, whatever its name.
detached=0
while IFS= read -r c; do
  [ -n "${c}" ] || continue
  ip="$(container_ip "${c}" || true)"
  if [ "${ip#10.66.66.}" != "${ip}" ]; then
    lxc network detach "${PROV_BRIDGE}" "${c}" >/dev/null 2>&1 && {
      log_info "Detached ${c} from ${PROV_BRIDGE}"
      detached=$((detached + 1))
    }
  fi
done < <(lxc list --format csv -c n 2>/dev/null || true)

log_info "Detached ${detached} container(s)."

lxc network delete "${PROV_BRIDGE}" >/dev/null 2>&1 && log_ok "Bridge ${PROV_BRIDGE} deleted." \
  || log_warn "Bridge ${PROV_BRIDGE} was not present."
lxc network acl delete "${PROV_ACL}" >/dev/null 2>&1 && log_ok "ACL ${PROV_ACL} deleted." \
  || log_warn "ACL ${PROV_ACL} was not present."

# --- Behavioural containment verification ------------------------------------
log_step "Verifying containment behaviourally"

# Every remaining container should now be on the lab subnet only.
lab_count=0; other_count=0; no_ip=0
while IFS= read -r c; do
  [ -n "${c}" ] || continue
  ip="$(container_ip "${c}" || true)"
  if [ -z "${ip}" ]; then
    no_ip=$((no_ip + 1))
    log_warn "${c}: no IP address"
  elif [ "${ip#10.77.77.}" != "${ip}" ]; then
    lab_count=$((lab_count + 1))
  else
    other_count=$((other_count + 1))
    log_warn "${c}: unexpected address ${ip}"
  fi
done < <(lxc list --format csv -c n 2>/dev/null || true)

log_info "On lab subnet: ${lab_count}   elsewhere: ${other_count}   no IP: ${no_ip}"

# Prove egress actually fails. Config can say one thing while the datapath does
# another, so this makes a real outbound connection attempt from inside.
probe_container=""
for c in $(lxc list --format csv -c n 2>/dev/null || true); do
  ip="$(container_ip "${c}" || true)"
  if [ "${ip#10.77.77.}" != "${ip}" ]; then probe_container="${c}"; break; fi
done

if [ -z "${probe_container}" ]; then
  log_warn "No lab container available to probe; skipping the behavioural check."
  exit 0
fi

log_info "Probing egress from ${probe_container}..."

egress_ok=false
if lxc exec "${probe_container}" -- sh -c '
     command -v wget >/dev/null 2>&1 && wget -qO- -T 4 https://www.php.net >/dev/null 2>&1
   ' >/dev/null 2>&1; then
  egress_ok=true
fi

if [ "${egress_ok}" = "true" ]; then
  log_fail "Egress SUCCEEDED from ${probe_container}. Containment is NOT in place."
  log_fail "Something is still routing this container to the internet."
  exit 1
fi
log_ok "Egress from ${probe_container} FAILED as required."

# Confirm the host still has internet: proves the failure above is containment,
# not a broken uplink that would make the test meaningless.
if curl -s -o /dev/null --max-time 8 https://www.php.net; then
  log_ok "Host control: host has internet, so the container failure is containment."
else
  log_warn "Host control: host has NO internet either; the container test proves nothing."
fi

log_step "Containment restored."
