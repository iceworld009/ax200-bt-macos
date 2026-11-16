#!/usr/bin/env python3
"""Apply the ForbiddenItlwm / AWDL changes to an OpenCore config.plist.

Idempotent. Usage:

    airdrop-config.py <path/to/config.plist>

Changes:

* Disable the ``AirportItlwm.kext``, ``itlwm.kext`` and ``IntelBTPatcher.kext``
  entries in ``Kernel -> Add``. IntelBTPatcher must be off: it and BTLEAdvFixup
  hook the same function, and Lilu panics when two plugins do.
* Add ``BTLEAdvFixup.kext`` and ``ForbiddenItlwm.kext`` to ``Kernel -> Add``,
  limited to Sequoia (MinKernel 24.0.0, MaxKernel 24.99.99). They are appended,
  so they load after Lilu and BlueToolFixup.
* Append the AWDL boot arguments to ``NVRAM -> Add -> boot-args`` and make sure
  ``boot-args`` is listed under ``NVRAM -> Delete`` for the same GUID.
"""
import plistlib
import sys

GUID = "7C436110-AB2A-4BBB-A880-FE41995C9F82"

AWDL_FLAGS = [
    "-btleadv",
    "-itlawdlcoexprobe",
    "-itlawdliface",
    "-itlawdlnativeup",
    "-itlawdlcoexrx",
    "-itlawdlcoextx",
    "-itlawdlcoexmulti",
    "-itlawdlcoexdata",
    "-itlawdlmitx",
    "-itlawdlelicit",
    "-itlawdlcaps",
    "-itlawdlsvcmerge",
    "-itlawdlawsync",
    "itlawdlintcoal=4",
    "-itlawdlcoexbatx",
    "-itlawdlcoexpeerpause",
    "-itlawdlcoexbatrace",
    "itlawdltxqueue=4096",
]

DISABLE = ("AirportItlwm.kext", "itlwm.kext", "IntelBTPatcher.kext")

ADD = [
    ("BTLEAdvFixup.kext", "Contents/MacOS/BTLEAdvFixup"),
    ("ForbiddenItlwm.kext", "Contents/MacOS/ForbiddenItlwm"),
]


def kext_entry(bundle_path, executable_path):
    return {
        "Arch": "Any",
        "BundlePath": bundle_path,
        "Comment": "AirDrop / AWDL",
        "Enabled": True,
        "ExecutablePath": executable_path,
        "MaxKernel": "24.99.99",
        "MinKernel": "24.0.0",
        "PlistPath": "Contents/Info.plist",
    }


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: airdrop-config.py <path/to/config.plist>")
    path = sys.argv[1]

    with open(path, "rb") as f:
        d = plistlib.load(f)

    kernel_add = d.setdefault("Kernel", {}).setdefault("Add", [])

    for entry in kernel_add:
        bundle = entry.get("BundlePath", "")
        if bundle in DISABLE and entry.get("Enabled"):
            entry["Enabled"] = False
            print(f"  disabled  {bundle}")

    present = {e.get("BundlePath") for e in kernel_add}
    for bundle, exe in ADD:
        if bundle in present:
            print(f"  present   {bundle}")
        else:
            kernel_add.append(kext_entry(bundle, exe))
            print(f"  added     {bundle}")

    nvram = d.setdefault("NVRAM", {})
    nv_add = nvram.setdefault("Add", {}).setdefault(GUID, {})
    boot_args = nv_add.get("boot-args", "")
    have = boot_args.split()
    for flag in AWDL_FLAGS:
        if flag not in have:
            have.append(flag)
    nv_add["boot-args"] = " ".join(have)
    print(f"  boot-args {nv_add['boot-args']}")

    nv_del = nvram.setdefault("Delete", {}).setdefault(GUID, [])
    if "boot-args" not in nv_del:
        nv_del.append("boot-args")
        print("  added     boot-args to NVRAM -> Delete")

    with open(path, "wb") as f:
        plistlib.dump(d, f, sort_keys=False)
    print(f"  wrote     {path}")


if __name__ == "__main__":
    main()
