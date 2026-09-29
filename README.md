# homelab

An on-demand Proxmox lab on my old desktop PC, built to practice networking and Linux
administration for NOC and sysadmin roles. The lab is isolated from my home network,
so nothing I break can take down the household internet. Every phase ends with a
writeup of what I did, what went wrong, and how I fixed it.

## Highlights

From [writeup 01 — Proxmox VE on a dual-boot PC](writeups/01-proxmox-dual-boot.md):

- Found that Windows was booting from an EFI System Partition on the disk I was about to
  wipe, and moved it to the Windows SSD with `diskpart` and `bcdboot` before installing.
- Diagnosed why Proxmox could reach the router but not resolve names: the ISP router
  doesn't answer DNS queries.
- Fixed Windows Recovery Environment, which broke after the boot partition move.

## Current setup

```mermaid
flowchart LR
    ISP["ISP router<br>192.168.0.1"] --- PVE["Proxmox VE 9.2<br>pve.home.arpa<br>192.168.0.200"]
    ISP --- MAC["MacBook<br>(admin)"]
    PVE -.-> OPN["OPNsense (phase 2)<br>WAN 192.168.0.201"]
```

| | |
| --- | --- |
| Host | Intel i7-7700K, 16 GB RAM |
| Lab storage | 240 GB SSD, dual-boot with Windows on a separate SSD |
| Hypervisor | Proxmox VE 9.2 on ext4 + LVM-thin |

Full details in [docs/hardware.md](docs/hardware.md). Why it's built this way:
[docs/decisions.md](docs/decisions.md).

## Progress

- [x] Phase 1 — Proxmox VE dual-boot install ([writeup](writeups/01-proxmox-dual-boot.md))
- [ ] Phase 2 — OPNsense and an isolated lab network
- [ ] Phase 3 — Linux servers (Ubuntu, Rocky), SSH, VM backup and restore
- [ ] Phase 4 — VLANs and MikroTik CHR site-to-site WireGuard
- [ ] Phase 5 — Break-and-fix incidents

## Repository layout

```text
docs/       hardware inventory and design decisions
writeups/   one writeup per phase, with screenshots in writeups/img/
```