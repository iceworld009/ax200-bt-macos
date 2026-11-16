# Intel AX200 on macOS Sequoia: Bluetooth and AirDrop

Notes, kexts and scripts from getting an Intel AX200 (`8087:0029`) working on a
macOS 15.8.3 (24H241) OpenCore hackintosh. Two independent problems, two fixes:

- **Bluetooth** would not connect any classic device. The kexts were fine. The
  cause was a stale NVRAM variable that made `bluetoothd` fall back to a
  non-existent Broadcom chip.
- **AirDrop** does not work with `AirportItlwm`, because it implements no AWDL.
  The `ForbiddenItlwm` fork adds AWDL and makes AirDrop work.

This is a record of one machine, not a supported installer. Read a section
through before applying it.

## Hardware and software

| Component | Value |
|---|---|
| Wi-Fi / Bluetooth | Intel AX200, Bluetooth over USB `8087:0029` |
| macOS | 15.8.3, build 24H241 (Sequoia) |
| Bootloader | OpenCore 1.0.8 (RELEASE) |
| Wi-Fi driver | `AirportItlwm` 2.4.0 (or `ForbiddenItlwm` for AirDrop) |
| Bluetooth | `IntelBluetoothFirmware` + `IntelBTPatcher` + `BlueToolFixup` |

## Bluetooth

### Symptom

The AX200 firmware loaded and the controller came up, but classic devices never
connected. `system_profiler SPBluetoothDataType` reported:

```
Address: NULL
State: Off
Chipset: BCM_4350C2
Firmware Version: v0 c0
```

and `bluetoothd` looped, then restarted, every ~15 s:

```
External Bluetooth dongle was not found -- setting chipset to default BCM_4350C2
[bm3_usb][GetProductAndVendorID] -- Use internal Bluetooth USB Host Controller
[bm3_usb][IOThreadFunc] -- USB -- Can't obtain vendorID and productID -- try again
```

`BCM_4350C2` is a Broadcom part this machine does not have. `bluetoothd` was
ignoring the Intel controller and looking for an internal Broadcom one.

### Root cause

This is upstream issue
[OpenIntelWireless/IntelBluetoothFirmware#513](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/issues/513).
macOS decides whether to adopt the USB controller as the "external dongle" by
reading two NVRAM variables. If `bluetoothExternalDongleFailed` is `01`, it
refuses the Intel controller and falls back to `BCM_4350C2`.

| NVRAM key (GUID `7C436110-AB2A-4BBB-A880-FE41995C9F82`) | broken | fixed |
|---|---|---|
| `bluetoothExternalDongleFailed` | `01` | `00` |
| `bluetoothInternalControllerInfo` | 14 bytes `00` | 14 bytes `00` |

The value had been left set from an earlier boot. Clearing it once is not
enough: macOS rewrites it during boot, so it has to be forced on every boot.

### Fix

Force both variables at every boot through OpenCore. They must be in **both**
`NVRAM → Add` and `NVRAM → Delete` for the same GUID. `Add` alone is not
enough: OpenCore cannot overwrite a pre-existing variable whose attributes
differ from the ones in `Add`, so the stale value survives. `Delete` removes it
first, then `Add` writes the correct one.

In `EFI/OC/config.plist`:

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

`AA==` is base64 for a single `00` byte; the 14-byte value is 14 zero bytes.
Edit the plist with a plist editor or Python `plistlib`, not `PlistBuddy`
(which mangles `<data>` values). Validate with `plutil -lint` and `ocvalidate`.

### Result

After one reboot:

```
Found external Bluetooth dongle -- setting chipset to THIRD_PARTY_DONGLE
[bm3_usb][GetProductAndVendorID] -- Found external Bluetooth dongle -- vendorID = 0x8087, produceID = 0x0029
Using external Bluetooth dongle, do not read info from NVRAM
GetControllerInfo: BlSt PoweredOn, Chip THIRD_PARTY_DONGLE, FrmV v256 c256, HWAd 34:C9:3D:9F:83:D6, LMPv 10 (5.1)
```

`system_profiler SPBluetoothDataType` then shows `State: On`,
`Chipset: THIRD_PARTY_DONGLE`, `Firmware Version: v256 c256`,
`Transport: USB`. The headset pairs, connects and streams A2DP.

Verify after a reboot with `scripts/verify-nvram-fix.sh`.

### Kexts

The fix above is what actually matters. The kexts in `kexts/` are a known-good
set built from upstream `master` at `a414375` (version string `2.5.0d1`,
x86_64). They include upstream commit `50e971c` ("compat for Sequoia: the HCI
memory descriptor is not prepared and can not be used directly"), which the
released 2.4.0 does not.

`IntelBluetoothFirmware` loads the firmware and drives the controller.
`IntelBTPatcher` patches the Sequoia HCI path at runtime. `BlueToolFixup` is
from [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM).
The build is described under [Building](#building) below.

## AirDrop

AirDrop needs AWDL (Apple Wireless Direct Link), a peer-to-peer Wi-Fi mode.
`AirportItlwm` does not implement it, so `wifip2pd` cannot create `awdl0`:

```
wifip2pd: Cannot create AWDL interface because the device is missing the capability
wifip2pd: Failed to create interface AWDL on en0 with error <Apple80211Error Operation Not Supported>
airportd: Failed to match cached interface (role=awdl parent=(null))
```

Bluetooth-based AirDrop *discovery* runs, but the AWDL transport that carries
the transfer does not, so AirDrop, Handoff and Continuity do not work. This is
the documented behaviour of `AirportItlwm`.

[retropineaple/ForbiddenItlwm](https://github.com/retropineaple/ForbiddenItlwm)
is a fork that adds an AWDL implementation on top of the Intel driver, and a
companion `BTLEAdvFixup.kext` that lets `bluetoothd` start LE advertising.
Together they enable AirDrop on the AX200.

**Set this up on a USB stick first.** Copy your working EFI to a USB stick and
make every change there, so the internal EFI stays bootable. The full procedure
is in [docs/AIRDROP.md](docs/AIRDROP.md). In short:

1. On the USB EFI, remove `AirportItlwm.kext`, add `ForbiddenItlwm.kext` and
   `BTLEAdvFixup.kext` (Sequoia builds).
2. **Disable `IntelBTPatcher.kext`.** It and `BTLEAdvFixup` hook the same
   function, and Lilu panics if two plugins do. `BTLEAdvFixup` takes over.
3. Add the `-itlawdl*` / `-btleadv` boot arguments to `NVRAM → Add` (keep
   `boot-args` in `NVRAM → Delete`).
4. Validate, boot the stick, join Wi-Fi, then check for the AWDL listener:

   ```sh
   ioreg -l -w0 | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|CountryLearned)"'
   ```

   Expect `Added` Yes, `Channel` 149, `CountryLearned` Yes.

5. Turn on AirDrop on both devices and send a file each way.

## Repository layout

```
kexts/          prebuilt IntelBluetoothFirmware.kext and IntelBTPatcher.kext (2.5.0d1)
build.sh        clang-only build of both kexts (no Xcode required)
bootstrap.sh    fetch build dependencies (upstream source, MacKernelSDK, Lilu)
diffs/          patches applied on top of upstream for diagnostics
docs/           AIRDROP.md, NVRAM-FIX.md, BUILD.md
scripts/        inspection and setup helpers (see below)
tools/          bt-tool.swift, a small IOBluetooth CLI
```

`scripts/`:

| Script | Purpose |
|---|---|
| `verify-nvram-fix.sh` | confirm the NVRAM fix took effect after a reboot |
| `nvram-fix-config.py` | apply the Bluetooth NVRAM fix to a `config.plist` |
| `airdrop-config.py` | apply the AirDrop/AWDL changes to a `config.plist` |
| `stage-airdrop-efi.sh` | stage ForbiddenItlwm on a USB ESP (backup, kexts, config, validate) |
| `inspect-internal-config.py` | summarise the internal EFI's kexts and NVRAM |
| `inspect-usb-config.py` | same, for a mounted USB EFI |
| `internal-efi-phase1.sh` | mount and back up the internal ESP (needs root) |
| `stage-test-efi.sh` | copy kexts onto a USB ESP, with a backup and safety checks |
| `inspect-efis.sh` | list kexts and NVRAM on all mounted EFIs |
| `collect-bt-logs.sh` | gather kernel and `bluetoothd` logs after a boot |
| `post-boot-check.sh` | quick post-boot Bluetooth state dump |
| `diag-read.sh` | dump IORegistry `diag_*` keys from the instrumented kext |
| `mount-usb-efi.sh` | repair and mount the USB ESP (needs root) |

## Building

`build.sh` builds both kexts with clang only (Command Line Tools, no full
Xcode). It needs three source trees beside it: `upstream/` (the
IntelBluetoothFirmware source), `MacKernelSDK/` and `Lilu/`. `bootstrap.sh`
clones them at the pinned commits:

```sh
./bootstrap.sh
./build.sh
```

This produces `kexts/IntelBluetoothFirmware.kext` and
`kexts/IntelBTPatcher.kext`. See [docs/BUILD.md](docs/BUILD.md) for the
`kmod_info` detail that a clang-only build has to reproduce, and why OpenCore
otherwise rejects the kexts.

## Tooling

`tools/bt-tool.swift` is a small IOBluetooth command-line tool:

```sh
swiftc -O -framework IOBluetooth -o bt-tool tools/bt-tool.swift

./bt-tool list             # paired devices
./bt-tool scan 12          # inquiry (put the target in pairing mode first)
./bt-tool pair <addr>      # pair, e.g. 97-51-b6-50-5b-1d
./bt-tool connect <addr>   # open an ACL connection
./bt-tool info <addr>
```

## Reverting

- NVRAM: `nvram -d 7C436110-AB2A-4BBB-A880-FE41995C9F82:bluetoothExternalDongleFailed`
  and `…:bluetoothInternalControllerInfo`, and remove the corresponding entries
  from `NVRAM → Add` and `NVRAM → Delete`.
- Kexts: put the original `IntelBluetoothFirmware.kext` / `IntelBTPatcher.kext`
  back and keep a backup of the whole EFI.
- AirDrop: see the uninstall steps at the end of
  [docs/AIRDROP.md](docs/AIRDROP.md).

## Credits and license

The kexts and `build.sh` are derived from
[OpenIntelWireless/IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware)
(GPL-3.0), with build dependencies
[acidanthera/MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) and
[acidanthera/Lilu](https://github.com/acidanthera/Lilu). The AirDrop procedure
uses [retropineaple/ForbiddenItlwm](https://github.com/retropineaple/ForbiddenItlwm)
(GPL-2.0). See [CREDITS.md](CREDITS.md). This repository is GPL-3.0; see
[LICENSE](LICENSE).
