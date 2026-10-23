#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/70-scan-all.sh
#
# Run the Source B verification scanner against every target and produce a
# coverage table.
#
# ------------------------------------------------------------------------------
# WHAT THE SCANNER ACTUALLY MEASURES
# ------------------------------------------------------------------------------
# Source B is a crash-based probe. It sends a malformed multipart body and
# treats HTTP 502/503/504 as evidence of a crash, which it reports as VULNERABLE.
# It reports FIXED / NO SIGNAL when the request is handled normally.
#
# This means:
#   - NO SIGNAL means "no crash observed", NOT "provably immune".
#   - A correctly PATCHED host can still legitimately return 502, because the
#     upstream fix terminates the worker. That case is discussed at length in
#     docs/04-oracle-finding.md and must be checked against the FPM log before
#     it is called a failure.
#
# The scan is run from the attacker box, over the isolated bridge, against the
# declared target list only. Anything else the scanner surfaces is recorded as
# out-of-scope and not tested.
#
# Prerequisites: targets provisioned, hardened, and the provisioning bridge closed.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

container_exists "${ATTACKER_NAME}" || { log_fail "${ATTACKER_NAME} does not exist."; exit 1; }

# Refuse to scan while the provisioning bridge is still up: a target that can
# still reach the internet is not the target under test.
if network_exists "${PROV_BRIDGE}"; then
  log_fail "Provisioning bridge ${PROV_BRIDGE} is still up."
  log_fail "Run scripts/11-close-provisioning.sh first; scans taken in this state are invalid."
  exit 1
fi

out_json="${REPORTS_MOUNT_PATH}/source-b-scan-${LAB_DATE}.json"
out_log="${REPORTS_MOUNT_PATH}/source-b-scan-${LAB_DATE}.log"

log_step "Scanning ${#TARGETS[@]} targets from ${ATTACKER_NAME}"

# Build the target list inside the attacker box so the loop runs there, not on
# the host. Keeps the scan surface entirely on the isolated network.
targets_file="$(mktemp)"
trap 'rm -f "${targets_file}"' EXIT

for entry in "${TARGETS[@]}"; do
  name="${entry%%|*}"
  container_exists "${name}" || continue
  state="$(lxc list "${name}" --format csv -c s 2>/dev/null | tr -d ' \r\n')"
  [ "${state}" = "RUNNING" ] || continue
  ip="$(container_ip "${name}" || true)"
  [ -n "${ip}" ] && echo "${ip}|${name}" >> "${targets_file}"
done

count="$(grep -c . "${targets_file}" || true)"
if [ "${count}" -eq 0 ]; then
  log_fail "No reachable targets found. Check scripts/21-fix-nics.sh."
  exit 1
fi
log_info "${count} reachable target(s)"

# Push the target list into the attacker box.
lxc file push "${targets_file}" "${ATTACKER_NAME}/root/scan-targets.txt" >/dev/null 2>&1

# Persist the list into the shared reports mount from inside the container.
# The host cannot write it directly: the directory is owned by the container's
# mapped uid (1000000) with mode 750, leaving the host only group read/execute.
lxc exec "${ATTACKER_NAME}" -- \
  cp /root/scan-targets.txt "${REPORTS_MOUNT_PATH}/scan-targets-${LAB_DATE}.txt"

log_info "Running scanner inside ${ATTACKER_NAME}..."

lxc exec "${ATTACKER_NAME}" -- bash -c "
  set -e
  if [ ! -f /opt/php2shell-scanner/scanner.py ]; then
    echo 'SCANNER_MISSING'
    exit 0
  fi
  : > '${out_json}'
  : > '${out_log}'
  while IFS='|' read -r ip name; do
    url=\"http://\${ip}/index.php\"
    line=\"\$(python3 /opt/php2shell-scanner/scanner.py --url \"\${url}\" 2>&1 | tr '\n' ' ')\"
    echo \"\${name}|\${url}|\${line}\" | tee -a '${out_log}'
  done < /root/scan-targets.txt
" 2>&1 | rtk tail -40

log_step "Scan complete. Raw log: ${out_log}"

# --- Summarise ----------------------------------------------------------------
log_step "Verdict summary"

results="${REPORTS_HOST_DIR}/source-b-scan-${LAB_DATE}.log"
if [ ! -f "${results}" ]; then
  log_fail "No scan log produced at ${results}"
  exit 1
fi

nv=0; vuln=0; other=0
while IFS='|' read -r name url rest; do
  case "${rest}" in
    *"NOT VULNERABLE"*|*"NO SIGNAL"*|*"FIXED"*) log_ok  "${name}: NOT VULNERABLE"; nv=$((nv + 1)) ;;
    *"VULNERABLE"*)                              log_fail "${name}: VULNERABLE";     vuln=$((vuln + 1)) ;;
    *)                                           log_warn "${name}: ${rest}";        other=$((other + 1)) ;;
  esac
done < "${results}"

echo
log_info "NOT VULNERABLE: ${nv}   VULNERABLE: ${vuln}   INCONCLUSIVE: ${other}"

if [ "${vuln}" -gt 0 ]; then
  log_fail "${vuln} target(s) still report VULNERABLE."
  log_info "Before treating these as failures, check the FPM log for each:"
  log_info "  lxc exec <target> -- journalctl -u php*-fpm --no-pager -n 40"
  log_info "A 'child exited with code 1' with no segfault is the oracle case, not a regression."
  exit 1
fi

if [ "${other}" -gt 0 ]; then
  log_warn "${other} target(s) returned no clear verdict."
  exit 1
fi

log_ok "All ${nv} target(s) report NOT VULNERABLE."
