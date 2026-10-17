import Foundation
import CoreMIDI

print("=== Sending CC #5 (and Note 5) on ALL 16 MIDI Channels at 120.0 BPM (16 Beats) ===")

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
    print("ERROR: Rane Sixty-Eight destination not found!")
    exit(1)
}

var client: MIDIClientRef = 0
MIDIClientCreate("CC5TestClient" as CFString, nil, nil, &client)

var outPort: MIDIPortRef = 0
MIDIOutputPortCreate(client, "CC5TestOut" as CFString, &outPort)

func sendMidi(_ bytes: [UInt8]) {
    var packet = MIDIPacket()
    packet.timeStamp = 0
    packet.length = UInt16(bytes.count)
    withUnsafeMutableBytes(of: &packet.data) { ptr in
        for i in 0..<bytes.count { ptr[i] = bytes[i] }
    }
    var list = MIDIPacketList(numPackets: 1, packet: packet)
    MIDISend(outPort, raneDest, &list)
}

print("Starting 16 Beats at 120.0 BPM (every 500ms)...")
print("Triggering CC #5 (127 -> 0) & Note #5 on all channels 1-16.")

for beat in 1...16 {
    print(">>> Beat \(beat) / 16 (120 BPM)")
    
    // ON (127) across all channels 0..15
    for ch: UInt8 in 0...15 {
        sendMidi([0xB0 | ch, 5, 127]) // CC #5
        sendMidi([0x90 | ch, 5, 127]) // Note #5
    }
    
    usleep(80000) // 80ms pulse duration
    
    // OFF (0) across all channels 0..15
    for ch: UInt8 in 0...15 {
        sendMidi([0xB0 | ch, 5, 0])
        sendMidi([0x80 | ch, 5, 0])
    }
    
    usleep(420000) // Remaining 420ms (total 500ms per beat)
}

print("Finished 16 beats!")
