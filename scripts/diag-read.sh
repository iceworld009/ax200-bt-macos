#!/bin/bash
# Read the IORegistry diagnostics published by the instrumented IntelBluetoothFirmware.
# This is the only reliable channel: third-party kext IOLog does not reach the
# unified log on modern macOS.
set -uo pipefail

echo "== boot =="
sysctl -n kern.boottime; uptime; date -u
echo

echo "== zxystd kexts loaded =="
kmutil showloaded 2>/dev/null | grep -i zxystd || echo "(none)"
echo

echo "== diag_* properties on the Bluetooth USB device =="
ioreg -w0 -l 2>/dev/null | grep -aE 'diag_|FirmwareLoaded|fw_name|Bluetooth USB Host Controller' | sed 's/^ *//' | head -60
echo

echo "== BT controller state =="
system_profiler SPBluetoothDataType 2>/dev/null | sed -n '1,20p'
echo

echo "== is the Apple USB transport attached? =="
ioreg -w0 2>/dev/null | grep -iE 'IOBluetoothHostControllerUSBTransport|IOBluetoothHCIController' | head
