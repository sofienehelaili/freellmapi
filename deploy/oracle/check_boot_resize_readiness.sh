#!/usr/bin/env bash
# Safe, read-only readiness check before any Oracle Boot Volume 50 -> 100 GB resize.
# It NEVER invokes growpart without -N and NEVER calls resize2fs or OCI update.
set -euo pipefail
echo 'OCI_BOOT_RESIZE_READINESS=READ_ONLY'
if [ "$(uname -m)" != "aarch64" ]; then
  echo 'STOP: expected aarch64 Oracle A1'
  exit 10
fi
root_source="$(findmnt -n -o SOURCE /)"
root_fstype="$(findmnt -n -o FSTYPE /)"
echo "ROOT_SOURCE=$root_source"
echo "ROOT_FSTYPE=$root_fstype"
if [ "$root_source" != "/dev/sda1" ] || [ "$root_fstype" != "ext4" ]; then
  echo 'STOP: expected /dev/sda1 formatted ext4; manual review required'
  exit 11
fi
for cmd in blockdev growpart lsblk; do
  command -v "$cmd" >/dev/null || { echo "STOP: missing $cmd"; exit 12; }
done
disk_bytes="$(sudo -n blockdev --getsize64 /dev/sda)"
echo "DISK_SIZE_BYTES=$disk_bytes"
echo "DISK_SIZE_GB=$((disk_bytes/1000000000))"
if [ "$disk_bytes" -lt 100000000000 ]; then
  echo 'STATUS=VOLUME_STILL_BELOW_100_GB'
  echo 'Do not expand Linux partition until OCI Boot Volume is safely resized.'
  exit 0
fi
echo '=== Partition placement ==='
lsblk -b -o NAME,START,SIZE,PARTN,FSTYPE,MOUNTPOINTS /dev/sda
start_root="$(cat /sys/class/block/sda1/start)"
for partition in /sys/class/block/sda/sda[0-9]*; do
  [ -d "$partition" ] || continue
  [ "${partition##*/}" = "sda1" ] && continue
  position="$(cat "$partition/start")"
  if [ "$position" -gt "$start_root" ]; then
    echo "STOP: found partition after root at $partition. No automatic resize recommendation."
    exit 13
  fi
done
echo '=== Growpart PREVIEW (no disk changes) ==='
sudo -n growpart -N /dev/sda 1 || true
echo 'STATUS=READY_FOR_MANUAL_REVIEW_NOT_APPROVED'
echo 'AFTER verified backup, quota and explicit approval, commands for a qualified operator:'
echo '  sudo growpart /dev/sda 1'
echo '  sudo resize2fs /dev/sda1'
echo '  df -h /'
echo 'Nothing has been changed by this preflight.'
