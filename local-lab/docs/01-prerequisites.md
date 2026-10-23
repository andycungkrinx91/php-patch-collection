# Prerequisites

What the host needs before `setup.sh` will work, and how to verify each item.

Run this first:

```bash
cd local-lab
./setup.sh preflight
```

It checks everything below and reports pass, warning, or failure. A failure means
stop; the four checks it performs exist because each one costs an hour of
confusing debugging when missed.

---

## 1. LXD

**Required:** LXD ≥ 5.0, and your user either root or in the `lxd` group.

```bash
lxc version
id -nG | tr ' ' '\n' | grep -x lxd
```

If the group is missing:

```bash
sudo usermod -aG lxd "$USER"
# log out and back in — group changes do not apply to a running session
```

LXD ≥ 5.0 is needed for network ACLs (`lxc network acl`). On older releases the
containment model in this lab cannot be built.

---

## 2. Disk

**Required:** ~40 GiB free.

```bash
df -h /
```

Fifteen containers plus their snapshots needs roughly 20 GiB. The headroom above
that covers image layers and the PHP build trees, which are large and are kept
until the build finishes.

### Storage driver caveat

```bash
lxc storage show default -c driver
```

If the driver is **`dir`** (the common default), per-container rootfs quotas are
**not enforceable**. Passing `-d root,size=20GiB` is accepted and silently
ignored. The lab records this as a known deviation rather than claiming a limit
that does not exist. `limits.memory` and `limits.cpu` are cgroup-enforced and do
work.

---

## 3. Firewall read access

**Required for containment verification only.** Not needed to build or scan.

`nft list ruleset` needs root. Running the whole lab as root is not required and
not recommended, so the lab uses a narrowly scoped passwordless rule for the
specific read commands it needs.

Create `/etc/sudoers.d/konoha-firewall-readonly`:

```
Cmnd_Alias FW_READ = /usr/sbin/nft list ruleset, /usr/sbin/iptables -S, /usr/sbin/iptables -t filter -S, /usr/sbin/iptables -t nat -S

andycungkrinx ALL=(root) NOPASSWD: FW_READ
```

Adjust the username. Then:

```bash
sudo install -m 0440 -o root -g root \
  /etc/sudoers.d/konoha-firewall-readonly \
  /etc/sudoers.d/konoha-firewall-readonly

sudo visudo -cf /etc/sudoers.d/konoha-firewall-readonly   # must print "parsed OK"
sudo -n nft list ruleset >/dev/null && echo "read access OK"
```

`visudo -c` validates before the file takes effect, so a syntax error cannot lock
you out.

**If you skip this:** the lab still builds and scans. It reports the containment
check as unverified rather than passing it. A verification that was not performed
is not reported as a pass.

Without the drop-in, verify manually:

```bash
sudo nft list ruleset | grep 10.77.77
```

You want to see the ACL reject chain and **no** `masquerade` rule.

---

## 4. Docker

**Optional.** Needed only for `test-cross-os-e2e.sh`, which runs the
configuration-drop-in regression suite in Docker containers. The main lab does
not use Docker.

```bash
docker info >/dev/null && echo "docker OK"
```

---

## 5. Host internet

**Required.** Image pulls and package provisioning happen over the host uplink.

The **lab** has no internet. The host does. That asymmetry is the design.

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://images.linuxcontainers.org
```

---

## 6. Images

The lab resolves images at build time. Check availability first — two of them are
easy to get wrong.

```bash
for i in ubuntu:14.04 ubuntu:16.04 ubuntu:18.04 ubuntu:20.04 ubuntu:22.04 \
         images:debian/12 images:centos/9-Stream \
         images:alpine/3.21 images:alpine/3.22; do
  lxc image info "$i" >/dev/null 2>&1 && echo "ok   $i" || echo "MISS $i"
done
```

### Two traps

**Ubuntu images are on the `ubuntu:` remote, not `images:`.** `images:ubuntu/18.04`
returns 404. Use `ubuntu:18.04`.

**CentOS 7 and 8 no longer exist upstream.** CentOS 7 and 8 are EOL and their
images have been removed from `images.linuxcontainers.org`. Only CentOS Stream 9
and 10 remain there. This lab uses Stream 9 and 10 as a result. CentOS 7 and 8
coverage, where wanted, comes from the Docker suite
(`test-cross-os-e2e.sh centos7`), which pulls `centos:7` and `centos:8` from
Docker Hub and repoints them at `vault.centos.org`.

Verify:

```bash
curl -s https://images.linuxcontainers.org/streams/v1/images.json \
  | python3 -c 'import json,sys; print([k for k in json.load(sys.stdin)["products"] if "centos" in k.lower()])'
```

Only `centos:9-Stream` and `centos:10-Stream` are returned. This is expected.

---

## 7. Time and patience

A full build is 30–60 minutes, dominated by image downloads and, on hosts that
rebuild PHP, compilation. `preflight` takes seconds. Run it first.

---

## Verifying the host afterwards

```bash
# Host still has internet (it should)
curl -s -o /dev/null -w '%{http_code}\n' https://www.php.net

# No masquerade for the lab subnet (there should be none)
sudo nft list ruleset | grep 10.77.77 | grep masquerade

# Lab bridge is the only one carrying lab traffic
lxc network show labbr0 | grep -E 'ipv4.address|ipv4.nat|security.acls'
```

Expected: `200`, no output from the grep, and `ipv4.nat: "false"`.
