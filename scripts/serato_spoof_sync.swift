import Foundation
import IOKit
import IOKit.hid

print("╔════════════════════════════════════════════════════════════════╗")
print("║     RANE SIXTY-EIGHT 60-SEKUNDEN SERATO SPOOF & BPM SYNC       ║")
print("╚════════════════════════════════════════════════════════════════╝")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first else {
    print("❌ Rane Sixty-Eight HID device nicht gefunden!")
    exit(1)
}

print("✅ Rane Sixty-Eight USB HID Device verbunden.")

func sendRawPacket(_ bytes: [UInt8], label: String = "") {
    var pkt = [UInt8](repeating: 0, count: 64)
    for i in 0..<min(bytes.count, 64) {
        pkt[i] = bytes[i]
    }
    let ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
    if ret != kIOReturnSuccess {
        print("⚠️ Sendefehler für \(label): 0x\(String(format: "%08X", ret))")
    }
}

// -------------------------------------------------------------
// STAGE 1: Serato Handshake & Hardware Unlock
// -------------------------------------------------------------
print("\n[Phase 1] Sende Serato Handshake...")

// 1. Report 0x83: Host Connected (Port A = 1)
print(" -> Report 0x83 (Host Connected Port A)...")
sendRawPacket([0x83, 0x01], label: "Report 0x83")
usleep(15000)

// 2. Report 0x82: Serato Software Mode Active (DSP Sync Mode)
print(" -> Report 0x82 (DSP Software Mode Active)...")
sendRawPacket([0x82, 0x01], label: "Report 0x82")
usleep(15000)

// 3. Report 0x36: HID Engine Init
print(" -> Report 0x36 (Init Engine)...")
sendRawPacket([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x01], label: "Report 0x36")
usleep(15000)

// 4. Report 0x41 + SysEx Opcode 0x18: Firmware Security Unlock Key
// Magic key from ROM: 03 59 10 14 03 2B 28
let sysexUnlock: [UInt8] = [
    0x41,       // Report ID
    0x0B,       // SysEx Length (11 Bytes: F0 bis F7)
    0xF0, 0x17, // Rane SysEx Header
    0x18,       // Opcode 0x18 (Hardware Unlock)
    0x03, 0x59, 0x10, 0x14, 0x03, 0x2B, 0x28, // 7-Byte Magic Key
    0xF7        // SysEx EOX
]
print(" -> Opcode 0x18 (Firmware Security Unlock)...")
sendRawPacket(sysexUnlock, label: "Opcode 0x18")
usleep(25000)

// 5. Report 0x41 + SysEx Opcode 0x52: Set Control Point to Port A (0x01)
let sysexCtrlPoint: [UInt8] = [
    0x41, 0x05, 0xF0, 0x17, 0x52, 0x01, 0xF7
]
print(" -> Opcode 0x52 (Control Point Port A)...")
sendRawPacket(sysexCtrlPoint, label: "Opcode 0x52")
usleep(25000)

// 6. Report 0x42: Serato FlexFX Deck Assignment (Deck 1 Bitmask = 0x80)
print(" -> Report 0x42 (FlexFX Deck 1 Zuweisung)...")
var r42 = [UInt8](repeating: 0, count: 64)
r42[0] = 0x42
r42[1] = 0x01
r42[2] = 0x01
r42[6] = 0x80 // Deck 1 bitmask
sendRawPacket(r42, label: "Report 0x42")
usleep(25000)

// -------------------------------------------------------------
// STAGE 2: Kontinuierlicher 60-Sekunden Stream (120.0 BPM / 500ms)
// -------------------------------------------------------------
print("\n[Phase 2] Starte 60-Sekunden BPM-Stream (120.0 BPM)...")
print("👀 BITTE JETZT DAS MIXER-DISPLAY BEOBACHTEN:")
print("   - Springt der BPM-Wert auf 120 (oder 120.0)?")
print("   - Ändert sich TIME auf 500 ms?")
print("   - Fängt der Stern (*) neben BPM an zu blinken?")

let targetBpm: Float = 120.0
let periodMs: UInt32 = 500 // 60000 / 120 = 500 ms

// IEEE-754 Float 120.0 = 0x42F00000
let bpmFloatBits = targetBpm.bitPattern
let fb0 = UInt8((bpmFloatBits >> 24) & 0xFF) // 0x42
let fb1 = UInt8((bpmFloatBits >> 16) & 0xFF) // 0xF0
let fb2 = UInt8((bpmFloatBits >> 8) & 0xFF)  // 0x00
let fb3 = UInt8(bpmFloatBits & 0xFF)         // 0x00

// SysEx Opcode 0x09 mit Float-BPM (120.0f)
let sysexBpmFloat: [UInt8] = [
    0x41, 0x08, 0xF0, 0x17, 0x09, fb0, fb1, fb2, fb3, 0xF7
]

// SysEx Opcode 0x09 mit Integer-BPM (120)
let sysexBpmInt: [UInt8] = [
    0x41, 0x06, 0xF0, 0x17, 0x09, 0x00, 0x78, 0xF7
]

// Report 0x4A: Serato Period Stream (500 ms -> 0x0001F4)
let report4A: [UInt8] = [
    0x4A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0xF4
]

// Report 0x45: Serato Heartbeat
let report45: [UInt8] = [
    0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
]

let startTime = Date().timeIntervalSince1970
var tickCount = 0
var lastReportSec = -1

while true {
    let elapsed = Date().timeIntervalSince1970 - startTime
    if elapsed >= 60.0 { break }
    
    tickCount += 1
    let currentSec = Int(elapsed)
    if currentSec != lastReportSec && currentSec % 5 == 0 {
        lastReportSec = currentSec
        let remain = 60 - currentSec
        print("⏱️ [Noch \(remain)s] Stream aktiv (BPM: 120 / Period: 500ms)...")
    }
    
    // Heartbeat alle 200ms (alle 4 Ticks bei 50ms)
    if tickCount % 4 == 0 {
        sendRawPacket(report45, label: "Heartbeat")
    }
    
    // FlexFX Zuweisung alle 500ms (alle 10 Ticks)
    if tickCount % 10 == 0 {
        sendRawPacket(r42, label: "Report 0x42")
    }
    
    // Report 0x4A Period (jeder Tick, 20 Hz)
    sendRawPacket(report4A, label: "Report 0x4A")
    
    // SysEx BPM Float alle 200ms
    if tickCount % 4 == 0 {
        sendRawPacket(sysexBpmFloat, label: "SysEx BPM Float")
    }
    
    // SysEx BPM Int alle 400ms
    if tickCount % 8 == 0 {
        sendRawPacket(sysexBpmInt, label: "SysEx BPM Int")
    }
    
    usleep(50000) // 50ms = 20 Hz
}

print("\n✅ 60-Sekunden Stream beendet.")
