#!/bin/bash
# READ-ONLY inspection of the USB ESP and the internal ESP.
# Mounts each one read-only (or falls back to default), then prints:
#   - OpenCore debug/log settings
#   - Kernel:Add entries for the Intel kexts (Enabled/paths/kernel range)
#   - Kernel:Block / Kernel:Force payloads
#   - the Kexts folder contents + Intel bundle versions + binary hashes
#   - any OpenCore boot log lines about injection
# It never writes to the ESPs.
#
# Run with:  sudo bash /Users/bogdan/ax200-bt-dev/inspect-efis.sh

set -u

if [[ $EUID -ne 0 ]]; then
    echo "please run with sudo (needs root to mount ESPs)" >&2
    exit 1
fi

PY=/usr/bin/python3
OUT_BIN_DIR="/Users/bogdan/ax200-bt-dev/out"

mount_esp() {
    local dev="$1" label="$2"
    local mp="/Volumes/_insp_$label"
    mkdir -p "$mp"
    if mount | grep -q " on $mp "; then
        echo "$mp already mounted" >&2
        echo "$mp"
        return 0
    fi
    # Try read-only first, then plain.
    if /sbin/mount_msdos -o ro,nodev,nosuid "/dev/$dev" "$mp" 2>/dev/null \
       || /sbin/mount -t msdos -o ro,nodev,nosuid "/dev/$dev" "$mp" 2>/dev/null \
       || /sbin/mount_msdos -o nodev,nosuid "/dev/$dev" "$mp" 2>/dev/null \
       || /sbin/mount_msdos "/dev/$dev" "$mp" 2>/dev/null; then
        echo "$mp"
        return 0
    fi
    echo "MOUNT_FAILED:$dev" >&2
    return 1
}

report_esp() {
    local mp="$1" label="$2"
    echo
    echo "=============================================================="
    echo " $label  ($mp)"
    echo "=============================================================="
    if [[ ! -d "$mp/EFI" ]]; then
        echo "no EFI directory here"
        return
    fi
    local P="$mp/EFI/OC/config.plist"
    if [[ ! -f "$P" ]]; then
        echo "no EFI/OC/config.plist"
        return
    fi
    echo "-- plist lint --"
    plutil -lint "$P" 2>&1
    echo "-- Misc:Debug --"
    /usr/libexec/PlistBuddy -c "Print :Misc:Debug:Target" "$P" 2>&1
    /usr/libexec/PlistBuddy -c "Print :Misc:Debug:DisplayLevel" "$P" 2>&1
    echo "-- Kernel:Scheme --"
    /usr/libexec/PlistBuddy -c "Print :Kernel:Scheme" "$P" 2>&1
    echo "-- Kernel:Block --"
    /usr/libexec/PlistBuddy -c "Print :Kernel:Block" "$P" 2>&1 | head -40
    echo "-- Kernel:Force --"
    /usr/libexec/PlistBuddy -c "Print :Kernel:Force" "$P" 2>&1 | head -40
    echo "-- Kernel:Add (all entries: Enabled | Arch | BundlePath | Exec | Comment) --"
    plutil -convert json -o /tmp/_cfg_$$.json "$P" 2>/dev/null && $PY - /tmp/_cfg_$$.json <<'PYEOF'
import json,sys
c=json.load(open(sys.argv[1]))
add=c.get('Kernel',{}).get('Add',[])
for i,e in enumerate(add):
    print("%2d  %-5s %-6s %-55s %-40s %s" % (
        i, str(e.get('Enabled')), e.get('Arch',''),
        e.get('BundlePath',''), e.get('ExecutablePath',''), e.get('Comment','')))
PYEOF
    rm -f /tmp/_cfg_$$.json
    echo "-- Kexts folder --"
    ls -la "$mp/EFI/OC/Kexts" 2>&1 | sed -n '1,80p'
    echo "-- Intel bundles --"
    for k in IntelBTPatcher IntelBluetoothFirmware; do
        local d="$mp/EFI/OC/Kexts/$k.kext"
        echo "  == $k == "
        if [[ ! -d "$d" ]]; then
            echo "     MISSING directory $d"
            continue
        fi
        echo -n "     version="
        plutil -extract CFBundleVersion raw "$d/Contents/Info.plist" 2>&1 || echo "(no plist)"
        local b="$d/Contents/MacOS/$k"
        if [[ -f "$b" ]]; then
            echo -n "     binary size=$(stat -f%z "$b") sha256="
            shasum -a 256 "$b" | awk '{print $1}'
        else
            echo "     MISSING binary $b"
        fi
        # nested bundle detection
        if [[ -d "$d/$k.kext" ]]; then
            echo "     !! NESTED bundle: $d/$k.kext"
        fi
        ls -la "$d/Contents" 2>&1 | sed -n '1,20p'
        ls -la "$d/Contents/MacOS" 2>&1 | sed -n '1,10p'
    done
    echo "-- OpenCore logs --"
    ls -la "$mp/EFI/OC"/opencore-*.txt 2>/dev/null || echo "     (no opencore-*.txt)"
    for f in "$mp/EFI/OC"/opencore-*.txt; do
        [[ -f "$f" ]] || continue
        echo "     ---- $f (injection/kext lines) ----"
        grep -iE "IntelBT|IntelBluetooth|injection|skips|missing|Plist|Image|Kexts" "$f" | head -80
    done
}

echo "=== our built binaries (for hash comparison) ==="
for k in IntelBTPatcher IntelBluetoothFirmware; do
    b="/Users/bogdan/ax200-bt-dev/out/$k.kext/Contents/MacOS/$k"
    [[ -f "$b" ]] && { echo -n "$k size=$(stat -f%z "$b") sha256="; shasum -a 256 "$b" | awk '{print $1}'; }
done

USB_MP="$(mount_esp disk2s1 USB 2>/dev/null)" || USB_MP=""
INT_MP="$(mount_esp disk0s1 INTERNAL 2>/dev/null)" || INT_MP=""

[[ -n "$USB_MP" ]] && report_esp "$USB_MP" "USB ESP (disk2s1)"
[[ -n "$INT_MP" ]] && report_esp "$INT_MP" "INTERNAL ESP (disk0s1)"

echo
echo "=== done. ESPs left mounted read-only at /Volumes/_insp_USB and /Volumes/_insp_INTERNAL ==="
