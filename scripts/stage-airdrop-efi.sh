#!/bin/bash
# Stage the ForbiddenItlwm AWDL driver on a USB test ESP.
#
# Usage (as root):
#   sudo scripts/stage-airdrop-efi.sh /Volumes/MACOSUSB \
#        [ForbiddenItlwm.kext] [BTLEAdvFixup.kext]
#
# The kext arguments default to ./airdrop/ForbiddenItlwm.kext and
# ./airdrop/BTLEAdvFixup.kext (unzip the Sequoia release assets there first).
#
# What it does:
#   * backs up the whole EFI and the original config.plist
#   * removes AirportItlwm.kext, installs ForbiddenItlwm.kext + BTLEAdvFixup.kext
#   * disables the AirportItlwm/itlwm/IntelBTPatcher entries and adds the new
#     ones in Kernel -> Add (see scripts/airdrop-config.py)
#   * appends the AWDL boot arguments to NVRAM -> Add
#   * validates with plutil and, if available, ocvalidate
#
# The internal boot ESP is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-}"
FORB="${2:-$ROOT/airdrop/ForbiddenItlwm.kext}"
BTLE="${3:-$ROOT/airdrop/BTLEAdvFixup.kext}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "error: run as root:  sudo $0 $*" >&2
    exit 1
fi
if [[ -z "$TARGET" ]]; then
    echo "usage: sudo $0 /Volumes/<USB_ESP> [ForbiddenItlwm.kext] [BTLEAdvFixup.kext]" >&2
    exit 2
fi
TARGET="${TARGET%/}"

if [[ -d "$TARGET/EFI/OC/Kexts" ]]; then
    ESP="$TARGET"
elif [[ -d "$TARGET/OC/Kexts" && "$(basename "$TARGET")" == "EFI" ]]; then
    ESP="$(dirname "$TARGET")"
else
    echo "error: $TARGET is not an OpenCore ESP (no EFI/OC/Kexts)" >&2
    exit 2
fi
EFI="$ESP/EFI"
PLIST="$EFI/OC/config.plist"

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
    echo "error: $ESP is not reported as removable; refusing" >&2
    exit 3
fi

for src in "$FORB" "$BTLE"; do
    [[ -d "$src" ]] || { echo "error: missing kext bundle: $src" >&2; exit 4; }
done
[[ -f "$PLIST" ]] || { echo "error: no $PLIST" >&2; exit 4; }

BACKUP="$ROOT/backups/EFI-airdrop-$STAMP.tar.gz"
mkdir -p "$ROOT/backups"
echo "==> backing up $EFI -> $BACKUP"
tar -czf "$BACKUP" -C "$ESP" EFI
cp "$PLIST" "$ROOT/backups/config.plist.airdrop-$STAMP"

echo "==> installing kexts"
rm -rf "$EFI/OC/Kexts/AirportItlwm.kext" "$EFI/OC/Kexts/itlwm.kext"
cp -R "$FORB" "$EFI/OC/Kexts/ForbiddenItlwm.kext"
cp -R "$BTLE" "$EFI/OC/Kexts/BTLEAdvFixup.kext"
for k in ForbiddenItlwm BTLEAdvFixup; do
    v="$(plutil -extract CFBundleVersion raw "$EFI/OC/Kexts/$k.kext/Contents/Info.plist" 2>/dev/null || echo '?')"
    echo "    $k.kext $v"
done

echo "==> editing config.plist"
echo "  Bluetooth NVRAM fix:"
python3 "$ROOT/scripts/nvram-fix-config.py" "$PLIST"
echo "  AirDrop / AWDL changes:"
python3 "$ROOT/scripts/airdrop-config.py" "$PLIST"

echo "==> validating"
plutil -lint "$PLIST"
if command -v ocvalidate >/dev/null 2>&1; then
    ocvalidate "$PLIST"
elif [[ -x "$ROOT/tools/ocvalidate" ]]; then
    "$ROOT/tools/ocvalidate" "$PLIST"
else
    echo "    ocvalidate not found; validate manually if you have it"
fi

echo
echo "==> staged. Revert with:"
echo "    sudo rm -rf '$EFI/OC/Kexts/ForbiddenItlwm.kext' '$EFI/OC/Kexts/BTLEAdvFixup.kext'"
echo "    sudo tar -xzf '$BACKUP' -C '$ESP'"
echo "    (or restore $ROOT/backups/config.plist.airdrop-$STAMP)"
