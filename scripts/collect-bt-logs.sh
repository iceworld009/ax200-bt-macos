#!/bin/bash
# Collect the Bluetooth diagnostics we need after booting the test EFI.
# Usage: ./collect-bt-logs.sh [minutes]     (default: 30)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MIN="${1:-30}"
OUT="$ROOT/logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
LOG=/usr/bin/log   # zsh builtin 'log' shadows it

echo "==> writing to $OUT"

# Kernel messages from our kexts and IOBluetooth.
$LOG show --last "${MIN}m" --style syslog --info --debug \
    --predicate 'process == "kernel"' 2>/dev/null > "$OUT/kernel.log"

$LOG show --last "${MIN}m" --style syslog --info --debug \
    --predicate 'eventMessage CONTAINS "ibtp:" OR eventMessage CONTAINS "AX200DIAG" OR eventMessage CONTAINS "IntelFirmware" OR eventMessage CONTAINS "Bluetooth"' \
    2>/dev/null > "$OUT/bt-filtered.log"

$LOG show --last "${MIN}m" --style syslog --info --debug \
    --predicate 'senderImagePath CONTAINS "IOBluetooth" OR process == "bluetoothd"' \
    2>/dev/null > "$OUT/bluetoothd.log"

# Kext presence / firmware state.
ioreg -l -w0 -p IOUSB > "$OUT/ioreg-usb.txt" 2>/dev/null
ioreg -l -w0 > "$OUT/ioreg-all.txt" 2>/dev/null
{
    echo "# loaded kexts"
    kmutil showloaded 2>/dev/null | grep -iE "Intel|BlueTool|Lilu"
    echo
    echo "# bluetooth prefs"
    defaults read /Library/Preferences/com.apple.Bluetooth 2>/dev/null | head -80
    echo
    echo "# controller props"
    system_profiler SPBluetoothDataType 2>/dev/null
} > "$OUT/state.txt"

cp /Library/Logs/DiagnosticReports/*bluetoothd* "$OUT/" 2>/dev/null || true

echo "==> summary"
echo "ibtp lines      : $(grep -c 'ibtp:' "$OUT/bt-filtered.log" 2>/dev/null || echo 0)"
echo "AX200DIAG lines : $(grep -c 'AX200DIAG' "$OUT/bt-filtered.log" 2>/dev/null || echo 0)"
echo "IntelFirmware   : $(grep -c 'IntelFirmware' "$OUT/bt-filtered.log" 2>/dev/null || echo 0)"
echo
echo "Key lines:"
grep -hE "ibtp:|AX200DIAG|ConnectionComplete|deviceConnected|FirmwareLoaded|fw_name" \
    "$OUT"/*.log 2>/dev/null | tail -40
