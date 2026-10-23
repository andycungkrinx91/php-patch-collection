#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/_common.sh
#
# Shared helpers. Sourced by every script in this directory; never executed
# directly. Loads lab.conf, sets up logging, and absorbs the two host quirks
# that break naive automation here (LXD binary path, containers booting with
# eth0 down after a network change).
# ==============================================================================
set -euo pipefail

LOCAL_LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lab.conf
. "${LOCAL_LAB_ROOT}/lab.conf"

# --- LXD binary ---------------------------------------------------------------
# Snap-installed LXD is not always on PATH for non-interactive shells.
if ! command -v lxc >/dev/null 2>&1; then
  for d in /snap/bin /usr/sbin /usr/bin; do
    if [ -x "${d}/lxc" ]; then PATH="${PATH}:${d}"; break; fi
  done
fi
command -v lxc >/dev/null 2>&1 || { echo "FATAL: lxc not found on PATH" >&2; exit 1; }

# --- Logging ------------------------------------------------------------------
_c_red=$'\033[0;31m'; _c_grn=$'\033[0;32m'; _c_ylw=$'\033[1;33m'
_c_blu=$'\033[0;34m'; _c_cyn=$'\033[0;36m'; _c_bld=$'\033[1m'; _c_off=$'\033[0m'

log_info() { echo "${_c_blu}[INFO]${_c_off}  $*"; }
log_ok()   { echo "${_c_grn}[ OK ]${_c_off}  $*"; }
log_warn() { echo "${_c_ylw}[WARN]${_c_off}  $*"; }
log_fail() { echo "${_c_red}[FAIL]${_c_off}  $*" >&2; }
log_step() { echo; echo "${_c_cyn}${_c_bld}>>> $*${_c_off}"; }

# --- Guards -------------------------------------------------------------------
is_lxc_root() { [ "$(id -u)" -eq 0 ]; }
running_as_lxd_group() { id -nG 2>/dev/null | tr ' ' '\n' | grep -qx lxd; }

require_lxd_access() {
  if ! is_lxc_root && ! running_as_lxd_group; then
    log_fail "User is neither root nor in the 'lxd' group."
    log_fail "Add yourself once, then re-login:  sudo usermod -aG lxd \$USER"
    exit 1
  fi
}

container_exists() { lxc info "$1" >/dev/null 2>&1; }
network_exists()   { lxc network show "$1" >/dev/null 2>&1; }
acl_exists()       { lxc network acl show "$1" >/dev/null 2>&1; }

# --- Target table helpers -----------------------------------------------------
# TARGETS entries are "name|image|memory|cpus|install_command".
target_names()  { for e in "${TARGETS[@]}"; do echo "${e%%|*}"; done; }
target_field()  { # target_field <name> <1-based field index>
  local want="$1" idx="$2" e
  for e in "${TARGETS[@]}"; do
    [ "${e%%|*}" = "${want}" ] || continue
    echo "${e}" | cut -d'|' -f"${idx}"
    return 0
  done
  return 1
}

# --- Container lifecycle ------------------------------------------------------
wait_for_exec() { # wait_for_exec <name> [tries]
  local name="$1" tries="${2:-60}" i=0
  while [ "${i}" -lt "${tries}" ]; do
    if lxc exec "${name}" -- /bin/true >/dev/null 2>&1; then return 0; fi
    i=$((i + 1)); sleep 2
  done
  log_fail "Container ${name} did not become exec-able after $((tries * 2))s"
  return 1
}

# Containers boot with eth0 DOWN after their network is reassigned. Ubuntu and
# Debian need ifup, CentOS need dhclient, Alpine needs udhcpc. Without
# this they come up with no IP and every later step fails confusingly.
fix_nic() { # fix_nic <name>
  local name="$1"
  lxc exec "${name}" -- sh -c '
    set -e
    ip link set eth0 up 2>/dev/null || true
    if command -v dhclient >/dev/null 2>&1; then
      dhclient -1 eth0 2>/dev/null || true
    fi
    if command -v udhcpc >/dev/null 2>&1; then
      udhcpc -i eth0 -b -q -n 2>/dev/null || true
    fi
    if command -v ifup >/dev/null 2>&1; then
      ifup --force eth0 2>/dev/null || true
    fi
    true
  ' >/dev/null 2>&1 || true
}

container_ip() { # container_ip <name>
  lxc list "$1" --format csv -c 4 2>/dev/null | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

wait_for_ip() { # wait_for_ip <name> [tries]
  local name="$1" tries="${2:-40}" i=0 ip
  while [ "${i}" -lt "${tries}" ]; do
    ip="$(container_ip "${name}" || true)"
    if [ -n "${ip}" ]; then echo "${ip}"; return 0; fi
    fix_nic "${name}"
    i=$((i + 1)); sleep 2
  done
  return 1
}

attach_to_network() { # attach_to_network <name> <bridge> [profile]
  local name="$1" bridge="$2" profile="${3:-}"
  if [ -n "${profile}" ]; then
    # Prefer the shared profile: one edit moves every instance that uses it.
    lxc profile device set "${profile}" eth0 network "${bridge}"
  else
    lxc config device remove "${name}" eth0 >/dev/null 2>&1 || true
    lxc config device add "${name}" eth0 nic network="${bridge}" name=eth0 >/dev/null
  fi
}

# --- Distro dispatch ----------------------------------------------------------
container_os_id() { # container_os_id <name>  -> debian|ubuntu|centos|alpine|unknown
  lxc exec "$1" -- sh -c '
    if [ -f /etc/alpine-release ]; then echo alpine
    elif [ -f /etc/centos-release ]; then echo centos
    elif [ -f /etc/debian_version ]; then
      if grep -qi ubuntu /etc/os-release 2>/dev/null; then echo ubuntu; else echo debian; fi
    else echo unknown; fi
  ' 2>/dev/null | tr -d "\r\n" || echo unknown
}

container_php_version() { # container_php_version <name>
  lxc exec "$1" -- sh -c 'php -r "echo PHP_VERSION;" 2>/dev/null' 2>/dev/null | tr -d "\r\n" || true
}

# --- Reporting ----------------------------------------------------------------
# Reports live on a host directory bind-mounted into the attacker box. Under the
# default LXD idmap the container's root maps to host uid 1000000.
ensure_reports_dir() {
  sudo -n mkdir -p "${REPORTS_HOST_DIR}" 2>/dev/null || mkdir -p "${REPORTS_HOST_DIR}"
  sudo -n chown "${IDMAP_HOST_UID}:${IDMAP_HOST_GID}" "${REPORTS_HOST_DIR}" 2>/dev/null || true
  sudo -n chmod 750 "${REPORTS_HOST_DIR}" 2>/dev/null || true
}

report_path() { # report_path <basename>
  echo "${REPORTS_HOST_DIR}/$1"
}

cleanup_container() { # cleanup_container <name>
  lxc delete -f "$1" >/dev/null 2>&1 || true
}
