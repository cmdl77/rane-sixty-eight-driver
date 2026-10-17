import Foundation
import IOKit
import IOKit.hid

print("╔════════════════════════════════════════════════════════════════╗")
print("║     RANE SIXTY-EIGHT POWER-CYCLE WATCHDOG & BPM SYNC           ║")
print("╚════════════════════════════════════════════════════════════════╝")
print("\n👉 BITTE SCHALTE DEN MIXER JETZT AUS UND WIEDER EIN!")
print("   Ich warte, bis die USB-Verbindung neu aufgebaut ist...\n")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

func getMixerDevice() -> IOHIDDevice? {
    if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = deviceSet.first {
        return device
    }
    return nil
}

// 1. Warte, bis der Mixer ausgeschaltet wird (oder falls bereits aus, fahre direkt fort)
var initialDevice = getMixerDevice()
if initialDevice != nil {
    print("⏳ Mixer ist aktuell noch AN. Bitte jetzt am Schalter AUSSCHALTEN...")
    while getMixerDevice() != nil {
        usleep(200000) // 200ms
    }
    print("🔴 Mixer wurde AUSGESCHALTET! (USB getrennt)")
} else {
    print("🔴 Mixer ist aktuell AUS.")
}

// 2. Warte, bis der Mixer wieder eingeschaltet wird
print("⏳ Warte darauf, dass du den Mixer wieder EINSCHALTEST...")
var newDevice: IOHIDDevice? = nil
while newDevice == nil {
    usleep(200000)
    newDevice = getMixerDevice()
}

print("🟢 Mixer wurde EINGESCHALTET! (USB wieder verbunden)")
print("⏳ Warte 2 Sekunden auf DSP-Bootloader und interne Initialisierung...")
sleep(2)

func sendRaw(_ device: IOHIDDevice, _ bytes: [UInt8], label: String = "") {
    var pkt = [UInt8](repeating: 0, count: 64)
    for i in 0..<min(bytes.count, 64) { pkt[i] = bytes[i] }
    let ret = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
    if ret == kIOReturnSuccess {
        print("✅ Gesendet [\(label)]: \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
    } else {
        print("❌ Fehler bei [\(label)]: 0x\(String(format: "%08X", ret))")
    }
}

guard let dev = getMixerDevice() else {
    print("❌ Fehler: Gerät verloren!")
    exit(1)
}

print("\n🚀 Sende verifizierten Serato-Handshake & BPM 120.00...")

// 1. Host Connect (Report 0x83)
sendRaw(dev, [0x83, 0x01], label: "Report 0x83 (Host Connect)")
usleep(20000)

// 2. Software Mode Active (Report 0x82)
sendRaw(dev, [0x82, 0x01], label: "Report 0x82 (Software Mode)")
usleep(20000)

// 3. Hardware Security Unlock (Opcode 0x18 mit echtem ROM-Key: 02 43 88 38 03 6A 01)
let unlockPkt: [UInt8] = [
    0x41, 0x0B, 0xF0, 0x17, 0x18,
    0x02, 0x43, 0x88, 0x38, 0x03, 0x6A, 0x01,
    0xF7
]
sendRaw(dev, unlockPkt, label: "Opcode 0x18 (Hardware Unlock)")
usleep(30000)

// 4. Set BPM 120.00 auf LCD via Opcode 0x53
// 120.00 * 100 = 12000 = 0x2EE0 (Hi: 0x2E, Lo: 0xE0)
let bpm120Pkt: [UInt8] = [
    0x41, 0x09, 0xF0, 0x17, 0x53,
    0x02, 0x01, 0x2E, 0xE0, 0x01,
    0xF7
]
sendRaw(dev, bpm120Pkt, label: "Opcode 0x53 (BPM 120.00)")

// 5. Halte den Stream für 30 Sekunden aktiv mit Heartbeat
print("\n⏱️ Halte den BPM-Stream für 30 Sekunden aktiv...")
let startTime = Date().timeIntervalSince1970
var tick = 0

while Date().timeIntervalSince1970 - startTime < 30.0 {
    tick += 1
    if tick % 5 == 0 {
        // Heartbeat alle 250ms
        sendRaw(dev, [0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01], label: "Heartbeat")
    }
    if tick % 10 == 0 {
        // BPM Refresh jede halbe Sekunde
        sendRaw(dev, bpm120Pkt, label: "Opcode 0x53 Refresh")
    }
    usleep(50000)
}

print("\n✅ Fertig! Bitte Mixer-Display prüfen.")
