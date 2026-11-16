#!/bin/bash
# Post-boot check for the ForbiddenItlwm AWDL / AirDrop setup.
# Run after booting the staged USB EFI.
set -uo pipefail

echo "== boot =="
sysctl -n kern.boottime

echo
echo "== kexts =="
kmutil showloaded 2>/dev/null | grep -iE "ForbiddenItlwm|BTLEAdvFixup|IntelBluetoothFirmware|IntelBTPatcher|AirportItlwm|Lilu|BlueToolFixup" \
    | sed 's/^/  /' || echo "  (none)"

echo
echo "== boot-args =="
nvram boot-args 2>/dev/null | sed 's/^/  /'

echo
echo "== interfaces =="
echo "  all: $(ifconfig -l)"
echo "  awdl0:"
ifconfig awdl0 2>&1 | sed 's/^/    /'

echo
echo "== AWDL listener (IORegistry) =="
ioreg -l -w0 2>/dev/null \
    | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|CountryLearned)"' \
    | sed 's/^ *//' | sed 's/^/  /' || echo "  (no AWDL properties found)"

echo
echo "== Wi-Fi hardware =="
networksetup -listallhardwareports 2>/dev/null | grep -A2 -i 'Wi-Fi' | sed 's/^/  /'

echo
echo "== Bluetooth =="
system_profiler SPBluetoothDataType 2>/dev/null | sed -n '1,10p' | sed 's/^/  /'
