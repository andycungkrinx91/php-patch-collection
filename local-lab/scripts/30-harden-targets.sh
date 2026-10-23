#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/30-harden-targets.sh
#
# Apply the runtime hardening drop-in to every target.
#
# ------------------------------------------------------------------------------
# WHY THESE CAPS AND NOT OTHERS
# ------------------------------------------------------------------------------
# The php2shell probe sends a multipart body containing hundreds of thousands of
# `x:` part-header lines, alongside a field name nested roughly 62 levels deep in
# array brackets. The nesting is deliberately kept under PHP's default
# max_input_nesting_level of 64, so raising that default is not what stops it.
#
# Three PHP-level caps each independently prevent the probe from reaching the
# vulnerable parser:
#
#   max_input_nesting_level = 20   rejects the nested field name outright
#   max_input_vars          = 200  rejects the flood of part headers
#   post_max_size           = 900K discards the oversized body before parsing
#
# ------------------------------------------------------------------------------
# THE ONE MISTAKE TO AVOID
# ------------------------------------------------------------------------------
# Do NOT satisfy this with Nginx's client_max_body_size. Nginx answers 413 before
# PHP ever sees the request. The probe never completes, and the scanner reports
# INCONCLUSIVE instead of a clean verdict, which reads as "blocked" rather than
# "mitigated".
#
# Measured probe sizes: 1 MiB, 8 MiB and 20 MiB
# (PROBES = ((1, 4000), (8, 1020), (20, 1020)) in scanner.py; the first tuple
# element is the size in MiB). Any finite nginx cap below 20 MiB therefore breaks
# the scan. Set client_max_body_size 0 (unlimited) and let PHP's post_max_size be
# the layer that discards the body.
#
# ------------------------------------------------------------------------------
# VERDICT INTERPRETATION
# ------------------------------------------------------------------------------
# A correctly hardened target returns HTTP 200 with a warning. A correctly
# PATCHED target may return 502. That is not a failure. Both CVEs corrupt Zend
# state such that the upstream fix calls zend_mm_safe_error_ex(), which is
# ZEND_NORETURN and terminates the worker via _exit(1) at Zend/zend_alloc.c:403.
# An FPM worker dying produces 502, which a crash-based scanner reads as
# vulnerable. Check the FPM log: a patched build shows
#   "child <pid> exited with code 1"
# with no segfault, no signal 11, and no core dumped. See docs/04-oracle-finding.md.
#
# Idempotent: rewrites the drop-in each run.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

HARDENING_INI_NAME="99-cve-2026-hardening.ini"

log_step "Applying runtime hardening caps to all targets"

applied_caps() {
  cat <<EOF
; CVE-2026-109618 / CVE-2026-109619 runtime hardening
; Applied by local-lab/scripts/30-harden-targets.sh
;
; These caps prevent the php2shell multipart probe from reaching the vulnerable
; parser. They are defence in depth: the source patch is the fix, this is the
; cap that holds if the binary cannot be rebuilt.

; Reject deeply nested field names (probe uses ~62 levels; default cap is 64).
max_input_nesting_level = ${CAP_MAX_INPUT_NESTING_LEVEL}

; Reject the flood of multipart part-header lines.
max_input_vars = ${CAP_MAX_INPUT_VARS}

; Bound parse time so a large body cannot hold a worker.
max_input_time = ${CAP_MAX_INPUT_TIME}

; Discard oversized bodies at the PHP layer. Must stay BELOW the web server's
; own body limit so PHP returns a normal response instead of a 413.
post_max_size = ${CAP_POST_MAX_SIZE}

; The vulnerable path is reached through the upload-progress callback.
session.upload_progress.enabled = ${CAP_UPLOAD_PROGRESS}
session.upload_progress.cleanup = On
EOF
}

# Every conf.d location the autopatch engine knows about, plus this lab's own.
conf_d_for() { # conf_d_for <name> <os_id> <php_version>
  local name="$1" os="$2" ver="$3" nodot="${3//./}"
  local candidates=()

  case "${os}" in
    centos)
      candidates=(/etc/php.d /etc/php-fpm.d "/etc/opt/remi/php${nodot}/php.d") ;;
    alpine)
      candidates=("/etc/php${nodot}/conf.d" /etc/php/conf.d) ;;
    *)
      candidates=("/etc/php/${ver}/fpm/conf.d" /etc/php5/fpm/conf.d "/etc/php/${ver}/conf.d" /etc/php/conf.d) ;;
  esac

  for d in "${candidates[@]}"; do
    if lxc exec "${name}" -- test -d "${d}" >/dev/null 2>&1; then echo "${d}"; return 0; fi
  done

  # Nothing exists yet: create the platform-appropriate default.
  case "${os}" in
    centos)      echo "/etc/php.d" ;;
    alpine)      echo "/etc/php${nodot}/conf.d" ;;
    *)           echo "/etc/php/${ver}/fpm/conf.d" ;;
  esac
}

ok=0; failed=0
hardening_body="$(applied_caps)"

for name in $(target_names); do
  container_exists "${name}" || { log_info "${name}: absent, skipping"; continue; }

  state="$(lxc list "${name}" --format csv -c s 2>/dev/null | tr -d ' \r\n')"
  [ "${state}" = "RUNNING" ] || { log_warn "${name}: not running, skipping"; continue; }

  os="$(container_os_id "${name}")"
  ver="$(container_php_version "${name}" || true)"

  if [ -z "${ver}" ]; then
    log_warn "${name}: no PHP detected; skipping (is PHP installed?)"
    failed=$((failed + 1)); continue
  fi

  cdir="$(conf_d_for "${name}" "${os}" "${ver}")"

  if printf '%s\n' "${hardening_body}" | lxc exec "${name}" -- bash -c "
        set -e
        mkdir -p '${cdir}'
        cat > '${cdir}/${HARDENING_INI_NAME}'
      " >/dev/null 2>&1; then
    log_ok "${name}: PHP ${ver} (${os}) -> ${cdir}/${HARDENING_INI_NAME}"
    applied=$((ok + 1))
  else
    log_fail "${name}: could not write the drop-in to ${cdir}"
    failed=$((failed + 1))
  fi

  # Restart FPM so the drop-in takes effect. The unit is named differently on
  # every family, so try each rather than guessing.
  lxc exec "${name}" -- bash -c '
    for u in php-fpm php5-fpm php7.0-fpm php7.2-fpm php7.4-fpm php8.0-fpm php8.1-fpm php8.3-fpm; do
      if systemctl list-unit-files "${u}.service" >/dev/null 2>&1 && \
         systemctl is-enabled "${u}.service" >/dev/null 2>&1; then
        systemctl restart "${u}.service" 2>/dev/null || true
      fi
    done
    for u in php-fpm83 php-fpm; do
      rc-service "${u}" restart 2>/dev/null || true
    done
    true
  ' >/dev/null 2>&1 || true
done

# --- Verify the caps are live, not just on disk -------------------------------
log_step "Verifying caps are live in the running FPM SAPI"

# Reading the CLI SAPI does not prove anything: the drop-in may sit in a conf.d
# directory the FPM binary never reads. Query FPM itself.
verify_failed=0
for name in $(target_names); do
  container_exists "${name}" || continue
  state="$(lxc list "${name}" --format csv -c s 2>/dev/null | tr -d ' \r\n')"
  [ "${state}" = "RUNNING" ] || continue

  live="$(lxc exec "${name}" -- bash -c '
      for b in php-fpm php-fpm8.1 php-fpm8.3 php-fpm7.4 php-fpm7.2 php-fpm7.0 php-fpm5.5; do
        if command -v "$b" >/dev/null 2>&1; then
          "$b" -i 2>/dev/null | grep -m1 "max_input_nesting_level"
          exit 0
        fi
      done
    ' 2>/dev/null | tr -d '\r' || true)"

  if echo "${live}" | grep -q "${CAP_MAX_INPUT_NESTING_LEVEL}"; then
    log_ok "${name}: FPM reports ${live##*= } for max_input_nesting_level"
  else
    log_warn "${name}: could not confirm via FPM SAPI (got: '${live}')"
    verify_failed=$((verify_failed + 1))
  fi
done

log_step "Hardening summary: ${ok} applied, ${failed} failed, ${verify_failed} unverified via FPM"

if [ "${failed}" -gt 0 ]; then
  log_fail "At least one target has no hardening applied."
  exit 1
fi

log_info "Note: a patched host may still answer 502 with these caps. Read"
log_info "      docs/04-oracle-finding.md before treating 502 as a failure."
