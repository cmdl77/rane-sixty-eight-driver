import Foundation
import IOKit
import IOKit.hid

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first else {
    print("❌ Rane Sixty-Eight HID device not found!")
    exit(1)
}

func sendPkt(_ bytes: [UInt8], desc: String) {
    var pkt = [UInt8](repeating: 0, count: 64)
    for i in 0..<min(bytes.count, 64) { pkt[i] = bytes[i] }
    // NOTE: Always pass reportID: 0 so IOHIDFamily doesn't prepend a duplicate byte!
    let kr = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
    print("➡️ [\(desc)] (kr: 0x\(String(format: "%08X", kr)))")
}

// 1. Report 0x36: Init HID
sendPkt([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x01], desc: "Init 0x36")
usleep(10000)

// 2. Report 0x42: Set FlexFX Deck 1 active
sendPkt([0x42, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x80], desc: "Report 0x42 Deck 1 (0x80)")
usleep(10000)

// 3. Report 0x4A variations
sendPkt([0x4A, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x58], desc: "Report 0x4A Period 600ms")
usleep(10000)
sendPkt([0x4A, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x64], desc: "Report 0x4A BPM 100")
usleep(10000)
sendPkt([0x4A, 0x00, 0x00, 0x00, 0x04, 0x00, 0x27, 0x10], desc: "Report 0x4A BPM*100")

print("Fertig!")
