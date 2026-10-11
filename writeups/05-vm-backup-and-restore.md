# Backups I actually restored: Proxmox, an external disk and a deleted VM

**Date:** 2026-10-09 · **Phase:** 3 · **Time spent:** ~5 h for the whole phase (writeups 03 to 05)

## TL;DR

- `web-01` now runs nginx with an internal page, and a systemd timer archives its configuration every day, keeping 14 days.
- Proxmox backs up every guest once a week to the lab's SSD. Because the lab is only on when I use it, the job runs at the next boot if the PC was off at the scheduled time.
- A second copy goes to an external USB disk that also holds my personal files (NTFS). Proxmox treats it as a storage that goes offline when the disk is unplugged, so a backup can never land on an empty folder by mistake.
- Then I deleted `web-01` and restored it from the external disk. It was serving its page again about 6 minutes later, with the same IP, the same SSH host key and its timer intact.
- The log showed two things a green "TASK OK" hid: `fw-01`'s file system couldn't be frozen during its backup, and the job had also backed up `test-01`, a phase 2 container I believed I had deleted.

## Goal

Backups that I have restored at least once, with a copy that survives the loss of the lab's SSD, on a lab that is only on a few hours a week.

## Environment

| Component | Detail |
| --- | --- |
| Host | Proxmox VE 9.2, from [writeup 01](01-proxmox-dual-boot.md) |
| Guests | `fw-01` (VM 100, OPNsense), `web-01` (VM 110, Ubuntu Server 26.04.1), `files-01` (VM 111, Rocky Linux 10.2), `test-01` (CT 900, stopped, deleted after this phase) |
| First copy | `local`: a folder on the Proxmox system volume, on the same 240 GB SSD as the VMs |
| Second copy | `external-backup`: a 4 TB USB hard disk, NTFS, shared with my personal files and mounted only while copying |

## Background

**A snapshot is not a backup.** A Proxmox snapshot lives in the same storage as the VM, depends on its disk and disappears when the VM is deleted. It's a quick undo before a risky change. A backup is a separate file that can be restored on any Proxmox host, even after the VM and its disk are gone.

**RPO and RTO.** Two numbers describe a backup plan. The RPO (Recovery Point Objective) is how much data you can lose: the time since the last copy you could restore from. The RTO (Recovery Time Objective) is how long it takes to be running again. Both mean something only after a real restore.

**3-2-1.** Three copies of the data, on two kinds of media, one of them away from the others. Here: the VMs themselves, a backup on the same SSD, and a copy on a USB disk that I can take out of the house.

**How a backup of a running VM works.** In snapshot mode, Proxmox asks the guest agent to *freeze* the guest's file systems, which flushes pending writes and pauses new ones for a moment. It starts the backup, *thaws* them, and copies the disk while the VM keeps running. If the VM writes to a block that hasn't been copied yet, the old version is copied first, so the archive is the disk as it was at the freeze.

## What I did

### 1. nginx on `web-01`

```bash
sudo apt install -y nginx
echo '<h1>web-01</h1><p>Internal page, lab.home.arpa</p>' | sudo tee /var/www/html/index.html
sudo ufw allow 'Nginx HTTP'
```

`Nginx HTTP` is a `ufw` profile that opens port 80 only; port 443 isn't needed without a certificate. `ss` shows nginx listening:

```text
nico@web-01:~$ sudo ss -tlnp | grep ':80 '
LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=2806,fd=5),("nginx",pid=2805,fd=5),("nginx",pid=2802,fd=5))
LISTEN 0      511             [::]:80           [::]:*    users:(("nginx",pid=2806,fd=6),("nginx",pid=2805,fd=6),("nginx",pid=2802,fd=6))
```

### 2. A daily backup of nginx's configuration

A copy of `/etc/nginx` inside the VM protects against a bad edit to the configuration. It doesn't protect against losing the VM: that's what the Proxmox backups are for.

The script, [`nginx-config-backup.sh`](../configs/web-01/nginx-config-backup.sh), in `/usr/local/sbin`:

```bash
#!/usr/bin/env bash
# Archive /etc/nginx with a timestamp and keep 14 days of archives.
set -euo pipefail

dest=/var/backups/nginx
mkdir -p "$dest"
tar -czf "$dest/nginx-config-$(date +%F-%H%M).tar.gz" -C /etc nginx
find "$dest" -name 'nginx-config-*.tar.gz' -mtime +14 -delete
echo "nginx config saved to $dest"
```

- **`/usr/local/sbin`** is where an administrator's own scripts go, outside what `apt` manages.
- **`set -euo pipefail`** stops the script at the first error instead of carrying on.
- **The `find` line** deletes archives older than 14 days. A backup with no limit ends up filling the disk.

A systemd service runs it, and a timer decides when ([`nginx-config-backup.service`](../configs/web-01/nginx-config-backup.service) and [`nginx-config-backup.timer`](../configs/web-01/nginx-config-backup.timer)):

```ini
[Timer]
OnCalendar=daily
Persistent=true
```

`Persistent=true` matters in an on-demand lab: if the PC was off at midnight, the timer runs the backup as soon as the VM starts. Without it, a daily job on a machine that's rarely on at midnight would almost never run. Compared with cron, the output goes to the journal, and `systemctl list-timers` shows the last and next run.

I ran the service once by hand to test it:

```text
nico@web-01:~$ sudo systemctl start nginx-config-backup.service
nico@web-01:~$ journalctl -u nginx-config-backup.service --no-pager
Oct 09 17:04:26 web-01 systemd[1]: Starting nginx-config-backup.service - Back up the nginx configuration...
Oct 09 17:04:26 web-01 nginx-config-backup.sh[3206]: nginx config saved to /var/backups/nginx
Oct 09 17:04:26 web-01 systemd[1]: nginx-config-backup.service: Deactivated successfully.
Oct 09 17:04:26 web-01 systemd[1]: Finished nginx-config-backup.service - Back up the nginx configuration.
```

### 3. A weekly backup of every guest

Datacenter → Backup → Add:

| Setting | Value | Why |
| --- | --- | --- |
| Storage | `local` | The everyday destination, on the SSD |
| Schedule | `sun 12:00` | Once a week. The time doesn't matter much because of Repeat missed |
| Selection mode | All | Guests I create later are included automatically |
| Mode | Snapshot | The VMs keep running during the backup |
| Compression | ZSTD | Fast, and compresses well |
| Retention | Keep Last `3` | Three weeks of history fit easily in `local` |
| Repeat missed | On | If the PC wasn't running Proxmox at the scheduled time, the job runs as soon as it starts |

Then **Run now**. The whole job took 72 seconds:

| Guest | Disk | Archive | Time | File system frozen? |
| --- | --- | --- | --- | --- |
| `fw-01` (VM 100) | 20 GB | 1.06 GB | 19 s | **No** ([problem 1](#problem-1-fw-01s-file-system-couldnt-be-frozen)) |
| `web-01` (VM 110) | 32 GB | 3.07 GB | 33 s | Yes |
| `files-01` (VM 111) | 32 GB | 1.36 GB | 13 s | Yes |
| `test-01` (CT 900) | 4 GB | 192 MB | 7 s | Stopped, so not needed ([problem 2](#problem-2-a-container-i-thought-i-had-deleted)) |

The archives are much smaller than the disks because most of each disk was never written: the log reports 80% to 92% of zeros, which `zstd` compresses to almost nothing. For `web-01`, the freeze and thaw around the start of the backup:

```text
INFO: creating vzdump archive '/var/lib/vz/dump/vzdump-qemu-110-2026_10_09-17_25_58.vma.zst'
INFO: issuing guest-agent 'fs-freeze' command
INFO: starting backup via QMP command
INFO: issuing guest-agent 'fs-thaw' command
...
INFO: archive file size: 3.07GB
INFO: Finished Backup of VM 110 (00:00:33)
```

### 4. A second copy on the external disk

The disk is NTFS and holds my personal files, and I need to be able to unplug it and take it elsewhere. So instead of reformatting it, Proxmox mounts it only while copying, and writes only into one folder.

**Finding the disk.** The lab PC already has three internal NTFS disks, so I identified the external one by its transport, `usb` (output trimmed to that disk):

```text
root@pve:~# lsblk -o NAME,SIZE,TRAN,FSTYPE,LABEL,MODEL,UUID
NAME     SIZE TRAN FSTYPE LABEL       MODEL UUID
sdf      3.6T usb                     WDC W
└─sdf1   3.6T      ntfs   My Passport       <uuid>
```

**Mounting it.** An `/etc/fstab` line with the partition's UUID and `noauto`:

```bash
mkdir -p /mnt/external
echo 'UUID=<uuid> /mnt/external ntfs3 noauto 0 0' >> /etc/fstab
systemctl daemon-reload
mount /mnt/external
mkdir -p /mnt/external/homelab-backups
```

- **The UUID**, because Linux names disks in the order it finds them. This one is `sdf` today, and the name can change ([writeup 01](01-proxmox-dual-boot.md) has the same lesson).
- **`noauto`**, because the disk isn't always plugged in. I mount it by hand.
- **`ntfs3`** is the Linux kernel's own NTFS driver.

**Telling Proxmox about it.**

```bash
pvesm add dir external-backup --path /mnt/external/homelab-backups --content backup --is_mountpoint /mnt/external
```

`is_mountpoint` makes Proxmox check that `/mnt/external` is really a mounted disk. When it isn't, `external-backup` shows as inactive. Without it, anything written there with the disk unplugged would go silently into the empty folder, on the SSD.

**Copying.**

```text
root@pve:~# rsync -rtv --progress /var/lib/vz/dump/ /mnt/external/homelab-backups/dump/
...
sent 6,095,642,330 bytes  received 247 bytes  128,329,317.41 bytes/sec
total size is 6,094,153,448  speedup is 1.00
root@pve:~# umount /mnt/external
```

`-rt` copies files and their times, but not Linux owners and permissions, which NTFS can't store (`-a` would try and complain). The copy includes each archive's `.log` and `.notes`, so Proxmox lists the backups under `external-backup` like any other. `umount` writes everything still pending, and only then is the disk safe to unplug.

### 5. Deleting `web-01` and restoring it

To prove the backups work, I restored from the copy I'd need if the SSD died: the one on the external disk.

| Time | What I did |
| --- | --- |
| 17:54 | From the Mac: the page loads, and `/var/backups/nginx` has two archives |
| | Mounted the external disk; `external-backup` showed the backup of VM 110 |
| | `web-01` → Shutdown, then More → Remove, with Destroy unreferenced disks |
| | `external-backup` → the VM 110 backup → Restore: storage `local-lvm`, VM ID `110`, Unique off, Start after restore on |
| 17:59 | From the Mac: the page loads, the timer is scheduled, both archives are there |

**Unique off** keeps the network card's MAC address, so the VM comes back identical. The checks after the restore:

```text
$ curl -I http://10.10.10.10
HTTP/1.1 200 OK
Server: nginx/1.28.3 (Ubuntu)
Date: Fri, 09 Oct 2026 20:59:58 GMT
Content-Type: text/html
Content-Length: 51
$ ssh web-01 'systemctl list-timers nginx-config-backup.timer; ls /var/backups/nginx'
NEXT                            LEFT LAST                        PASSED UNIT                      ACTIVATES
Sat 2026-10-10 00:00:00 -03 5h 59min Fri 2026-10-09 17:03:50 -03      - nginx-config-backup.timer nginx-config-backup.service
...
nginx-config-2026-10-09-1702.tar.gz
nginx-config-2026-10-09-1704.tar.gz
```

(`Date` is in UTC: 20:59 is 17:59 local time.)

- **The RTO was about 6 minutes**, from the check before deleting to the page loading again.
- **`ssh web-01` connected without a host key warning.** The server's SSH keys are inside the backup, so the restored VM is the same server as far as my Mac can tell.
- **The restored VM has none of its snapshots.** The backup log says it (`snapshots found (not included into backup)`), and the snapshots went away with the deleted VM. That's the difference between a snapshot and a backup, made real.
- **The RPO, if the SSD died today, is the date of the last copy to the external disk.** The weekly job is automatic; the copy to the external disk is manual.

Then I unmounted the external disk and unplugged it.

## What went wrong and how I fixed it

### Problem 1: `fw-01`'s file system couldn't be frozen

**Symptom.** The job finished with `TASK OK`, but `fw-01`'s part of the log had an error:

```text
INFO: creating vzdump archive '/var/lib/vz/dump/vzdump-qemu-100-2026_10_09-17_25_39.vma.zst'
INFO: issuing guest-agent 'fs-freeze' command
ERROR: unable to freeze guest fs - failed to freeze /: Resource deadlock avoided
INFO: starting backup via QMP command
INFO: issuing guest-agent 'fs-thaw' command
...
INFO: Finished Backup of VM 100 (00:00:19)
```

**What it means.** The backup went ahead without the freeze. `fw-01`'s archive is *crash-consistent*: what the disk would hold if the power went off at that instant, with any pending writes lost. The other two VMs froze without errors.

**Cause.** Not found yet. The agent on `fw-01` is the `os-qemu-guest-agent` plugin from [writeup 02](02-opnsense-isolated-lab.md#6-updates-guest-agent-and-backups), and the error comes from the guest (`Resource deadlock avoided`). The same message shows up in [at least one thread on the Proxmox forum](https://forum.proxmox.com/goto/post?id=644632), without a cause I could apply to my case.

**Why it can wait.** A firewall keeps no databases or user files, so a crash-consistent copy will very likely boot. And `fw-01`'s configuration has its own backup: the `config.xml` I downloaded from OPNsense in phase 2, kept outside the repository.

**Lesson.** A job that finishes with `TASK OK` can still have errors inside. Read the log, not just the status.

### Problem 2: a container I thought I had deleted

**Symptom.** With Selection mode All, the job also backed up `CT 900 (test-01)`, the throwaway container from [writeup 02](02-opnsense-isolated-lab.md#7-testing-with-a-throwaway-container). That writeup said I had deleted it.

**Cause.** I never did. I had planned to, and I wrote it down as done.

**Fix.** I deleted `test-01` and corrected writeup 02, which had said it was gone since phase 2.

**Lesson.** "All" backs up what exists, not what you believe exists. A backup log is also an inventory, and worth reading as one.

### Smaller issues

| What happened | Cause | Fix |
| --- | --- | --- |
| `systemctl list-timers` stopped at `lines 1-5/5 (END)` and didn't return to the prompt | `systemctl` shows long output in a pager (`less`) | `q` to leave, or `--no-pager` |

## What I learned

- A snapshot is an undo button, not a backup. Deleting the VM took its snapshots with it, and the backup didn't include them.
- A backup only counts once it has been restored. The restore gave me real numbers: about 6 minutes to recover `web-01`.
- In a lab that is only on sometimes, schedules need a way to catch up: Repeat missed in Proxmox, `Persistent=true` in systemd.
- A removable backup disk needs a guard against the empty mount point. `is_mountpoint` turns "the disk isn't there" into an error instead of a full SSD.
- `TASK OK` can hide an `ERROR` line. Read the log.
- The copy that protects against losing the SSD is only as recent as the last time I made it, so making it is part of the routine.

## Troubleshooting

### Using a removable disk for Proxmox backups

```bash
lsblk -o NAME,SIZE,TRAN,FSTYPE,LABEL,UUID     # find it by TRAN=usb and its size
mkdir -p /mnt/external
echo 'UUID=<uuid> /mnt/external ntfs3 noauto 0 0' >> /etc/fstab   # ext4 instead of ntfs3 if the disk is Linux-only
systemctl daemon-reload
mount /mnt/external
pvesm add dir external-backup --path /mnt/external/<folder> --content backup --is_mountpoint /mnt/external
```

Always `umount` before unplugging. If `mount` fails with `volume is dirty and "force" flag is not set`, plug the disk into Windows, run `chkdsk` on it and eject it safely.

### `unable to freeze guest fs` in a backup log

The backup still happened, without the freeze. Check whether the agent can freeze at all, from the Proxmox shell:

```bash
qm guest cmd <vmid> fsfreeze-freeze
qm guest cmd <vmid> fsfreeze-thaw
```

If it can't, the error comes from inside the guest. Until it's fixed, that VM's backups are crash-consistent.

## Next

- Find out why `fw-01` can't freeze its file system, or turn off the freeze for that VM so the weekly log stops reporting an error I already know about.
- Copy the backups to the external disk after each weekly job.
- Phase 4: VLANs on `vmbr1` and a site-to-site WireGuard tunnel between two MikroTik CHR routers.
