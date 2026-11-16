# Building the kexts

`build.sh` builds `IntelBluetoothFirmware.kext` and `IntelBTPatcher.kext` with
clang only. A full Xcode install is not needed; the Command Line Tools are
enough (`xcode-select --install`), plus Python 3.

## Steps

```sh
./bootstrap.sh   # clone upstream, MacKernelSDK and Lilu at pinned commits
./build.sh
```

`bootstrap.sh` clones:

| Tree | Source | Commit |
|---|---|---|
| `upstream/` | OpenIntelWireless/IntelBluetoothFirmware | `a414375` |
| `MacKernelSDK/` | acidanthera/MacKernelSDK | `3f75008` |
| `Lilu/` | acidanthera/Lilu | `0249c3a` |

and applies `diffs/diag-vs-master.diff`, which adds the diagnostic logging
present in the shipped `kexts/`. To build without diagnostics, clone `upstream`
and skip the patch.

`build.sh` writes `kexts/IntelBluetoothFirmware.kext` and
`kexts/IntelBTPatcher.kext`, version string `2.5.0d1`, x86_64.

## Why a clang-only build needs `kmod_info`

A clang-only build does not emit the `_kmod_info` symbol, which Xcode's
kernel-extension target synthesises from the `MODULE_NAME` / `MODULE_VERSION` /
`MODULE_START` / `MODULE_STOP` build settings. Without it, OpenCore cannot find
the kmod address, and injection fails:

```
OC: Prelinked injection IntelBluetoothFirmware.kext (2.4.0) - Invalid Parameter
OC: Prelinked injection IntelBTPatcher.kext (2.4.0) - Invalid Parameter
```

The path is `KextFindKmodAddress` leaving `VirtualKmod == 0`, then
`Library/OcAppleKernelLib/Link.c` returning `EFI_UNSUPPORTED`, which
`PrelinkedInjectKext` turns into `EFI_INVALID_PARAMETER`.

`build.sh` generates a `kmod_info` object for each kext with the same packed
`kmod_info_t` the Xcode build produces (`info_version = 1`, `id = -1`,
`reference_count = -1`, start/stop pointing at the module entry points). Verify:

```sh
nm -m kexts/IntelBluetoothFirmware.kext/Contents/MacOS/IntelBluetoothFirmware | grep _kmod_info
# 0000000000ae40f8 (__DATA,__data) external _kmod_info
```

## Version string

`2.5.0d1` is a string only. Lilu reads the numeric prefix, so it behaves as
`2.5.0`. The suffix marks this local build. The version is set by `VER=` at the
top of `build.sh`.
