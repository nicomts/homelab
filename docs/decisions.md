# Decisions

Why the lab is built the way it is. Each entry says what I chose, why, and what I gave up.

## Dual boot, one disk per system

- **Decision:** Windows stays on the 960 GB SSD and Proxmox gets the 240 GB SSD. I choose the system from the BIOS boot menu.
- **Why:** I still use Windows on this PC. With each system on its own disk, if one breaks, the other still boots.
- **Trade-off:** The lab only runs while the PC is booted into Proxmox.

## An on-demand lab

- **Decision:** The lab is only on while I'm working on it. Nothing my household depends on runs there.
- **Why:** I work on it 3 to 6 hours a week, so there's no reason to keep it running all day. And since nobody else uses anything on it, turning it off or breaking it doesn't affect anyone.
- **Trade-off:** No always-on services, so things like monitoring or self-hosted apps have to wait for a machine that is on all day.

## ext4 instead of ZFS

- **Decision:** Proxmox is installed on `ext4` with LVM-thin for VM disks (the installer's default).
- **Why:** ZFS uses a lot of RAM for its cache, and with 16 GB I need that RAM for VMs.
- **Trade-off:** No ZFS features such as data checksums, compression or replication. VM snapshots still work on LVM-thin.

## Static IPs outside the DHCP range

- **Decision:** The router's DHCP hands out `192.168.0.2`–`.199`. Addresses `.200`–`.254` are for static IPs: Proxmox is `.200`, and `.201` is reserved for OPNsense's WAN in phase 2.
- **Why:** If a static IP is inside the DHCP range, the router can give the same address to another device, and the two devices end up in an IP conflict.
- **Trade-off:** Fewer addresses for DHCP (198), which is still plenty for a home.

## `home.arpa` as the local domain

- **Decision:** The Proxmox host is `pve.home.arpa`.
- **Why:** `home.arpa` is reserved for home networks ([RFC 8375](https://www.rfc-editor.org/rfc/rfc8375)), so it can never clash with a real domain on the internet.

## Public DNS servers on the Proxmox host

- **Decision:** Proxmox uses `1.1.1.1` (Cloudflare) as its first DNS server and `9.9.9.9` (Quad9) as its second.
- **Why:** My ISP router doesn't answer DNS queries; its DHCP hands out the ISP's DNS servers instead (see [writeup 01](../writeups/01-proxmox-dual-boot.md)). I could have used the ISP's servers, but Proxmox has a static configuration: if the ISP changed them, Proxmox wouldn't find out, while DHCP devices would. Public servers don't change, and two different providers mean one outage doesn't break name resolution.
- **Trade-off:** DNS queries from the lab go to Cloudflare and Quad9 instead of my ISP, and the lab uses different DNS servers than the rest of the house.

## Manual configuration first

- **Decision:** I configure everything by hand in the first stage, and automate it with Ansible later.
- **Why:** First understand what each step does, then automate it. The change also shows up in this repo.
- **Trade-off:** Rebuilding something by hand is slow until the Ansible stage.
