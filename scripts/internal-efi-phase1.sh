#!/bin/bash
# Phase 1: inspect + back up the INTERNAL boot EFI (disk0s1).
# Runs as root (invoked via osascript "with administrator privileges").
set -u
DEV="disk0s1"
WS="/Users/bogdan/ax200-bt-dev"
TS="$(date +%Y%m%d-%H%M%S)"

echo "===== phase 1: inspect + backup internal EFI ====="
echo "date: $TS"
echo "host: $(hostname)"

echo "-- current mounts for $DEV --"
mount | grep -E "/dev/$DEV" || echo "(not mounted)"

echo "-- force unmount if mounted --"
diskutil unmount force "$DEV" 2>/dev/null || true

echo "-- mounting $DEV --"
diskutil mount "$DEV"
RC=$?
echo "mount rc=$RC"
if [ "$RC" -ne 0 ]; then echo "MOUNT FAILED"; exit 2; fi

MNT="$(diskutil info -plist "$DEV" | plutil -extract MountPoint raw - 2>/dev/null)"
echo "mount point: [$MNT]"
if [ -z "${MNT:-}" ] || [ "$MNT" = "-" ]; then echo "no mount point found"; exit 3; fi

echo "-- top level of ESP --"
ls -la "$MNT"

echo "-- EFI dir --"
ls -la "$MNT/EFI" 2>&1

echo "-- EFI/OC dir --"
ls -la "$MNT/EFI/OC" 2>&1

echo "-- EFI/OC/Kexts --"
ls -la "$MNT/EFI/OC/Kexts" 2>&1

echo "-- EFI/OC/Drivers --"
ls -la "$MNT/EFI/OC/Drivers" 2>&1

echo "-- config.plist info --"
ls -la "$MNT/EFI/OC/config.plist" 2>&1

echo "-- OpenCore config version keys --"
if [ -f "$MNT/EFI/OC/config.plist" ]; then
  /usr/bin/plutil -extract Misc.Version raw "$MNT/EFI/OC/config.plist" 2>&1 || true
  /usr/bin/plutil -extract Kernel.Add raw "$MNT/EFI/OC/config.plist" 2>&1 | head -40 || true
fi

echo "-- backing up entire EFI folder --"
mkdir -p "$WS/backups"
if [ -d "$MNT/EFI" ]; then
  tar -C "$MNT" -czf "$WS/backups/internal-EFI-$TS.tar.gz" EFI 2>&1
  echo "backup: $WS/backups/internal-EFI-$TS.tar.gz"
  ls -la "$WS/backups/internal-EFI-$TS.tar.gz"
else
  echo "NO EFI FOLDER FOUND ON $DEV"
fi

echo "-- copying config.plist out for review --"
cp "$MNT/EFI/OC/config.plist" "$WS/backups/internal-config.plist.$TS" 2>&1
ls -la "$WS/backups/internal-config.plist.$TS" 2>&1

echo "-- chown mount to user 501 for convenient editing --"
chown -R 501:20 "$MNT" 2>&1 && echo "chown ok" || echo "chown failed"

echo "-- final mount status --"
mount | grep "$MNT" || echo "(not mounted)"

echo "===== phase 1 done ====="
echo "TS=$TS"
echo "MNT=$MNT"
