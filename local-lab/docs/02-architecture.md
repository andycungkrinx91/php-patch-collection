# Architecture

How the lab network is built, and why each decision was made the way it was.

---

## Topology

<p align="center">
  <img src="images/lab-topology.webp" alt="PHP2Shell Lab Architecture & Dual-Isolation Topology" width="100%" style="width: 100%; max-width: 100%; height: auto;">
</p>
<p align="center"><em>Figure 1: PHP2Shell Lab Dual-Isolation Network Topology (<a href="images/lab-topology.svg">View Vector SVG</a>)</em></p>

---

## Why two isolation mechanisms

`ipv4.nat=false` removes the masquerade rule. It does **not** stop the bridge from
forwarding packets between its subnet and the uplink. A Linux bridge routes;
NAT only rewrites addresses.

So a bridge with NAT disabled and no filtering still lets a container reach the
internet — it just does so with its own source address, which the upstream router
drops. Dropped by accident is not the same as contained by design: on a different
upstream, or with a router that accepts the address, it would work.

The default-deny ACL is the mechanism that actually denies. Both are required.

---

## Why the ACL rules are ordered the way they are

LXD hoists rules that specify no destination to the top of the generated ruleset.
Writing the catch-all first therefore produces a chain where the catch-all runs
before the scoped allow, and intra-subnet traffic is rejected along with
everything else. The lab looks isolated but the attacker box cannot reach any
target.

Rules are added in this order instead:

```
1.  egress allow  destination=10.77.77.0/24    # scoped allow
2.  egress reject                              # catch-all, last
3.  ingress allow                              # targets answer the attacker
```

---

## Why provisioning uses a separate bridge

Targets need package installs. The options were:

| Option | Problem |
|---|---|
| Enable NAT on the lab bridge temporarily | Opens a window where containment does not hold; a crash in that window leaves the lab exposed |
| Push packages over `lxc file` | Works, but apt/dnf still need a repository to resolve dependencies |
| **Separate temporary bridge** | No window at rest: the bridge is created from nothing and deleted back to nothing |

`labprov0` is created by `scripts/10-open-provisioning.sh` and destroyed by
`scripts/11-close-provisioning.sh`. There is no state in which a target sits on
both.

Its egress is allowlisted. LXD ACLs match IP and CIDR only, never hostnames, so
every mirror hostname is resolved to `/32` entries at creation time. Per the
containment plan, a domain that is not on the list is a reason to stop and ask —
never a reason to widen to `0.0.0.0/0`.

---

## Why the report directory has a specific owner

LXD's default idmap shifts container root to host uid `1000000`. A host directory
owned by `1000:1000` is not writable by the container's root, because from the
container's perspective that uid is unmapped.

```
chown 1000000:1000000 /opt/lab-reports/akatsuki
chmod 750             /opt/lab-reports/akatsuki
```

`/mnt/reports` is the **only** bind mount in any container. No target container
receives one at all. Verified with:

```bash
lxc exec akatsuki-lab -- findmnt -t none,autofs,bind
```

---

## Why containers boot with no network

After a container's NIC is reassigned, it starts with `eth0` administratively
down and no lease. Every downstream step then fails with a misleading symptom:
the web server is running, but nothing can reach it, and scans report connection
refused rather than a verdict.

The recovery differs by family, which is why `scripts/21-fix-nics.sh` exists as a
standalone script:

| Family | Command |
|---|---|
| Ubuntu / Debian | `ip link set eth0 up` + `ifup --force eth0` |
| CentOS | `ip link set eth0 up` + `dhclient eth0` |
| Alpine | `ip link set eth0 up` + `udhcpc -i eth0` |

---

## Storage

The `default` LXD pool uses the **`dir`** driver on this host, which has no
per-container quota support. A `-d root,size=20GiB` flag is accepted and silently
ignored. This is recorded as a known deviation rather than presented as an
enforced limit.

Targets are created with `limits.memory` and `limits.cpu` set — those are
cgroup-enforced and do work.

---

## Network path summary

| Path | Allowed | Mechanism |
|---|---|---|
| Container → container, same bridge | Yes | ACL rule 1 |
| Container → internet | **No** | NAT off + ACL rule 2 |
| Attacker → target | Yes | ACL rule 3 |
| Host → internet | Yes | Host route (needed for image pulls) |
| Container → host filesystem | No, except `/mnt/reports` | Single bind mount |
