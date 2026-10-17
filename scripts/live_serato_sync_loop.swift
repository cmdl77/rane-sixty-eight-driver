import Foundation
import IOKit
import IOKit.hid

print("╔════════════════════════════════════════════════════════════════╗")
print("║  RANE SIXTY-EIGHT LIVE SERATO SYNC STREAM (45 SEKUNDEN)        ║")
print("╚════════════════════════════════════════════════════════════════╝")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first else {
    print("❌ Mixer nicht gefunden!")
    exit(1)
}

var inReportBuf = [UInt8](repeating: 0, count: 64)
let callback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    if bytes[0] == 0xFE || bytes[0] == 0x41 || bytes[0] == 0x40 {
        // Filtere uninteressante MIDI CC Rauschdaten
        let filtered = bytes.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        if bytes.contains(0x53) || bytes.contains(0x18) {
            print("   📥 MIXER ANTWORT: \(filtered)")
        }
    }
}
IOHIDDeviceRegisterInputReportCallback(device, &inReportBuf, 64, callback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

func sendRaw(_ bytes: [UInt8], label: String = "") {
    var pkt = [UInt8](repeating: 0, count: 64)
    for i in 0..<min(bytes.count, 64) { pkt[i] = bytes[i] }
    _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
}

// 1. Host Connect (Report 0x83)
sendRaw([0x83, 0x01])
RunLoop.current.run(until: Date().addingTimeInterval(0.05))

// 2. Hardware Security Unlock (Opcode 0x18 mit verifiziertem ROM-Key)
let unlockPkt: [UInt8] = [
    0x41, 0x0B, 0xF0, 0x17, 0x18,
    0x02, 0x43, 0x88, 0x38, 0x03, 0x6A, 0x01,
    0xF7
]
sendRaw(unlockPkt)
print("🔑 Hardware Unlock gesendet...")
RunLoop.current.run(until: Date().addingTimeInterval(0.1))

// 3. Kontinuierlicher Serato BPM Sync Stream: 128.00 BPM (12800 = 0x3200)
let targetBpm: Double = 128.00
let bpmInt = UInt16(targetBpm * 100) // 12800 = 0x3200
let bHi = UInt8((bpmInt >> 8) & 0xFF)
let bLo = UInt8(bpmInt & 0xFF)
let beatInterval = 60.0 / targetBpm // 0.46875s (Viertelnote)

print("🎵 Sende BPM \(targetBpm) Sync-Stream für 45 Sekunden...")
print("👀 SCHAU JETZT AUF DAS FLEX-FX DISPLAY DES SIXTY-EIGHT!\n")

let totalBeats = Int(45.0 / beatInterval)

for beat in 1...totalBeats {
    let remainingSec = Int(Double(totalBeats - beat) * beatInterval)
    
    // Beat Pulse: Byte 4 = 0x01 (Beat Event), Byte 7 = 0x01 (Stern '*' an)
    let syncPktOn: [UInt8] = [
        0x41, 0x09, 0xF0, 0x17, 0x53,
        0x02, 0x01, bHi, bLo, 0x01,
        0xF7
    ]
    sendRaw(syncPktOn)
    
    if beat % 4 == 1 {
        print("▶️ Beat \(beat)/\(totalBeats) | BPM: \(targetBpm) [*] | Noch \(remainingSec)s aktiv...")
    }
    
    // 120ms Stern anlassen
    RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    
    // Stern wieder aus (Byte 7 = 0x00)
    let syncPktOff: [UInt8] = [
        0x41, 0x09, 0xF0, 0x17, 0x53,
        0x02, 0x00, bHi, bLo, 0x00,
        0xF7
    ]
    sendRaw(syncPktOff)
    
    // Restliche Taktzeit warten
    RunLoop.current.run(until: Date().addingTimeInterval(beatInterval - 0.12))
}

print("\n✅ Stream beendet.")
