# homelab

An on-demand Proxmox lab on my old desktop PC, built to practice networking and Linux
administration for NOC and sysadmin roles. The lab is isolated from my home network,
so nothing I break can take down the household internet. Every phase ends with
writeups of what I did, what went wrong, and how I fixed it.

## Highlights

From [writeup 07 — Two branch routers and a WireGuard tunnel](writeups/07-site-to-site-wireguard-mikrotik.md):

- Ran two MikroTik CHR routers as branch offices joined by a WireGuard tunnel with static routes. Proved the tunnel from both sides: one hop and no loss from one branch LAN to the other, and only UDP between the two routers on the network in between.
- Hardened RouterOS like the servers (my own user with a key, `admin` disabled, unused services off) and kept each router's configuration in the repository as an export, without private keys.
- Moved each router from its DHCP address to a fixed one over SSH without locking myself out, by opening the new session before removing the old address.

From [writeup 06 — A clients VLAN on the lab bridge](writeups/06-vlans-and-firewall-rules.md):

- Added a clients network as VLAN 20 on the same Proxmox bridge, with the firewall's card as a trunk and the client on an access port, and captured the 802.1Q tag on one side and its absence on the other with `tcpdump`.
- Wrote rules that let clients use one internal website and the internet, and block and log everything else private with a single alias. Tested each rule and matched every blocked test to the firewall log.

From [writeup 05 — Backups I actually restored](writeups/05-vm-backup-and-restore.md):

- Set up weekly Proxmox backups of every guest, with a second copy on a removable NTFS disk
  that Proxmox treats as offline when it's unplugged, so a backup can't land on an empty folder.
- Deleted a VM and restored it from the external disk in about 6 minutes, with the same IP and
  SSH host key. The backup log also exposed a failed file-system freeze and a container I had
  forgotten to delete.

From [writeup 04 — A Samba share that SELinux blocked](writeups/04-samba-vs-selinux.md):

- Traced a Samba "permission denied" with correct Unix permissions to an SELinux label, reading
  the audit log, and fixed it in the policy with `semanage fcontext` and `restorecon` instead of
  turning SELinux off.

From [writeup 03 — Two Linux servers, one baseline](writeups/03-linux-server-baseline.md):

- Built the same baseline on Ubuntu Server and Rocky Linux (static IP, SSH with keys only,
  automatic security updates, a host firewall) and documented what changes between the two
  families.
- Found that a line in `sshd_config` wouldn't have turned off password logins, because an
  installer file set it first and `sshd` keeps the first value. Checked the result with `sshd -T`.

From [writeup 02 — An isolated lab network behind an OPNsense VM](writeups/02-opnsense-isolated-lab.md):

- Built an isolated lab network on a Proxmox bridge with no physical port, with an
  OPNsense VM as the only way in or out: DHCP, recursive DNS, NAT, and a logged rule
  that blocks the lab from every device at home.
- Traced repeated lockouts from the firewall's web interface to an alias that a
  diagnostics button had emptied, using the firewall log, the address tables the
  firewall had actually loaded, and the configuration history. It also showed that my
  first explanation was wrong.
- Tested the design with a throwaway container: the lab reaches the internet, can't
  reach the house, and the house keeps working with the firewall off.

From [writeup 01 — Proxmox VE on a dual-boot PC](writeups/01-proxmox-dual-boot.md):

- Found that Windows was booting from an EFI System Partition on the disk I was about to
  wipe, and moved it to the Windows SSD with `diskpart` and `bcdboot` before installing.
- Diagnosed why Proxmox could reach the router but not resolve names: the ISP router
  doesn't answer DNS queries.
- Fixed Windows Recovery Environment, which broke after the boot partition move.

## Current setup

```mermaid
flowchart LR
    NET((Internet)) --- ISP
    subgraph HOME["Home network 192.168.0.0/24"]
        ISP["ISP router<br>192.168.0.1"]
        MAC["MacBook (admin)<br>192.168.0.109"]
        PVE["Proxmox VE 9.2<br>pve.home.arpa<br>192.168.0.200"]
    end
    ISP --- FW["fw-01 (OPNsense)<br>WAN 192.168.0.201<br>LAN 10.10.10.1<br>CLIENTS 10.10.20.1"]
    subgraph LAB["Lab network 10.10.10.0/24"]
        WEB["web-01 (Ubuntu)<br>nginx<br>10.10.10.10"]
        FILES["files-01 (Rocky)<br>Samba<br>10.10.10.11"]
        CHRA["chr-a (MikroTik)<br>10.10.10.21"]
        CHRB["chr-b (MikroTik)<br>10.10.10.22"]
    end
    subgraph CLI["CLIENTS VLAN 20<br>10.10.20.0/24"]
        CLIENT["client-01 (Debian)"]
    end
    FW --- WEB
    FW --- FILES
    FW --- CHRA
    FW --- CHRB
    FW --- CLIENT
    CHRA -.-|WireGuard| CHRB
    CHRA --- BRA["Branch A<br>10.20.1.0/24"]
    CHRB --- BRB["Branch B<br>10.20.2.0/24"]
```

| | |
| --- | --- |
| Host | Intel i7-7700K, 16 GB RAM |
| Lab storage | 240 GB SSD, dual-boot with Windows on a separate SSD |
| Hypervisor | Proxmox VE 9.2 on ext4 + LVM-thin |
| Firewall | OPNsense 26.7.5 VM (`fw-01`), the only path between the lab and the house |
| Servers | `web-01` (Ubuntu Server 26.04.1 LTS, nginx) and `files-01` (Rocky Linux 10.2, Samba) |
| Networks | The lab network, plus a clients VLAN (`CLIENTS`, VLAN 20) on the same bridge, filtered by `fw-01` |
| Branch routers | `chr-a` and `chr-b`, MikroTik CHR (RouterOS 7.24.5), joined by a WireGuard tunnel |
| Backups | Weekly Proxmox backups of every guest, plus a copy on an external USB disk |

Full details in [docs/hardware.md](docs/hardware.md) and [docs/network.md](docs/network.md).
Why it's built this way: [docs/decisions.md](docs/decisions.md).

## Progress

- [x] Phase 1 — Proxmox VE dual-boot install ([writeup](writeups/01-proxmox-dual-boot.md))
- [x] Phase 2 — OPNsense and an isolated lab network ([writeup](writeups/02-opnsense-isolated-lab.md))
- [x] Phase 3 — Linux servers (Ubuntu, Rocky), SSH, VM backup and restore (writeups [03](writeups/03-linux-server-baseline.md), [04](writeups/04-samba-vs-selinux.md), [05](writeups/05-vm-backup-and-restore.md))
- [x] Phase 4 — VLANs and MikroTik CHR site-to-site WireGuard (writeups [06](writeups/06-vlans-and-firewall-rules.md), [07](writeups/07-site-to-site-wireguard-mikrotik.md)). Optional OSPF over the tunnel still pending
- [ ] Phase 5 — Break-and-fix incidents

## Repository layout

```text
configs/    configuration files from the lab, without secrets
docs/       hardware inventory, network map and design decisions
writeups/   writeups for each phase, with screenshots in writeups/img/
```
