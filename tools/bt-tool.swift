// bt-tool.swift — minimal IOBluetooth CLI for pairing classic devices.
// Usage:
//   bt-tool list                 list paired devices
//   bt-tool scan [seconds]       inquiry, print discovered devices
//   bt-tool pair <addr>          pair with a device (address like aa-bb-cc-dd-ee-ff)
//   bt-tool connect <addr>       open an ACL connection
//   bt-tool info <addr>          print details for one device
import Foundation
import IOBluetooth

// Keep the inquiry + delegate alive for the whole process: IOBluetoothDeviceInquiry
// crashes in -dealloc if its delegate is gone, and unbuffered stdout so output
// survives an abnormal exit.
setbuf(stdout, nil)
var gDelegate: Inq?
var gInquiry: IOBluetoothDeviceInquiry?

func fmt(_ d: IOBluetoothDevice) -> String {
    let addr = d.addressString ?? "?"
    let name = d.nameOrAddress ?? "(null)"
    let conn = d.isConnected() ? "connected" : "not-connected"
    let paired = d.isPaired() ? "paired" : "unpaired"
    return "\(addr)  \(paired)  \(conn)  \(name)"
}

class Inq: NSObject, IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let d = device else { return }
        print("FOUND  \(fmt(d))  rssi=\(d.rawRSSI())")
    }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        print("INQUIRY COMPLETE  error=\(error)  aborted=\(aborted)")
    }
}

func device(_ s: String) -> IOBluetoothDevice? {
    return IOBluetoothDevice(addressString: s)
}

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "list"

switch cmd {
case "list":
    let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    if paired.isEmpty { print("(no paired devices)") }
    for d in paired { print(fmt(d)) }

case "scan":
    let secs = args.count > 2 ? (Double(args[2]) ?? 10) : 10
    let delegate = Inq()
    gDelegate = delegate
    guard let inquiry = IOBluetoothDeviceInquiry(delegate: delegate) else {
        print("ERROR: could not create inquiry"); exit(2)
    }
    gInquiry = inquiry
    inquiry.inquiryLength = UInt8(max(1, min(48, Int(secs))))
    inquiry.updateNewDeviceNames = true
    let r = inquiry.start()
    print("inquiry.start() -> \(r); scanning \(Int(secs))s ...")
    RunLoop.current.run(until: Date().addingTimeInterval(secs + 3))
    inquiry.stop()
    print("done")

case "pair":
    guard args.count > 2, let d = device(args[2]) else {
        print("usage: bt-tool pair <addr>"); exit(2)
    }
    print("pairing \(fmt(d)) ...")
    guard let cls = NSClassFromString("IOBluetoothDevicePair") else {
        print("ERROR: IOBluetoothDevicePair class not found"); exit(2)
    }
    let pairer = (cls as! NSObject.Type).init()
    _ = pairer.perform(NSSelectorFromString("setDevice:"), with: d)
    typealias StartFn = @convention(c) (AnyObject, Selector) -> Int32
    let sel = NSSelectorFromString("start")
    let startFn = unsafeBitCast(pairer.method(for: sel), to: StartFn.self)
    let r = startFn(pairer, sel)
    print("pairer.start() -> \(r); waiting 15s ...")
    RunLoop.current.run(until: Date().addingTimeInterval(15))
    print("paired=\(d.isPaired()) connected=\(d.isConnected())")
    if d.isPaired() {
        let rc = d.openConnection()
        print("openConnection() -> \(rc)")
    }

case "connect":
    guard args.count > 2, let d = device(args[2]) else {
        print("usage: bt-tool connect <addr>"); exit(2)
    }
    let r = d.openConnection()
    print("openConnection(\(fmt(d))) -> \(r)  connected=\(d.isConnected())")

case "info":
    guard args.count > 2, let d = device(args[2]) else {
        print("usage: bt-tool info <addr>"); exit(2)
    }
    print("address   : \(d.addressString ?? "?")")
    print("name      : \(d.nameOrAddress ?? "(null)")")
    print("paired    : \(d.isPaired())")
    print("connected : \(d.isConnected())")
    print("class     : 0x\(String(d.classOfDevice, radix: 16))")

default:
    print("unknown command: \(cmd)")
    exit(2)
}
