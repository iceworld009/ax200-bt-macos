import plistlib, sys

# Usage: inspect-usb-config.py [path/to/config.plist]
cfg = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/MACOSUSB/EFI/OC/config.plist"
with open(cfg, "rb") as f:
    d = plistlib.load(f)

print("== Kernel.Add ==")
for k in d.get("Kernel", {}).get("Add", []):
    bp = k.get("BundlePath", "")
    print(f"  {bp:34s} Enabled={str(k.get('Enabled')):5s} Min={k.get('MinKernel',''):8s} Max={k.get('MaxKernel',''):8s} Arch={k.get('Arch','')}")

print()
guid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
nv = d.get("NVRAM", {})
print("== NVRAM.Add[bluetooth GUID] ==")
for key, val in nv.get("Add", {}).get(guid, {}).items():
    print(f"  {key} = <{val.hex()}>" if isinstance(val, bytes) else f"  {key} = {val!r}")
print("== NVRAM.Add boot-args ==")
print("  ", repr(nv.get("Add", {}).get(guid, {}).get("boot-args")))
print("== NVRAM.Delete[bluetooth GUID] ==")
print("  ", nv.get("Delete", {}).get(guid))
print()
print("== Kernel.Block ==")
for b in d.get("Kernel", {}).get("Block", []):
    print("  ", b.get("Identifier"), "Enabled=", b.get("Enabled"))
