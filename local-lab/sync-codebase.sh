#!/usr/bin/env bash
# ==============================================================================
# local-lab/sync-codebase.sh
#
# Mirror the code under test into local-lab/codebase/.
#
# Why a generated copy at all: the lab needs a self-contained tree it can push
# into containers, but the canonical patches live in cve-2026-109618-109619/ and
# must not be forked. Two hand-maintained copies drift, and a drifted patch is
# worse than no patch because it looks authoritative.
#
# So this copy is generated, never edited by hand. A manifest records the SHA-256
# of every file so drift is detectable:
#
#   ./sync-codebase.sh          # regenerate the mirror
#   ./sync-codebase.sh --check  # verify the mirror matches the source
#
# If --check reports drift, either the source changed (re-run to resync) or
# somebody edited the mirror (do not; edit the source).
# ==============================================================================
set -euo pipefail

LOCAL_LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LOCAL_LAB_ROOT}/.." && pwd)"

SOURCE_DIR="${REPO_ROOT}/cve-2026-109618-109619"
MIRROR_DIR="${LOCAL_LAB_ROOT}/codebase"
MANIFEST="${LOCAL_LAB_ROOT}/codebase.manifest.sha256"

MODE="${1:-sync}"

[ -d "${SOURCE_DIR}" ] || { echo "ERROR: source not found: ${SOURCE_DIR}" >&2; exit 1; }

# Only the parts the lab actually needs. The Docker recipes and docs stay in the
# canonical tree; copying them here would duplicate documentation, which is how
# two versions of the truth appear.
INCLUDE=(
  "universal-autopatch-109618-109619.sh"
  "compile-and-patch-vm-cve.sh"
  "test-cross-os-e2e.sh"
  "cve-2026-hardening.conf"
  "docker-image/cve-2026-hardening.ini"
  "tools"
)

write_manifest() {
  : > "${MANIFEST}"
  ( cd "${MIRROR_DIR}" && find . -type f -print0 \
      | sort -z \
      | xargs -0 sha256sum ) >> "${MANIFEST}"
}

case "${MODE}" in
  sync)
    echo ">>> mirroring ${SOURCE_DIR} -> ${MIRROR_DIR}"
    rm -rf "${MIRROR_DIR}"
    mkdir -p "${MIRROR_DIR}"
    for item in "${INCLUDE[@]}"; do
      if [ -e "${SOURCE_DIR}/${item}" ]; then
        mkdir -p "${MIRROR_DIR}/$(dirname "${item}")"
        cp -r "${SOURCE_DIR}/${item}" "${MIRROR_DIR}/${item}"
        echo "    + ${item}"
      else
        echo "    ! missing in source: ${item}"
      fi
    done
    write_manifest
    n="$(wc -l < "${MANIFEST}")"
    echo ">>> mirrored ${n} file(s); manifest written to codebase.manifest.sha256"
    ;;

  check)
    [ -d "${MIRROR_DIR}" ] || { echo "ERROR: no mirror yet; run ./sync-codebase.sh" >&2; exit 1; }
    [ -f "${MANIFEST}" ] || { echo "ERROR: no manifest; run ./sync-codebase.sh" >&2; exit 1; }

    echo ">>> verifying mirror against manifest"
    if ( cd "${MIRROR_DIR}" && sha256sum -c --quiet "$(realpath --relative-to="${MIRROR_DIR}" "${MANIFEST}")" 2>/dev/null ); then
      echo ">>> mirror intact"
    else
      # Fall back to a straight comparison when relative paths do not resolve.
      tmp="$(mktemp)"
      ( cd "${MIRROR_DIR}" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) > "${tmp}"
      if diff -q "${tmp}" "${MANIFEST}" >/dev/null; then
        echo ">>> mirror intact"
      else
        echo ">>> DRIFT DETECTED:"
        diff "${MANIFEST}" "${tmp}" | head -20
        rm -f "${tmp}"
        exit 1
      fi
      rm -f "${tmp}"
    fi

    # Also confirm the mirror still matches the live source.
    echo ">>> comparing mirror against source"
    drifted=0
    for item in "${INCLUDE[@]}"; do
      [ -e "${SOURCE_DIR}/${item}" ] || continue
      if [ -f "${SOURCE_DIR}/${item}" ]; then
        a="$(sha256sum < "${SOURCE_DIR}/${item}" | cut -d' ' -f1)"
        b="$(sha256sum < "${MIRROR_DIR}/${item}" 2>/dev/null | cut -d' ' -f1)"
        if [ "${a}" != "${b}" ]; then
          echo "    DIFF ${item}"
          drifted=$((drifted + 1))
        fi
      fi
    done
    if [ "${drifted}" -gt 0 ]; then
      echo ">>> ${drifted} file(s) differ from source. Re-run ./sync-codebase.sh"
      exit 1
    fi
    echo ">>> mirror matches source"
    ;;

  *)
    echo "Usage: $0 [sync|check]" >&2
    exit 1
    ;;
esac
