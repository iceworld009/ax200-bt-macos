# The Bluetooth NVRAM fix

## What goes wrong

`bluetoothd` decides whether to adopt a USB Bluetooth controller as the
"external dongle" by reading two NVRAM variables in the GUID
`7C436110-AB2A-4BBB-A880-FE41995C9F82`. If `bluetoothExternalDongleFailed` is
`01`, it rejects the Intel controller and looks for an internal Broadcom part
that this machine does not have (`BCM_4350C2`). Bluetooth then stays off:

```
Address: NULL
State: Off
Chipset: BCM_4350C2
Firmware Version: v0 c0
```

The firmware and kexts are fine; only this variable is wrong.

## Why `NVRAM → Add` alone is not enough

macOS rewrites the variable during boot. Clearing it once does not survive a
reboot, so it has to be forced on every boot. OpenCore can do that, but only if
the key is listed under **both** `Add` and `Delete`:

- `Add` writes the desired value.
- `Delete` removes the existing variable first. OpenCore cannot overwrite a
  pre-existing variable whose attributes differ from the ones in `Add`, so
  without `Delete` the stale value survives and `Add` has no effect.

## The config

In `EFI/OC/config.plist`, under `NVRAM`:

```xml
<key>NVRAM</key>
<dict>
  <key>Add</key>
  <dict>
    <key>7C436110-AB2A-4BBB-A880-FE41995C9F82</key>
    <dict>
      <key>bluetoothExternalDongleFailed</key>
      <data>AA==</data>
      <key>bluetoothInternalControllerInfo</key>
      <data>AAAAAAAAAAAAAAAAAAA=</data>
    </dict>
  </dict>
  <key>Delete</key>
  <dict>
    <key>7C436110-AB2A-4BBB-A880-FE41995C9F82</key>
    <array>
      <string>bluetoothExternalDongleFailed</string>
      <string>bluetoothInternalControllerInfo</string>
    </array>
  </dict>
</dict>
```

`AA==` is base64 for one `00` byte. `AAAAAAAAAAAAAAAAAAA=` is base64 for 14
`00` bytes. The values must be `<data>`, not `<string>`.

## Editing the plist

Do not use `PlistBuddy` for these keys; it mangles `<data>` values. Edit with a
plist editor or Python `plistlib`. Minimal example that sets both keys and the
matching `Delete` names:

```python
import plistlib

path = "EFI/OC/config.plist"
guid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"

with open(path, "rb") as f:
    d = plistlib.load(f)

add = d.setdefault("NVRAM", {}).setdefault("Add", {}).setdefault(guid, {})
add["bluetoothExternalDongleFailed"] = b"\x00"
add["bluetoothInternalControllerInfo"] = b"\x00" * 14

delete = d.setdefault("NVRAM", {}).setdefault("Delete", {}).setdefault(guid, [])
for key in ("bluetoothExternalDongleFailed", "bluetoothInternalControllerInfo"):
    if key not in delete:
        delete.append(key)

with open(path, "wb") as f:
    plistlib.dump(d, f, sort_keys=False)
```

Validate:

```sh
plutil -lint EFI/OC/config.plist
ocvalidate EFI/OC/config.plist
```

## Verifying

After one reboot:

```sh
nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:bluetoothExternalDongleFailed
# ... %00

system_profiler SPBluetoothDataType | sed -n '1,12p'
# Address: 34:C9:3D:9F:83:D6
# State: On
# Chipset: THIRD_PARTY_DONGLE
```

`scripts/verify-nvram-fix.sh` does both. The `bluetoothd` log should contain
`Found external Bluetooth dongle` instead of the `BCM_4350C2` loop.

## Reverting

```sh
nvram -d 7C436110-AB2A-4BBB-A880-FE41995C9F82:bluetoothExternalDongleFailed
nvram -d 7C436110-AB2A-4BBB-A880-FE41995C9F82:bluetoothInternalControllerInfo
```

and remove both names from `NVRAM → Add` and `NVRAM → Delete` in the config.

## Mounting the ESP

On this install, mounting an internal EFI partition needs root (DiskArbitration
skips EFI partitions owned by uid 0 for normal users). `scripts/internal-efi-phase1.sh`
mounts and backs up the internal ESP through an admin prompt;
`scripts/mount-usb-efi.sh` does the same for a USB ESP.
