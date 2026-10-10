#!/usr/bin/env bash
# Archive /etc/nginx with a timestamp and keep 14 days of archives.
set -euo pipefail

dest=/var/backups/nginx
mkdir -p "$dest"
tar -czf "$dest/nginx-config-$(date +%F-%H%M).tar.gz" -C /etc nginx
find "$dest" -name 'nginx-config-*.tar.gz' -mtime +14 -delete
echo "nginx config saved to $dest"
