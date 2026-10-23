#!/usr/bin/env bash
# ==============================================================================
# local-lab/scripts/10-open-provisioning.sh
#
# Create the temporary provisioning bridge used to install packages, then
# close it again once the targets are built (scripts/11-close-provisioning.sh).
#
# Why a separate bridge instead of temporarily enabling NAT on the lab bridge:
# turning NAT on and off on the lab bridge means a window where the containment
# claim does not hold, and if the script dies in that window the lab is left
# exposed. A separate bridge that is created from nothing and deleted back to
# nothing has no such window: at rest, the lab bridge is the only network the
# targets know about.
#
# Egress is allowlisted because the bridge does have NAT. LXD ACLs match IP and
# CIDR only, never hostnames, so every mirror hostname is resolved to /32s here.
#
# Per the containment plan: if an install step needs a domain that is not on this
# list, STOP and confirm before widening it. Never widen to 0.0.0.0/0.
# ==============================================================================
# shellcheck source=_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_lxd_access

# Mirror hosts reachable during provisioning. Add a host only with justification.
PROV_ALLOWED_HOSTS="${PROV_ALLOWED_HOSTS:-
mirror.stream.centos.org mirrors.centos.org vault.centos.org
dl.fedoraproject.org download.fedoraproject.org
www.php.net
github.com raw.githubusercontent.com codeload.github.com objects.githubusercontent.com
pypi.org files.pythonhosted.org rubygems.org
proxy.golang.org sum.golang.org storage.googleapis.com
deb.debian.org security.debian.org
archive.ubuntu.com security.ubuntu.com old-releases.ubuntu.com
}"

log_step "Opening provisioning bridge ${PROV_BRIDGE} (${PROV_SUBNET})"

# Tear down anything left over from an interrupted run so this is repeatable.
for c in $(lxc list --format csv -c n 2>/dev/null || true); do
  ip="$(container_ip "${c}" || true)"
  case "${ip}" in 10.66.66.*) lxc network detach "${PROV_BRIDGE}" "${c}" >/dev/null 2>&1 || true ;; esac
done
lxc network delete "${PROV_BRIDGE}" >/dev/null 2>&1 || true
lxc network acl delete "${PROV_ACL}" >/dev/null 2>&1 || true

lxc network create "${PROV_BRIDGE}" \
  ipv4.address="${PROV_GATEWAY}/24" \
  ipv4.nat=true \
  ipv4.dhcp=true \
  ipv4.firewall=true \
  ipv6.address=none
log_ok "Bridge ${PROV_BRIDGE} created (NAT on, temporary)."

lxc network acl create "${PROV_ACL}"

# Resolve every allowed hostname to its A records. Duplicates are collapsed.
addr_file="$(mktemp)"
trap 'rm -f "${addr_file}"' EXIT
for h in ${PROV_ALLOWED_HOSTS}; do
  getent ahostsv4 "${h}" 2>/dev/null | awk '{print $1}' >> "${addr_file}" || true
done
sort -u -o "${addr_file}" "${addr_file}"
addr_count="$(grep -c . "${addr_file}" || true)"
log_info "Resolved ${addr_count} unique mirror addresses."

while read -r a; do
  [ -n "${a}" ] || continue
  lxc network acl rule add "${PROV_ACL}" egress action=allow destination="${a}/32" >/dev/null
done < "${addr_file}"

# Catch-alls last. Order matters: LXD hoists destination-less rules to the top,
# so an early reject would kill the intra-subnet allow above it.
lxc network acl rule add "${PROV_ACL}" egress action=allow destination="${PROV_SUBNET}" >/dev/null
lxc network acl rule add "${PROV_ACL}" egress action=reject >/dev/null
lxc network acl rule add "${PROV_ACL}" ingress action=allow >/dev/null

lxc network set "${PROV_BRIDGE}" security.acls="${PROV_ACL}"
lxc network set "${PROV_BRIDGE}" security.acls.default.egress.action=reject
lxc network set "${PROV_BRIDGE}" security.acls.default.ingress.action=allow

log_ok "Provisioning bridge ready: ${addr_count} allowed destinations, everything else rejected."
log_warn "This bridge is TEMPORARY. Close it with scripts/11-close-provisioning.sh when installs finish."
