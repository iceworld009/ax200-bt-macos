#!/bin/bash
# Stage the diagnostic kexts onto a *test* OpenCore ESP (USB stick).
# The internal disk ESP is never touched. A full backup of the target EFI
# directory is taken before anything is replaced.
#
# Usage:
#   ./stage-test-efi.sh /Volumes/MACOSUSB          # ESP volume
#   ./stage-test-efi.sh /Volumes/MACOSUSB/EFI      # EFI folder itself
#
# Safety: the target volume must be removable and contain EFI/OC/Kexts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ -z "$TARGET" ]]; then
    echo "usage: $0 /Volumes/<USB_ESP>" >&2
    exit 2
fi
TARGET="${TARGET%/}"

# Accept either the ESP mount point (/Volumes/X) or its EFI folder (/Volumes/X/EFI).
if [[ -d "$TARGET/EFI/OC/Kexts" ]]; then
    ESP="$TARGET"
elif [[ -d "$TARGET/OC/Kexts" && "$(basename "$TARGET")" == "EFI" ]]; then
    ESP="$(dirname "$TARGET")"
else
    echo "error: $TARGET does not look like an OpenCore ESP (no EFI/OC/Kexts)" >&2
    exit 2
fi
EFI="$ESP/EFI"

# Refuse the internal disk. Compare the physical store of the target volume
# with the boot disk (/dev/disk0 on this machine).
BOOT_DISK="$(diskutil info / 2>/dev/null | awk -F': *' '/Part of Whole/{print $2; exit}' || true)"
TARGET_DISK="$(diskutil info "$ESP" 2>/dev/null | awk -F': *' '/Part of Whole/{print $2; exit}' || true)"
REMOVABLE="$(diskutil info "$ESP" 2>/dev/null | awk -F': *' '/Removable Media/{print $2; exit}' || true)"
echo "target      : $ESP"
echo "target disk : ${TARGET_DISK:-unknown} (removable: ${REMOVABLE:-unknown})"
echo "boot disk   : ${BOOT_DISK:-unknown}"
if [[ -n "${BOOT_DISK:-}" && "${TARGET_DISK:-}" == "${BOOT_DISK}" ]]; then
    echo "error: refusing to modify the internal boot ESP" >&2
    exit 3
fi
if [[ "${REMOVABLE:-}" != "Removable" ]]; then
    echo "error: target volume is not reported as removable; refusing" >&2
    echo "       (pass CONFIRM_INTERNAL_TEST_EFI=1 to override only if you are certain)" >&2
    [[ "${CONFIRM_INTERNAL_TEST_EFI:-0}" == "1" ]] || exit 3
fi

for k in IntelBTPatcher IntelBluetoothFirmware; do
    if [[ ! -d "$ROOT/out/$k.kext" ]]; then
        echo "error: missing $ROOT/out/$k.kext (run ./build.sh first)" >&2
        exit 4
    fi
done

# TCC "Removable Volumes": stat() can succeed while readdir/read is denied, so
# probe with a real directory listing before touching anything.
if ! ls "$EFI/OC/Kexts" >/dev/null 2>&1; then
    echo "error: cannot read $EFI/OC/Kexts" >&2
    echo "       macOS blocks removable-volume access for this terminal app." >&2
    echo "       System Settings > Privacy & Security > Full Disk Access (or" >&2
    echo "       Files and Folders > <your terminal> > Removable Volumes)," >&2
    echo "       enable it, quit and reopen the terminal, then re-run." >&2
    exit 5
fi

BACKUP="$ROOT/backups/EFI-$STAMP.tar.gz"
mkdir -p "$ROOT/backups"
echo "==> backing up $EFI to $BACKUP"
tar -czf "$BACKUP" -C "$ESP" EFI
# Keep the original kexts separately for a one-line revert.
ORIG="$ROOT/backups/original-kexts-$STAMP"
mkdir -p "$ORIG"
for k in IntelBTPatcher IntelBluetoothFirmware; do
    [[ -d "$EFI/OC/Kexts/$k.kext" ]] && cp -R "$EFI/OC/Kexts/$k.kext" "$ORIG/"
done

echo "==> installing diagnostic kexts"
for k in IntelBTPatcher IntelBluetoothFirmware; do
    rm -rf "$EFI/OC/Kexts/$k.kext"
    cp -R "$ROOT/out/$k.kext" "$EFI/OC/Kexts/$k.kext"
    echo "    $k.kext $(plutil -extract CFBundleVersion raw "$EFI/OC/Kexts/$k.kext/Contents/Info.plist")"
done

# Verify that OpenCore config references both bundles (it should, the bundle
# identifiers are unchanged). Report only, never edit config.plist here.
PLIST="$EFI/OC/config.plist"
if [[ -f "$PLIST" ]]; then
    for k in IntelBTPatcher IntelBluetoothFirmware; do
        if /usr/libexec/PlistBuddy -c "Print :Kernel:Add" "$PLIST" 2>/dev/null | grep -q "BundlePath = $k.kext"; then
            echo "    config.plist: $k.kext entry present"
        else
            echo "    WARNING: config.plist has no Kernel:Add entry for $k.kext" >&2
        fi
    done
fi

echo
echo "==> staged. Revert with:"
echo "    sudo rm -rf '$EFI/OC/Kexts/IntelBTPatcher.kext' '$EFI/OC/Kexts/IntelBluetoothFirmware.kext'"
echo "    sudo cp -R '$ORIG/'*.kext '$EFI/OC/Kexts/'"
echo "    (or restore the whole tree: tar -xzf '$BACKUP' -C '$ESP')"
