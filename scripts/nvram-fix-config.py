#!/usr/bin/env python3
"""Force the Bluetooth NVRAM keys in an OpenCore config.plist.

Idempotent. Usage:

    nvram-fix-config.py <path/to/config.plist>

Sets, for the Apple Bluetooth GUID:

    bluetoothExternalDongleFailed   = 00        (1 byte)
    bluetoothInternalControllerInfo = 14 x 00

in ``NVRAM -> Add``, and adds both key names to ``NVRAM -> Delete``. The
``Delete`` half is required: OpenCore cannot overwrite a pre-existing variable
whose attributes differ from the ones in ``Add``. See docs/NVRAM-FIX.md.
"""
import plistlib
import sys

GUID = "7C436110-AB2A-4BBB-A880-FE41995C9F82"

KEYS = {
    "bluetoothExternalDongleFailed": b"\x00",
    "bluetoothInternalControllerInfo": b"\x00" * 14,
}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: nvram-fix-config.py <path/to/config.plist>")
    path = sys.argv[1]

    with open(path, "rb") as f:
        d = plistlib.load(f)

    nvram = d.setdefault("NVRAM", {})
    add = nvram.setdefault("Add", {}).setdefault(GUID, {})
    for key, value in KEYS.items():
        add[key] = value
        print(f"  Add    {key} = <{value.hex()}>")

    delete = nvram.setdefault("Delete", {}).setdefault(GUID, [])
    for key in KEYS:
        if key not in delete:
            delete.append(key)
            print(f"  Delete {key}")

    with open(path, "wb") as f:
        plistlib.dump(d, f, sort_keys=False)
    print(f"  wrote  {path}")


if __name__ == "__main__":
    main()
