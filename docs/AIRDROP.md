# Enabling AirDrop (AWDL) with ForbiddenItlwm

AirDrop, Handoff and Continuity need AWDL, which `AirportItlwm` does not
implement. [retropineaple/ForbiddenItlwm](https://github.com/retropineaple/ForbiddenItlwm)
is a fork of the Intel Wi-Fi driver that adds an AWDL implementation, plus a
companion `BTLEAdvFixup.kext` that lets `bluetoothd` start LE advertising.
Together they enable AirDrop on the AX200 under macOS Sequoia.

Do all of this on a **USB stick's** EFI, never the internal one, so the machine
stays bootable if something is wrong.

## Verified configuration

On the machine this repository documents (Intel AX200, macOS 15.8.3 build
24H241, OpenCore 1.0.8), booting the staged USB EFI produced:

- `ForbiddenItlwm` 0.5.4 and `BTLEAdvFixup` 0.9.1 loaded; `AirportItlwm` and
  `IntelBTPatcher` not loaded.
- `ifconfig -l` includes `awdl0`, and `system_profiler SPAirPortDataType`
  reports `AirDrop: Supported`.
- `ioreg` shows:

  ```
  "ItlwmAWDLBuildCheck"       = "verified"
  "ItlwmAWDLInterfaceBuild"   = "forbidden-0.5.4-beta.2-sequoia"
  "ITLAWDLCoexAdded"          = Yes
  "ITLAWDLCoexChannel"        = 149
  "ITLAWDLCoexCountryLearned" = Yes
  ```

- `sharingd` advertises `AirDropUsable`, and `bluetoothd` sees nearby devices
  over BLE (so `BTLEAdvFixup` is active).

`scripts/airdrop-check.sh` prints all of the above after a boot.

## Requirements

- macOS Sequoia 15.8.x (this was verified against 15.8.3, build 24H241).
- The **Sequoia** builds of both kexts. A kext built for another macOS version
  refuses to start, and `BTLEAdvFixup`'s patches will not match.
- `IntelBTPatcher.kext` disabled (see below). This is mandatory.
- Revert OpenCore Legacy Patcher "Modern Wireless" root patches if present,
  and remove any `Kernel → Block` entry for `com.apple.iokit.IOSkywalkFamily`
  or injected `IOSkywalkFamily.kext` / `IO80211FamilyLegacy.kext`.

Reference versions used here:

| Kext | Version | Source |
|---|---|---|
| `ForbiddenItlwm.kext` | 0.5.4-beta.2 (Sequoia) | release `v0.5.4-beta.2` |
| `BTLEAdvFixup.kext` | 0.9.1 (Sequoia) | release `v0.5.4-beta.2` |
| `Lilu.kext` | 1.7.2 | acidanthera/Lilu |
| `IntelBluetoothFirmware.kext` | 2.5.1 | OpenIntelWireless |
| `BlueToolFixup.kext` | 2.7.3 | acidanthera/BrcmPatchRAM |

## Download

From `https://github.com/retropineaple/ForbiddenItlwm/releases/tag/v0.5.4-beta.2`:

```sh
curl -LO https://github.com/retropineaple/ForbiddenItlwm/releases/download/v0.5.4-beta.2/ForbiddenItlwm-0.5.4-beta.2-Sequoia.zip
curl -LO https://github.com/retropineaple/ForbiddenItlwm/releases/download/v0.5.4-beta.2/BTLEAdvFixup-0.9.1-Sequoia.zip

shasum -a 256 *.zip
# 82d791b52aa05715d146e326cab08706d064fb2e9f9a82171e298d9fca42a54a  ForbiddenItlwm-0.5.4-beta.2-Sequoia.zip
# 54021a179519f12df3db6930b1f5cc35031ec4c0fc32cdad36cfab5df0e18de2  BTLEAdvFixup-0.9.1-Sequoia.zip
```

Each zip contains a `.kext` bundle. Unzip them and copy the bundles into the
stick's `EFI/OC/Kexts`.

## Automated setup

`scripts/stage-airdrop-efi.sh` performs the OpenCore changes below in one step.
It backs up the whole EFI first, refuses to touch the internal ESP, and
validates the result:

```sh
mkdir -p airdrop
unzip -o ForbiddenItlwm-0.5.4-beta.2-Sequoia.zip -d airdrop
unzip -o BTLEAdvFixup-0.9.1-Sequoia.zip -d airdrop
sudo scripts/stage-airdrop-efi.sh /Volumes/MACOSUSB
```

It uses `scripts/nvram-fix-config.py` (Bluetooth NVRAM fix) and
`scripts/airdrop-config.py` (AWDL changes). The manual steps follow, for
reference.

## OpenCore changes (on the USB stick)

Mount the stick's ESP. On this install that needs root:

```sh
sudo diskutil mount diskNs1      # diskNs1 is the stick's EFI partition
```

### 1. Kexts

- Remove `AirportItlwm.kext` (and `itlwm.kext` if present).
- Copy in `ForbiddenItlwm.kext` and `BTLEAdvFixup.kext`.

### 2. `Kernel → Add`

Keep this order so each kext loads after its dependency:

| Order | BundlePath | ExecutablePath | MinKernel | Notes |
|---|---|---|---|---|
| 1 | `Lilu.kext` | `Contents/MacOS/Lilu` | | |
| 2 | `IntelBluetoothFirmware.kext` | `Contents/MacOS/IntelBluetoothFirmware` | | |
| 3 | `BlueToolFixup.kext` | `Contents/MacOS/BlueToolFixup` | `21.0.0` | |
| 4 | `BTLEAdvFixup.kext` | `Contents/MacOS/BTLEAdvFixup` | `24.0.0` | MaxKernel `24.99.99` |
| 5 | `ForbiddenItlwm.kext` | `Contents/MacOS/ForbiddenItlwm` | `24.0.0` | MaxKernel `24.99.99`; replaces `AirportItlwm.kext` |

Set `IntelBTPatcher.kext` to `Enabled = false`. It and `BTLEAdvFixup` hook the
same function, and Lilu panics when two plugins do. `BTLEAdvFixup` replaces it.
Make sure no `AirportItlwm.kext` or `itlwm.kext` entry is still enabled.

### 3. Boot arguments

Add these to `boot-args` under
`NVRAM → Add → 7C436110-AB2A-4BBB-A880-FE41995C9F82`, keeping your existing
arguments. They go on one line:

```
-btleadv -itlawdlcoexprobe -itlawdliface -itlawdlnativeup -itlawdlcoexrx -itlawdlcoextx -itlawdlcoexmulti -itlawdlcoexdata -itlawdlmitx -itlawdlelicit -itlawdlcaps -itlawdlsvcmerge -itlawdlawsync itlawdlintcoal=4 -itlawdlcoexbatx -itlawdlcoexpeerpause -itlawdlcoexbatrace itlawdltxqueue=4096
```

`boot-args` must also be listed under `NVRAM → Delete` for the same GUID, or
OpenCore will not overwrite it.

### 4. Validate

```sh
plutil -lint EFI/OC/config.plist
ocvalidate EFI/OC/config.plist
```

## First boot

1. Boot the stick from the OpenCore picker.
2. Join your normal Wi-Fi network.
3. Wait a minute, then confirm the driver and its AWDL listener are running:

   ```sh
   ioreg -l -w0 | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|CountryLearned)"'
   ```

   Expect `Added` Yes, `Channel` 149 (or 44 in some regions) and
   `CountryLearned` Yes. `Channel 6` means the firmware did not open 149 or 44;
   that build keeps AirDrop off.
4. Turn on AirDrop on both devices. "Contacts Only" needs a shared Apple
   Account or known contacts; otherwise use "Everyone for 10 Minutes".
5. Send a file in both directions.

## Uninstalling

1. Remove `ForbiddenItlwm.kext` and `BTLEAdvFixup.kext`, and their
   `Kernel → Add` entries.
2. Put `AirportItlwm.kext` back and re-enable its entry.
3. Remove the `-itlawdl*`, `itlawdl*` and `-btleadv` boot flags.
4. Reboot.

The driver writes nothing to disk; `BTLEAdvFixup` patches `bluetoothd` in
memory only.
