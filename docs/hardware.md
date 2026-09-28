# Hardware

The lab runs on my old desktop PC, which dual-boots Windows and Proxmox VE. Each system has its own SSD, and I choose between them from the BIOS boot menu.

## PC

| Component | Model |
| --- | --- |
| Motherboard | MSI Z270 Gaming M3 (UEFI) |
| CPU | Intel Core i7-7700K, 4 cores / 8 threads (VT-x enabled in the BIOS; VT-d off, not needed for now) |
| RAM | 16 GB DDR4 |
| GPU | NVIDIA GTX 1060 6 GB (not used by the lab) |
| Network | Onboard Ethernet, `nic0` in Proxmox, wired to the home router |

## Disks

| Disk | Size | Used for |
| --- | --- | --- |
| Kingston SA400 SSD | 960 GB | Windows 10 and its EFI System Partition |
| AVEXIR S100 SSD | 240 GB | Proxmox VE: system and VM storage |
| 3 HDDs | 2 TB, 4 TB and 2 TB | Personal data (NTFS). Not used by the lab |

As seen from Proxmox. Linux names disks in the order it finds them, so these `sdX` names can change if disks are added or removed:

```text
root@pve:~# lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
NAME                 SIZE TYPE FSTYPE      MOUNTPOINT
sda                894.3G disk
├─sda1                16M part
├─sda2             893.7G part ntfs
└─sda3               500M part vfat
sdb                  1.8T disk
├─sdb1                 1K part
└─sdb5               1.7T part ntfs
sdc                223.6G disk
├─sdc1              1007K part
├─sdc2                 1G part vfat        /boot/efi
└─sdc3               222G part LVM2_member
  ├─pve-swap           8G lvm  swap        [SWAP]
  ├─pve-root        65.5G lvm  ext4        /
  ├─pve-data_tmeta   1.3G lvm
  │ └─pve-data     129.8G lvm
  └─pve-data_tdata 129.8G lvm
    └─pve-data     129.8G lvm
sdd                  3.6T disk
├─sdd1               1.8T part ntfs
└─sdd2               1.8T part ntfs
sde                  1.8T disk
├─sde1                 1K part
└─sde5               1.8T part ntfs
```

## Proxmox storage

Proxmox is installed on `ext4` with the installer's default LVM layout:

```text
root@pve:~# lvs
  LV   VG  Attr       LSize    Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  data pve twi-a-tz-- <129.85g             0.00   1.23
  root pve -wi-ao----  <65.50g
  swap pve -wi-ao----    8.00g
root@pve:~# pvesm status
Name             Type     Status     Total (KiB)      Used (KiB) Available (KiB)        %
local             dir     active        67022232         5526272        58045696    8.25%
local-lvm     lvmthin     active       136155136               0       136155136    0.00%
```

| Storage | What it is | What goes there |
| --- | --- | --- |
| `local` | A folder on the system volume (`root`, ~65 GB) | ISO images, container templates, backups |
| `local-lvm` | The `data` thin pool (~130 GB) | VM and container disks |

A thin pool only uses space for the data a VM has actually written, so the virtual disks can add up to more than 130 GB as long as they don't all fill up.

## Network

| Device | Address |
| --- | --- |
| Home router (ISP, Technicolor CGA4233) | `192.168.0.1` |
| Router's DHCP range | `192.168.0.2`–`192.168.0.199` |
| Proxmox host (`pve.home.arpa`) | `192.168.0.200/24` |
| Reserved for OPNsense's WAN (phase 2) | `192.168.0.201` |
| Proxmox DNS servers | `1.1.1.1`, `9.9.9.9` |

Proxmox's network configuration. The IP lives on the bridge `vmbr0`, not on the network card: `nic0` is plugged into the bridge, and VMs will connect to the same bridge.

```text
root@pve:~# cat /etc/network/interfaces
auto lo
iface lo inet loopback

iface nic0 inet manual

auto vmbr0
iface vmbr0 inet static
	address 192.168.0.200/24
	gateway 192.168.0.1
	bridge-ports nic0
	bridge-stp off
	bridge-fd 0


source /etc/network/interfaces.d/*
```

## Software

| | Version |
| --- | --- |
| Proxmox VE | 9.2 (`pve-manager/9.2.20`) |
| Kernel | `7.0.14-19-pve` |
| Windows | Windows 10 |
