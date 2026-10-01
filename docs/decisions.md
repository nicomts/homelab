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

- **Decision:** The router's DHCP hands out `192.168.0.2`–`.199`. Addresses `.200`–`.254` are for static IPs: Proxmox is `.200`, and `.201` is `fw-01`'s WAN.
- **Why:** If a static IP is inside the DHCP range, the router can give the same address to another device, and the two devices end up in an IP conflict.
- **Trade-off:** Fewer addresses for DHCP (198), which is still plenty for a home.

## `home.arpa` as the local domain

- **Decision:** The Proxmox host is `pve.home.arpa`.
- **Why:** `home.arpa` is reserved for home networks ([RFC 8375](https://www.rfc-editor.org/rfc/rfc8375)), so it can never clash with a real domain on the internet.

## Public DNS servers on the Proxmox host

- **Decision:** Proxmox uses `1.1.1.1` (Cloudflare) as its first DNS server and `9.9.9.9` (Quad9) as its second.
- **Why:** My ISP router doesn't answer DNS queries; its DHCP hands out the ISP's DNS servers instead (see [writeup 01](../writeups/01-proxmox-dual-boot.md)). I could have used the ISP's servers, but Proxmox has a static configuration: if the ISP changed them, Proxmox wouldn't find out, while DHCP devices would. Public servers don't change, and two different providers mean one outage doesn't break name resolution.
- **Trade-off:** DNS queries from the Proxmox host go to Cloudflare and Quad9 instead of my ISP, and the host uses different DNS servers than the rest of the house. (The lab network has its own resolver, see below.)

## Manual configuration first

- **Decision:** I configure everything by hand in the first stage, and automate it with Ansible later.
- **Why:** First understand what each step does, then automate it. The change also shows up in this repo.
- **Trade-off:** Rebuilding something by hand is slow until the Ansible stage.

## OPNsense as a VM in front of the lab

- **Decision:** The lab's firewall and router is OPNsense running as a VM (`fw-01`) on the Proxmox host, with one network card on the home network (WAN) and one on the lab bridge (LAN).
- **Why:** No extra hardware, and a Proxmox snapshot rolls back a broken firewall in a minute. OPNsense does stateful filtering, NAT, DHCP, DNS and VPNs, so later phases can build on it.
- **Trade-off:** The lab network only exists while Proxmox is running. That fits an on-demand lab, but nothing in the house can depend on it.

## The lab behind the home router, not in front of it

- **Decision:** `fw-01`'s WAN is a normal address on my home network (`192.168.0.201`), and the home router stays as it is.
- **Why:** The household internet never depends on the lab. With `fw-01` off, nothing changes for anyone else (tested in [writeup 02](../writeups/02-opnsense-isolated-lab.md)).
- **Trade-off:** The lab's traffic goes through NAT twice: once in `fw-01` and again in the ISP router. And since the lab's "internet" is a private network, Block private networks has to stay off on `fw-01`'s WAN.

## An isolated bridge for the lab

- **Decision:** `vmbr1` has no physical port and no IP on the host. Lab machines connect only to `vmbr1`, never to `vmbr0`.
- **Why:** `fw-01` has to be the only path between the lab and the house. A host IP on `vmbr1`, or a lab VM on `vmbr0`, would be a path that skips the firewall.
- **Trade-off:** Everything that goes into the lab from the house goes through `fw-01` and its rules, including my own admin access.

## A static route on the Mac, only when I need it

- **Decision:** The Mac reaches the lab through a route that the `labup` alias adds and `labdown` removes. No port forwarding, and no route on the home router.
- **Why:** It doesn't touch the home router, and the route only exists while I'm working on the lab. With a route instead of port forwarding, every lab machine is reachable at its real address.
- **Trade-off:** Only the Mac can reach the lab, and the route is gone after a reboot, so I have to run `labup` again.

## Admin access from one IP only

- **Decision:** The WAN rule lets only `ADMIN_MAC` (the Mac's IP, `192.168.0.109`, reserved on the router) into the lab, not the whole home network.
- **Why:** No other device at home needs to reach the lab, so none can.
- **Trade-off:** If the Mac's IP changes, I'm locked out of the web interface until I update the alias. The way in is the console in Proxmox (`pfctl -d`).

## One logged rule between the lab and the house

- **Decision:** A single LAN rule, `Block lab to home network`, blocks the lab from all of `192.168.0.0/24` and logs every drop. It sits above OPNsense's default rules that allow the LAN to go anywhere.
- **Why:** It's easy to read and easy to test: the lab reaches the internet and nothing at home. The log is the proof when testing and a trail when something breaks.
- **Trade-off:** The rule is IPv4 only, like the lab. If the lab gets IPv6, it needs an IPv6 version.

## Unbound as a recursive resolver

- **Decision:** The lab's DNS server is Unbound on `fw-01`, resolving names itself, starting from the root servers, instead of forwarding queries to another DNS server.
- **Why:** It doesn't depend on my ISP router, which doesn't answer DNS queries, or on a third-party DNS service.
- **Trade-off:** The first lookup of each name is slower than asking a large public resolver that already has it cached. DNSSEC validation is still off, and it's the next thing to turn on.

## Dnsmasq for DHCP, with room for static IPs

- **Decision:** Dnsmasq on `fw-01` hands out `10.10.10.100` to `.199`. Addresses `.2` to `.99` are for servers with static IPs. With automatic registration, Unbound asks Dnsmasq for names in `lab.home.arpa`.
- **Why:** The same rule as at home: static IPs outside the DHCP range never collide. Machines that get an IP by DHCP can be found by name without editing DNS by hand.
- **Trade-off:** 100 addresses for DHCP, which is plenty for a lab.

## `lab.home.arpa` and role-based names

- **Decision:** The lab's domain is `lab.home.arpa`, and machines are named by role and number: `fw-01`, and later `web-01` or `files-01`.
- **Why:** A subdomain of `home.arpa` keeps lab names apart from home names like `pve.home.arpa`. A role-based name says what the machine does and still fits if I swap the product behind it.

## UFS instead of ZFS for OPNsense

- **Decision:** `fw-01` is installed on UFS.
- **Why:** The OPNsense docs recommend ZFS because it handles power cuts better, but ZFS uses more RAM and `fw-01` has 2 GB. Proxmox snapshots already give me a way back.
- **Trade-off:** After an unclean shutdown, UFS is more likely to need a file system check or a restore from a snapshot.

## Reply-to off

- **Decision:** Reply-to is disabled for the whole firewall (Optimize for Multiwan unchecked in the setup wizard) and on the WAN rule.
- **Why:** The admin Mac is on the same network as the WAN. With reply-to, OPNsense sends replies to the home router instead of straight to the Mac, and connections only half work.
- **Trade-off:** If `fw-01` ever gets a second internet link, reply-to has to be reconsidered.

## Throwaway containers for testing

- **Decision:** Network tests run from a temporary LXC container (`test-01`, CT 900) that I delete afterwards.
- **Why:** A container starts in seconds and uses little RAM. The high ID marks it as disposable.
- **Trade-off:** A container shares the host's kernel, so anything that depends on the kernel needs a VM instead.
