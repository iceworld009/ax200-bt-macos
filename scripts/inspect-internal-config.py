import plistlib, sys

# Usage: inspect-internal-config.py [path/to/config.plist]
cfg = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/NO NAME/EFI/OC/config.plist"
with open(cfg, "rb") as f:
    d = plistlib.load(f)

print("== Kernel.Add (enabled) ==")
for k in d.get("Kernel", {}).get("Add", []):
    bp = k.get("BundlePath", "")
    en = k.get("Enabled")
    mk = k.get("MinKernel", "")
    xk = k.get("MaxKernel", "")
    mark = "  <-- BT/WIFI" if any(s in bp for s in ("Intel", "BlueTool", "AirportItlwm")) else ""
    print(f"  {bp:34s} Enabled={str(en):5s} Min={mk:6s} Max={xk:6s}{mark}")

print()
print("== NVRAM Add (bluetooth GUID) ==")
nv = d.get("NVRAM", {})
guid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
add = nv.get("Add", {}).get(guid, {})
for key, val in add.items():
    if isinstance(val, bytes):
        print(f"  {key} = <{val.hex()}> ({len(val)} bytes)")
    else:
        print(f"  {key} = {val!r}")
print("== NVRAM Delete (bluetooth GUID) ==")
print("  ", nv.get("Delete", {}).get(guid))

print()
print("== Misc.Boot ==")
for k in ("Timeout", "ShowPicker", "TakeoffDelay", "PickerMode", "HideAuxiliary"):
    print(f"  {k} = {d.get('Misc',{}).get('Boot',{}).get(k)}")
print("== Misc.Security ==")
for k in ("SecureBootModel", "DmgLoading", "Vault", "AllowNvramReset", "ExposeSensitiveData"):
    print(f"  {k} = {d.get('Misc',{}).get('Security',{}).get(k)}")
