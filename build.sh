#!/bin/bash
# IntelBluetoothFirmware / IntelBTPatcher clang-only build.
# Reproduces the Xcode settings from IntelBluetoothFirmware.xcodeproj without
# requiring a full Xcode install (Command Line Tools are enough).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/upstream"
MKS="$ROOT/MacKernelSDK"
LILU="$ROOT/Lilu"
BUILD="$ROOT/build"
OUT="$ROOT/out"
VER="2.5.0d1"

SDK_TARGET="x86_64-apple-macos10.12"
CXXFLAGS=(
    -target "$SDK_TARGET"
    -std=gnu++14
    -mkernel -fapple-kext
    -fno-rtti -fno-exceptions -fno-common -fno-builtin
    -Oz -g
    -Wno-unused-parameter -Wno-sign-conversion -Wno-shadow
    -I "$MKS/Headers"
    -I "$LILU/Lilu"
    -DKERNEL=1
)
LDFLAGS=(
    -target "$SDK_TARGET"
    -nostdlib -r
    -Wl,-kext
    -Wl,-no_compact_unwind
    "$MKS/Library/x86_64/libkmod.a"
)

echo "==> preparing"
rm -rf "$BUILD" "$OUT"
mkdir -p "$BUILD/obj" "$OUT"

echo "==> generating FwBinary.cpp"
python3 -c "import sys;sys.path.append('$SRC/scripts');import zlib_compress_fw;zlib_compress_fw.process_files('$SRC/IntelBluetoothFirmware/FwBinary.cpp','$SRC/IntelBluetoothFirmware/fw/')"

compile() {
    local out="$1"; shift
    local file="$1"; shift
    clang++ "${CXXFLAGS[@]}" "$@" -c "$file" -o "$out"
}

# Xcode's kernel-extension target synthesises a `kmod_info` symbol from the
# MODULE_NAME / MODULE_VERSION / MODULE_START / MODULE_STOP build settings.
# Without it OpenCore's prelinker rejects the kext:
#   KextFindKmodAddress -> VirtualKmod == 0 -> Link.c EFI_UNSUPPORTED
#   -> PrelinkedInjectKext EFI_INVALID_PARAMETER ("Invalid Parameter").
# Reproduce the generated object here (see MacKernelSDK/Headers/mach/kmod.h).
echo "==> generating kmod_info sources"
cat > "$BUILD/kmod_fw.cpp" <<EOF
#include <mach/kmod.h>

// zutil.c defines these with C++ linkage; keep the mangling identical.
extern int _start(struct kmod_info *, void *);
extern int _stop(struct kmod_info *, void *);

extern "C" {
kmod_info_t kmod_info = {
    0, KMOD_INFO_VERSION, -1U,
    { "com.zxystd.IntelBluetoothFirmware" },
    { "$VER" },
    -1, 0, 0, 0, 0,
    (kmod_start_func_t *)_start,
    (kmod_stop_func_t *)_stop
};
}
EOF

cat > "$BUILD/kmod_pt.cpp" <<EOF
#include <mach/kmod.h>

extern "C" kern_return_t IntelBTPatcher_kern_start(struct kmod_info *, void *);
extern "C" kern_return_t IntelBTPatcher_kern_stop(struct kmod_info *, void *);

extern "C" {
kmod_info_t kmod_info = {
    0, KMOD_INFO_VERSION, -1U,
    { "com.zxystd.IntelBTPatcher" },
    { "$VER" },
    -1, 0, 0, 0, 0,
    (kmod_start_func_t *)IntelBTPatcher_kern_start,
    (kmod_stop_func_t *)IntelBTPatcher_kern_stop
};
}
EOF

echo "==> building IntelBluetoothFirmware.kext"
FW_OBJS=()
for f in BtIntel.cpp BtIntelFw.cpp BtIntelVSC.cpp IntelBluetoothFirmware.cpp \
         IntelBluetoothOpsGen1.cpp IntelBluetoothOpsGen2.cpp IntelBluetoothOpsGen3.cpp \
         USBDeviceController.cpp FwBinary.cpp; do
    o="$BUILD/obj/${f%.*}.o"
    compile "$o" "$SRC/IntelBluetoothFirmware/$f" \
        -I "$SRC/IntelBluetoothFirmware" \
        -DMODULE_VERSION="$VER" -DPRODUCT_NAME=IntelBluetoothFirmware
    FW_OBJS+=("$o")
done
# zutil.c is C++-ish (extern "C" helpers); compile as C++ like the Xcode target does.
compile "$BUILD/obj/zutil.o" "$SRC/IntelBluetoothFirmware/zutil.c" \
    -I "$SRC/IntelBluetoothFirmware" -DMODULE_VERSION="$VER" -DPRODUCT_NAME=IntelBluetoothFirmware
FW_OBJS+=("$BUILD/obj/zutil.o")
compile "$BUILD/obj/kmod_fw.o" "$BUILD/kmod_fw.cpp"
FW_OBJS+=("$BUILD/obj/kmod_fw.o")

clang++ "${LDFLAGS[@]}" -o "$BUILD/IntelBluetoothFirmware" "${FW_OBJS[@]}"

echo "==> building IntelBTPatcher.kext"
PT_OBJS=("$BUILD/obj/IntelBTPatcher.o" "$BUILD/obj/plugin_start.o")
compile "$BUILD/obj/IntelBTPatcher.o" "$SRC/IntelBTPatcher/IntelBTPatcher.cpp" \
    -I "$SRC/IntelBTPatcher" -DMODULE_VERSION="$VER" -DPRODUCT_NAME=IntelBTPatcher
compile "$BUILD/obj/plugin_start.o" "$LILU/Lilu/Library/plugin_start.cpp" \
    -DMODULE_VERSION="$VER" -DPRODUCT_NAME=IntelBTPatcher
compile "$BUILD/obj/kmod_pt.o" "$BUILD/kmod_pt.cpp"
PT_OBJS+=("$BUILD/obj/kmod_pt.o")
clang++ "${LDFLAGS[@]}" -o "$BUILD/IntelBTPatcher" "${PT_OBJS[@]}"

package_kext() {
    local name="$1" bin="$2" srcplist="$3" plist_id="$4" exec_name="$5"
    local dst="$OUT/$name.kext"
    mkdir -p "$dst/Contents/MacOS"
    cp "$bin" "$dst/Contents/MacOS/$exec_name"
    sed -e "s|\$(DEVELOPMENT_LANGUAGE)|en|g" \
        -e "s|\$(EXECUTABLE_NAME)|$exec_name|g" \
        -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$plist_id|g" \
        -e "s|\$(PRODUCT_NAME:rfc1034identifier)|$name|g" \
        -e "s|\$(PRODUCT_NAME)|$name|g" \
        -e "s|\$(PRODUCT_BUNDLE_PACKAGE_TYPE)|KEXT|g" \
        -e "s|\$(MARKETING_VERSION)|$VER|g" \
        -e "s|\$(CURRENT_PROJECT_VERSION)|$VER|g" \
        -e "s|\$(MODULE_VERSION)|$VER|g" \
        "$srcplist" > "$dst/Contents/Info.plist"
    plutil -lint "$dst/Contents/Info.plist" >/dev/null
    echo "    $dst"
}

echo "==> packaging"
package_kext IntelBluetoothFirmware "$BUILD/IntelBluetoothFirmware" \
    "$SRC/IntelBluetoothFirmware/Info.plist" com.zxystd.IntelBluetoothFirmware IntelBluetoothFirmware
package_kext IntelBTPatcher "$BUILD/IntelBTPatcher" \
    "$SRC/IntelBTPatcher/Info.plist" com.zxystd.IntelBTPatcher IntelBTPatcher

echo "==> done"
ls -l "$OUT"
file "$OUT"/*/Contents/MacOS/* || true
