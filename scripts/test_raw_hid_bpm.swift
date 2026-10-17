import Foundation
import IOKit
import IOKit.hid

print("=== Testing Direct HID Reports on Rane Sixty-Eight ===")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [
    kIOHIDVendorIDKey as String: 0x1CC5
]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first else {
    print("❌ Rane Sixty-Eight HID device not found!")
    exit(1)
}

var nameProp = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString)
print("✅ Found Device: \(nameProp ?? "Rane Sixty-Eight" as CFTypeRef)")

func sendReport(_ bytes: [UInt8], desc: String) {
    var pkt = [UInt8](repeating: 0, count: 64)
    for i in 0..<min(bytes.count, 64) {
        pkt[i] = bytes[i]
    }
    let kr = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(pkt[0]), pkt, pkt.count)
    let hex = bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
    print("➡️ [\(desc)] -> kr: 0x\(String(format: "%08X", kr)) [\(hex)...]")
}

// 1. Report 0x36: Init HID Engine
sendReport([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x01], desc: "Report 0x36 Init HID")
usleep(20000)

// 2. Report 0x41 with Exact Firmware Framing: pkt[0]=0x41, pkt[1]=len, pkt[2]=0xF0, pkt[3]=0x17...
// Test Opcode 0x04 (GET_ALL)
sendReport([0x41, 0x04, 0xF0, 0x17, 0x04, 0xF7], desc: "Report 0x41 SysEx 0x04 GET_ALL")
usleep(20000)

// 3. Report 0x42: Serato FlexFX Assignment (Deck 1 active = 0x80)
sendReport([0x42, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x80], desc: "Report 0x42 FlexFX Deck 1 Active (0x80)")
usleep(20000)

// 4. Report 0x4A: Serato Tempo / BPM Packet
// 100 BPM: period in ms = 60000 / 100 = 600 ms = 0x000258
// Or BPM * 100 = 10000 = 0x002710
print("\n--- Sending Report 0x4A variations for BPM 100 ---")

// Variant A: Period 600 ms (0x000258)
sendReport([0x4A, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x58], desc: "Report 0x4A (Period 600 ms = 0x000258)")
usleep(50000)

// Variant B: Direct BPM 100 (0x000064)
sendReport([0x4A, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x64], desc: "Report 0x4A (BPM 100 = 0x000064)")
usleep(50000)

// Variant C: BPM * 100 = 10000 (0x002710)
sendReport([0x4A, 0x00, 0x00, 0x00, 0x03, 0x00, 0x27, 0x10], desc: "Report 0x4A (BPM*100 = 0x002710)")
usleep(50000)

// 5. Opcode 0x18 via Report 0x41 framing:
// F0 17 18 <7 bytes> F7 (Length 11)
// Let's test 100 BPM via SysEx 0x18 framing:
// Byte 0: 0x41
// Byte 1: 0x0B (11 bytes)
// Byte 2: 0xF0
// Byte 3: 0x17
// Byte 4: 0x18 (Opcode DSP FX)
// Bytes 5..11: payload + 0xF7
sendReport([0x41, 0x0B, 0xF0, 0x17, 0x18, 0x01, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0xF7], desc: "Report 0x41 SysEx 0x18 (BPM 100)")

print("\nFertig gesendet! Bitte schau auf das Mixer-Display:")
