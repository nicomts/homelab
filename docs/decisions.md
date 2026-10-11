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
- **Trade-off:** The first lookup of each name is slower than asking a large public resolver that already has it cached.

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

- **Decision:** Network tests run from a disposable LXC container (in phase 2, `test-01`, CT 900) that I delete afterwards.
- **Why:** A container starts in seconds and uses little RAM. The high ID marks it as disposable.
- **Trade-off:** A container shares the host's kernel, so anything that depends on the kernel needs a VM instead.

## DNSSEC validation in Unbound

- **Decision:** Unbound on `fw-01` validates DNSSEC signatures for every lab machine.
- **Why:** A forged answer for a signed domain gets an error instead of reaching a server. It stayed off during phase 2 so there was one less thing that could fail, and it went on at the start of phase 3 (tested in [writeup 03](../writeups/03-linux-server-baseline.md#1-dnssec-on-the-labs-resolver)).
- **Trade-off:** Validation depends on `fw-01`'s clock: signatures have validity dates, so with a wrong clock every signed name fails.

## One server from each Linux family

- **Decision:** `web-01` runs Ubuntu Server 26.04 LTS and `files-01` runs Rocky Linux 10.
- **Why:** Debian's and Red Hat's families cover most Linux servers, and a job can put me in front of either. Doing the same baseline on both shows what changes ([writeup 03](../writeups/03-linux-server-baseline.md#same-goal-two-families)).
- **Trade-off:** Two sets of tools and defaults to keep in mind.

## VM IDs that match the IP

- **Decision:** A machine with a static IP on the lab network gets 100 plus the last part of its IP as its VM ID: `web-01` is VM 110 at `.10`, `files-01` is VM 111 at `.11`, and the routers `chr-a` and `chr-b` are VMs 121 and 122 at `.21` and `.22`. Clients that get their address by DHCP go in the 200s (`client-01` is CT 201).
- **Why:** Nothing to look up when moving between Proxmox and the network.
- **Trade-off:** It only works for the static range of the lab network (`.2` to `.99`).

## CPU type `host`

- **Decision:** The server VMs use CPU type `host`.
- **Why:** Rocky Linux 10 needs x86-64-v3, which Proxmox's default type (x86-64-v2-AES) doesn't provide. Both servers use the same type so they differ only in the distribution.
- **Trade-off:** A VM with CPU type `host` can't be live-migrated to a host with a different CPU. With one node, that doesn't matter.

## Installing from the ISO

- **Decision:** Each server is installed by hand from the distribution's ISO, not cloned from a cloud-init template.
- **Why:** The installer (disks, LVM, network, users) is part of what I'm learning. Templates fit better with the Ansible stage.
- **Trade-off:** Building a server by hand is slower than cloning a template.

## Static IPs set in the installer, names in Dnsmasq

- **Decision:** The servers' static IPs are entered in each installer, and their names are added by hand in Dnsmasq's Hosts.
- **Why:** The installers write the network configuration (netplan, NetworkManager) without any typing in the Proxmox console, which drops Shift. Dnsmasq only registers the names of machines it gives addresses to.
- **Trade-off:** Two places to update if a server's IP changes.

## A personal admin account with a console-safe password

- **Decision:** Each server has an account `nico` with `sudo`. Its password uses only lowercase letters and digits. Root logins are disabled.
- **Why:** A named account leaves who did what in the logs, unlike a shared `admin`. The password has to be typeable in the Proxmox browser console, which drops Shift from my Mac.
- **Trade-off:** Without symbols or capitals, only length keeps the password strong.

## SSH with keys only, in a drop-in file

- **Decision:** `PasswordAuthentication`, `KbdInteractiveAuthentication` and `PermitRootLogin` are off on both servers, set in `/etc/ssh/sshd_config.d/00-hardening.conf`. The key is the Mac's `id_ed25519`, which has a passphrase.
- **Why:** A password can be guessed; a private key protected by a passphrase can't. `sshd` keeps the first value it reads, and the file whose name sorts first wins over the ones the installers leave in `sshd_config.d/` ([writeup 03](../writeups/03-linux-server-baseline.md#9-ssh-with-keys-only)).
- **Trade-off:** Without the Mac's key, the only way in is the console.

## A serial console on every Linux VM

- **Decision:** Every Linux VM has a serial port, and its kernel sends a console to it. I open it with xterm.js in Proxmox or `qm terminal`.
- **Why:** The browser console (noVNC) drops Shift from my Mac. The serial console sends text, so capitals, symbols and pasting work.
- **Trade-off:** It only works once Linux has started. Anything before that (the boot menu, the installer) still needs noVNC.

## Automatic security updates, no automatic reboots

- **Decision:** `unattended-upgrades` on Ubuntu and `dnf-automatic` on Rocky install security updates only, and never reboot.
- **Why:** Security fixes shouldn't wait for me. Reboots are my call: the lab is only on when I use it, and on real servers they go in a maintenance window.
- **Trade-off:** Some updates, like a new kernel, only take effect after a reboot I have to remember.

## A firewall on every server

- **Decision:** `ufw` on Ubuntu and `firewalld` on Rocky, each allowing only what the server offers: SSH, plus HTTP on `web-01` and Samba on `files-01`.
- **Why:** `fw-01` doesn't see traffic between two machines on the lab network, so each server filters its own.
- **Trade-off:** A new service needs a rule on the server as well as on `fw-01`.

## SELinux stays enforcing

- **Decision:** SELinux stays in enforcing mode on Rocky. Access problems get fixed with labels in the policy (`semanage fcontext` and `restorecon`).
- **Why:** Turning it off fixes one problem by removing a layer of protection for the whole server ([writeup 04](../writeups/04-samba-vs-selinux.md)).
- **Trade-off:** New services sometimes need a label before they work.

## Weekly backups of every guest, with Repeat missed

- **Decision:** A Proxmox job backs up all guests every Sunday at 12:00 to `local`, in snapshot mode with ZSTD, keeping the last 3. Repeat missed is on.
- **Why:** With Selection mode All, new guests are included automatically. The lab is only on sometimes, so a missed run happens at the next boot instead of being skipped.
- **Trade-off:** These backups are on the same SSD as the VMs, so they don't survive that SSD failing. The next decision covers that.

## A second copy on an external NTFS disk

- **Decision:** After each weekly backup, I copy the backups to a USB disk that also holds my personal files. It's mounted with `ntfs3` only while copying, and Proxmox sees it as the storage `external-backup`, with `is_mountpoint` set.
- **Why:** A copy on a different disk that can leave the house. Keeping NTFS means the disk still works with Windows and other computers. `is_mountpoint` keeps Proxmox from writing into the empty folder when the disk isn't there.
- **Trade-off:** The copy is manual, so it's only as recent as the last time I made it. The disk must always be unmounted before unplugging, because it holds more than lab data.

## A daily backup of nginx's configuration inside `web-01`

- **Decision:** A systemd timer archives `/etc/nginx` every day to `/var/backups/nginx`, keeping 14 days, with `Persistent=true`.
- **Why:** It undoes a bad configuration change without restoring the whole VM. `Persistent=true` runs a missed day at the next boot.
- **Trade-off:** It lives inside the VM, so it's lost with it. The Proxmox backups cover that.

## VLANs on the existing lab bridge

- **Decision:** New networks inside the lab are VLANs on `vmbr1`. `fw-01`'s lab card has no tag, so it's a trunk; each client's card has its VLAN's tag, so it's an access port. The first one is `CLIENTS`, VLAN 20, `10.10.20.0/24`.
- **Why:** `vmbr1` has been VLAN aware since phase 2, so a new network needs no new card on the firewall and no new bridge. Traffic between VLANs has to go through `fw-01`, so its rules decide what crosses ([writeup 06](../writeups/06-vlans-and-firewall-rules.md)).
- **Trade-off:** Every VLAN shares `fw-01`'s single lab card, and a wrong tag quietly puts a machine on the wrong network.

## One block rule with every private range

- **Decision:** On `CLIENTS`, one logged rule blocks traffic to `PRIVATE_NETS`, an alias with the three RFC 1918 ranges. It sits below the rules that allow DNS to `fw-01` and HTTP/HTTPS to `web-01`, and above the rule that allows the internet.
- **Why:** One rule covers the servers, `fw-01`'s own web interface, the house, the branches and any private network I add later. It's also easy to check in the log.
- **Trade-off:** Anything private a client should reach needs its own allow rule above the block.

## A container as the clients VLAN's test machine

- **Decision:** `client-01`, an LXC container with Debian 13, stays in the lab as the test client on `CLIENTS`.
- **Why:** Testing firewall rules needs a machine on the network, not a desktop. A container starts in seconds, uses 512 MB, and its console passes Shift.
- **Trade-off:** It isn't a user's PC: no browser and no desktop operating system.

## MikroTik CHR for the branch routers

- **Decision:** The two branch routers are MikroTik Cloud Hosted Routers, RouterOS 7, with the free license.
- **Why:** RouterOS is widely used by ISPs and small networks, and a CHR runs the same system as MikroTik's hardware routers in a 512 MB VM. The free license doesn't expire.
- **Trade-off:** The free license limits upload to 1 Mbps per interface: enough to test routing, not throughput.

## Branch LANs as bridges without ports

- **Decision:** Each branch's LAN is a bridge with no ports on its router (`branch-lan`).
- **Why:** In RouterOS, a bridge without ports is an interface that's always up, like a loopback. It stands for a LAN without one more VM per branch.
- **Trade-off:** There's no host behind each router, so tests between branches have to start from the router's LAN address (`src-address`).

## WireGuard with static routes between the branches

- **Decision:** A WireGuard tunnel joins the branches (UDP 13231, a `/30` for the two ends), with one static route on each router to the other branch's LAN. OSPF is an optional next step.
- **Why:** WireGuard is built into RouterOS 7 and has few moving parts. With two sites, two static routes are easier to read and to debug than a routing protocol ([writeup 07](../writeups/07-site-to-site-wireguard-mikrotik.md)).
- **Trade-off:** Each new branch means peers and routes by hand on every router.

## RouterOS access: my user, my key, fewer services

- **Decision:** Each router has a user `nico` (group `full`) with the Mac's key. `admin` is disabled, and telnet, FTP, the web interface and the API are off. SSH keeps `password-authentication=yes-if-no-key`, so a user with a key can only log in with it.
- **Why:** The same baseline as the servers: a named account, keys over SSH, and nothing listening that I don't use.
- **Trade-off:** WinBox stays on and still accepts passwords.

## Router configurations in the repository as `/export`

- **Decision:** Each router's configuration goes in `configs/<router>/export.rsc`, taken with `/export`, without Windows line endings and without the `system id` line.
- **Why:** An export is the configuration written as commands, so it can be read, compared with `git diff` and loaded again. RouterOS 7 leaves private keys out of it.
- **Trade-off:** Users, SSH keys and default values aren't in the export, so the hardening is documented only in the writeup.
