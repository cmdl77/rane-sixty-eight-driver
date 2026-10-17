import Foundation
import IOKit
import IOKit.hid

print("=== Starting 10-Second Continuous BPM 120 Sync Stream ===")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first else {
    print("❌ Rane Sixty-Eight HID device not found!")
    exit(1)
}

func sendRaw(_ bytes: [UInt8]) {
    var pkt = [UInt8](repeating: 0, count: 64)
    for i in 0..<min(bytes.count, 64) { pkt[i] = bytes[i] }
    IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
}

// 1. Initial Handshake: Report 0x36
sendRaw([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
usleep(10000)

// 2. Report 0x42: Serato FlexFX Active on Deck 1 (0x80)
var seq: UInt32 = 1
let startTime = Date().timeIntervalSince1970

// Target BPM: 120.0 BPM
// In 120 BPM:
// Period = 60000 / 120 = 500 ms (0x0001F4)
// Or BPM * 100 = 12000 = 0x002EE0
// Or BPM direct = 120 = 0x000078

print("Streaming BPM 120 to mixer for 10 seconds (Look at LCD now)...")

var timerCounter = 0
while Date().timeIntervalSince1970 - startTime < 10.0 {
    seq += 1
    let s0 = UInt8((seq >> 24) & 0xFF)
    let s1 = UInt8((seq >> 16) & 0xFF)
    let s2 = UInt8((seq >> 8) & 0xFF)
    let s3 = UInt8(seq & 0xFF)
    
    // Send Report 0x45 (Heartbeat keepalive) every 10 cycles (~500ms)
    if timerCounter % 10 == 0 {
        sendRaw([0x45, s0, s1, s2, s3, 0x00, 0x01])
    }
    
    // Send Report 0x42 (FlexFX Deck 1 bitmask 0x80)
    sendRaw([0x42, s0, s1, s2, s3, 0x01, 0x01, 0x80])
    
    // Send Report 0x4A (Period = 500 ms -> 0x0001F4)
    sendRaw([0x4A, s0, s1, s2, s3, 0x00, 0x01, 0xF4])
    
    timerCounter += 1
    usleep(50000) // 20 Hz stream (every 50 ms)
}

print("✅ Finished 10-second stream.")
