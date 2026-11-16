# Credits

This repository is a record of one machine's configuration. It builds on work
by others:

- [OpenIntelWireless/IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware)
  (GPL-3.0) — the Bluetooth driver and patcher. The kexts in `kexts/` and
  `build.sh` are derived from it. Upstream issue
  [#513](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/issues/513)
  describes the NVRAM problem this repository works around.
- [acidanthera/Lilu](https://github.com/acidanthera/Lilu) (BSD-3-Clause) —
  kernel patching framework; build dependency and runtime dependency.
- [acidanthera/MacKernelSDK](https://github.com/acidanthera/MacKernelSDK)
  — kernel headers used by the build.
- [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM)
  (GPL-3.0) — provides `BlueToolFixup.kext`.
- [acidanthera/OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)
  (BSD-3-Clause) — bootloader; `ocvalidate` is used to check the config.
- [retropineaple/ForbiddenItlwm](https://github.com/retropineaple/ForbiddenItlwm)
  (GPL-2.0) — the Intel Wi-Fi driver fork that adds AWDL, and `BTLEAdvFixup`.
  Not included here; `docs/AIRDROP.md` links to the release and lists the
  checksums.

The bundled kexts are GPL-3.0. See [LICENSE](LICENSE).
