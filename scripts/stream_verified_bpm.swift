import Foundation
import IOKit
import IOKit.hid

print("╔════════════════════════════════════════════════════════════════╗")
print("║     RANE SIXTY-EIGHT VERIFIED BPM STREAM (15 SEKUNDEN)         ║")
print("╚════════════════════════════════════════════════════════════════╝")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first else {
    print("❌ Mixer nicht gefunden!")
    exit(1)
}

func sendRaw(_ bytes: [UInt8]) {
    var pkt = [UInt8](repeating: 0, count: 64)
    for i in 0..<min(bytes.count, 64) { pkt[i] = bytes[i] }
    IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
}

// 1. Host Connect (Report 0x83)
sendRaw([0x83, 0x01])
usleep(15000)

// 2. Hardware Security Unlock (Opcode 0x18 mit echtem ROM-Key: 02 43 88 38 03 6A 01)
let unlockPkt: [UInt8] = [
    0x41, 0x0B, 0xF0, 0x17, 0x18,
    0x02, 0x43, 0x88, 0x38, 0x03, 0x6A, 0x01,
    0xF7
]
sendRaw(unlockPkt)
usleep(25000)

// 3. Set BPM 120.00 auf LCD via Opcode 0x53
// 120.00 * 100 = 12000 = 0x2EE0 (Hi: 0x2E, Lo: 0xE0)
let bpm120Pkt: [UInt8] = [
    0x41, 0x09, 0xF0, 0x17, 0x53,
    0x02, 0x01, 0x2E, 0xE0, 0x01,
    0xF7
]

// Also variations for byte 3 (mode 1 or mode 2)
let bpm120Mode1: [UInt8] = [
    0x41, 0x09, 0xF0, 0x17, 0x53,
    0x01, 0x01, 0x2E, 0xE0, 0x01,
    0xF7
]

let startTime = Date().timeIntervalSince1970
var count = 0

print("Streaming BPM 120.00 & Heartbeat für 15 Sekunden...")

while Date().timeIntervalSince1970 - startTime < 15.0 {
    count += 1
    
    // Heartbeat Report 0x45
    if count % 4 == 0 {
        sendRaw([0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
    }
    
    // Opcode 0x53 BPM
    sendRaw(bpm120Pkt)
    if count % 2 == 0 {
        sendRaw(bpm120Mode1)
    }
    
    usleep(50000) // 20 Hz
}

print("✅ Stream beendet.")
