#!/bin/bash
# Verify the NVRAM fix for the "Can't obtain vendorID and productID" loop.
# Run after rebooting with the patched USB test EFI config.plist.
set -uo pipefail

echo "===== boot ====="
sysctl -n kern.boottime; uptime; date -u
echo

echo "===== NVRAM bluetooth keys (expect ExternalDongleFailed=00) ====="
for k in bluetoothExternalDongleFailed bluetoothInternalControllerInfo; do
  printf "%-34s = " "$k"; nvram "7C436110-AB2A-4BBB-A880-FE41995C9F82:$k" 2>/dev/null || echo "(absent)"
done
echo

echo "===== bluetoothd: dongle detection + bm3_usb ====="
/usr/bin/log show --last boot --info --debug --style compact 2>/dev/null \
  | grep -aiE 'HasInternalControllerAddr|External Bluetooth dongle|Found external|THIRD_PARTY_DONGLE|Can.t obtain vendorID|GetProductAndVendorID.*(vendorID|Use internal)|Use external' \
  | head -20
echo

echo "===== bluetoothd crash/restart this boot? ====="
/usr/bin/log show --last boot --style compact 2>/dev/null \
  | grep -aiE 'corpse|Transport layer initialization failed|Bluetooth error - restarting' | head -10 \
  || echo "(none)"
echo

echo "===== system_profiler SPBluetoothDataType ====="
system_profiler SPBluetoothDataType 2>/dev/null | sed -n '1,14p'
echo

echo "===== IOBluetoothHCIController / USB transport ====="
ioreg -w0 -l 2>/dev/null | grep -aE 'IOBluetoothHCIController|IOBluetoothHostControllerUSBTransport|"BluetoothTransportConnected"' | head
echo

echo "===== kexts loaded ====="
kmutil showloaded 2>/dev/null | grep -i zxystd
