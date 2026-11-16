#!/bin/bash
# Run *after* rebooting the test EFI. Reports whether OpenCore injected the two
# Intel bundles this time, and whether they loaded into the kernel.
#
# The USB ESP must be mounted (read-only is fine). If it is not mounted, run:
#   sudo diskutil mount disk2s1
set -uo pipefail

ESP="${1:-/Volumes/MACOSUSB}"

echo "== boot / uptime =="
sysctl -n kern.boottime
uptime
echo

if [[ ! -d "$ESP/EFI/OC" ]]; then
    echo "!! $ESP is not mounted. Mount the USB ESP first, e.g.:"
    echo "     sudo diskutil mount disk2s1"
    exit 1
fi

echo "== newest OpenCore log =="
LOG="$(ls -1t "$ESP"/opencore-*.txt 2>/dev/null | head -1)"
echo "$LOG"
echo
echo "--- injection result for the Intel bundles ---"
if [[ -n "$LOG" ]]; then
    grep -aE 'injection IntelBluetoothFirmware|injection IntelBTPatcher|OCAK: .*Intel' "$LOG" || \
        echo "(no Intel injection lines found)"
fi
echo

echo "== loaded kexts (zxystd) =="
kmutil showloaded 2>/dev/null | grep -i zxystd || echo "(none loaded)"
echo

echo "== IOLog diagnostics from the last boot =="
echo "--- IntelBTPatcher (ibtp:) ---"
/usr/bin/log show --last boot --style compact --predicate 'eventMessage CONTAINS "ibtp:"' 2>/dev/null | tail -60 \
    || echo "(log show failed)"
echo "--- IntelBluetoothFirmware (IntelFirmware / AX200DIAG) ---"
/usr/bin/log show --last boot --style compact --predicate 'eventMessage CONTAINS "AX200DIAG" OR eventMessage CONTAINS "IntelFirmware"' 2>/dev/null | tail -40 \
    || echo "(log show failed)"
