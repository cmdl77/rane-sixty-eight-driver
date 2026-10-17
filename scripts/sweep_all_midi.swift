import Foundation
import CoreMIDI

print("==========================================================")
print("  RANE SIXTY-EIGHT FULL MIDI SWEEP (ALL NOTES & ALL CCs)  ")
print("==========================================================")

let numDests = MIDIGetNumberOfDestinations()
var raneDest: MIDIEndpointRef = 0

for i in 0..<numDests {
    let dest = MIDIGetDestination(i)
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(dest, kMIDIPropertyName, &name)
    let destName = (name?.takeRetainedValue() as String?) ?? ""
    if destName.contains("Sixty-Eight") || destName.contains("Rane") {
        raneDest = dest
        break
    }
}

guard raneDest != 0 else {
    print("FEHLER: Rane Sixty-Eight CoreMIDI Destination nicht gefunden!")
    exit(1)
}

print("Verbunden mit Rane Sixty-Eight Destination (ID: \(raneDest))")

var client: MIDIClientRef = 0
MIDIClientCreate("SweepClient" as CFString, nil, nil, &client)

var outPort: MIDIPortRef = 0
MIDIOutputPortCreate(client, "SweepOut" as CFString, &outPort)

func sendMidiPacket(_ bytes: [UInt8]) {
    var packet = MIDIPacket()
    packet.timeStamp = 0
    packet.length = UInt16(bytes.count)
    withUnsafeMutableBytes(of: &packet.data) { ptr in
        for i in 0..<bytes.count { ptr[i] = bytes[i] }
    }
    var list = MIDIPacketList(numPackets: 1, packet: packet)
    MIDISend(outPort, raneDest, &list)
}

print("\n--- PHASE 1: NOTE SWEEP (Noten 0 bis 127 auf allen 16 Kanälen) ---")
print("Schau jetzt auf die Tasten und LEDs des Mixers...")

// 1. Sweep Notes 0..127 across channels 0..15
for note: UInt8 in 0...127 {
    // Note ON (Velocity 127) auf Kanälen 0..15
    for ch: UInt8 in 0...15 {
        sendMidiPacket([0x90 | ch, note, 127])
    }
    usleep(25000) // 25ms leuchten lassen
    
    // Note OFF auf allen Kanälen
    for ch: UInt8 in 0...15 {
        sendMidiPacket([0x80 | ch, note, 0])
    }
    usleep(10000) // 10ms Puffer
    
    if note % 16 == 0 || note == 127 {
        print("  -> Noten-Bereich getestet: \(note) / 127")
    }
}

print("✓ Noten-Sweep abgeschlossen!\n")
usleep(300000)

print("--- PHASE 2: CONTROLLER SWEEP (CC 0 bis 127 auf allen 16 Kanälen) ---")
print("Schau jetzt auf Displays, Pegel, LEDs und Anzeigen...")

// 2. Sweep CC 0..127 across channels 0..15
for cc: UInt8 in 0...127 {
    // CC Wert 127 auf allen Kanälen
    for ch: UInt8 in 0...15 {
        sendMidiPacket([0xB0 | ch, cc, 127])
    }
    usleep(25000) // 25ms Haltezeit
    
    // CC Wert 0 auf allen Kanälen
    for ch: UInt8 in 0...15 {
        sendMidiPacket([0xB0 | ch, cc, 0])
    }
    usleep(10000)
    
    if cc % 16 == 0 || cc == 127 {
        print("  -> CC-Bereich getestet: CC #\(cc) / 127")
    }
}

print("✓ Controller-Sweep abgeschlossen!\n")
usleep(300000)

print("--- PHASE 3: VOLL-FEUERWERK (Alle Noten 0..127 gleichzeitig AN) ---")
for ch: UInt8 in 0...4 { // Kanäle 1..5 (Rane Gruppen 1..5)
    for note: UInt8 in 0...127 {
        sendMidiPacket([0x90 | ch, note, 127])
        sendMidiPacket([0xB0 | ch, note, 127])
    }
}
print("  -> Alle LEDs aktiv für 1,5 Sekunden...")
usleep(1500000)

print("  -> Zurücksetzen (Alles AUS)...")
for ch: UInt8 in 0...15 {
    for note: UInt8 in 0...127 {
        sendMidiPacket([0x80 | ch, note, 0])
        sendMidiPacket([0xB0 | ch, note, 0])
    }
}

print("\n==========================================================")
print("  SWEEP VOLLSTÄNDIG ABGESCHLOSSEN!                         ")
print("==========================================================")
