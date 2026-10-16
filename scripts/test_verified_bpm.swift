import Foundation
import IOKit
import IOKit.hid

let targetBpm: Double = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 66.0) : 66.0
let bpmInt = UInt16(round(targetBpm * 100.0)) // z.B. 6600 = 0x19C8 für 66.00 BPM
let hiByte = UInt8((bpmInt >> 8) & 0xFF)
let loByte = UInt8(bpmInt & 0xFF)
let beatIntervalUs = UInt32(round((60.0 / targetBpm) * 1_000_000.0))
let expectedTimeMs = Int(round(60000.0 / targetBpm))

print("╔════════════════════════════════════════════════════════════════╗")
print("║   RANE SIXTY-EIGHT VERIFIED SERATO SYNC (\(String(format: "%6.2f", targetBpm)) BPM LIVE)      ║")
print("╚════════════════════════════════════════════════════════════════╝")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first else {
    print("❌ Mixer nicht gefunden!")
    exit(1)
}

var seqNum: UInt32 = 1

func sendSysEx(_ sysex: [UInt8], label: String = "") {
    var pkt = [UInt8](repeating: 0, count: 64)
    pkt[0] = 0x41
    pkt[1] = UInt8((seqNum >> 24) & 0xFF)
    pkt[2] = UInt8((seqNum >> 16) & 0xFF)
    pkt[3] = UInt8((seqNum >> 8) & 0xFF)
    pkt[4] = UInt8(seqNum & 0xFF)
    seqNum += 1
    
    let count = min(sysex.count, 58)
    pkt[5] = UInt8(count)
    for i in 0..<count {
        pkt[6 + i] = sysex[i]
    }
    
    let ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
    if !label.isEmpty {
        print("✅ [\(label)] kr=0x\(String(format: "%08X", ret))")
    }
}

// 1. Control Point auf Port A setzen (Opcode 0x52)
sendSysEx([0xF0, 0x17, 0x52, 0x00, 0xF7], label: "Opcode 0x52 (Control Point Port A)")
usleep(20000)

// 2. Hardware Unlock (Opcode 0x18)
sendSysEx([0xF0, 0x17, 0x18, 0x02, 0x43, 0x88, 0x38, 0x03, 0x6A, 0x01, 0xF7], label: "Opcode 0x18 (Unlock)")
usleep(20000)

// 3. Sende Ziel-BPM im 14-Byte Nibble-Format für ca. 10 Sekunden
let totalBeats = max(8, Int(round(10.0 / (60.0 / targetBpm))))
print("🎵 Starte \(String(format: "%.2f", targetBpm)) BPM Beat-Sync Puls (\(totalBeats) Beats, Δt = \(expectedTimeMs) ms)...")

for beat in 1...totalBeats {
    let sysex14: [UInt8] = [
        0xF0, 0x17, 0x53,
        0x00, 0x02,                         // Mode = 2 (Serato Sync)
        0x00, 0x01,                         // Beat Sync = 1
        (hiByte >> 4) & 0x0F, hiByte & 0x0F, // BPM High Byte Nibbles
        (loByte >> 4) & 0x0F, loByte & 0x0F, // BPM Low Byte Nibbles
        0x00, 0x01,                         // Asterisk Blink Trigger = 1
        0xF7
    ]
    sendSysEx(sysex14, label: beat == 1 ? "Beat 1 (\(String(format: "%.2f", targetBpm)) BPM *)" : "")
    usleep(beatIntervalUs)
}

print("✅ Fertig! Display sollte jetzt BPM: \(Int(round(targetBpm))) * 1/1 und TIME: \(expectedTimeMs)ms zeigen.")
