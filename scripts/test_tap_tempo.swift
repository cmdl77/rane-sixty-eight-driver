import Foundation
import CoreMIDI

print("=== Testing TAP Button MIDI Simulation on Rane Sixty-Eight ===")

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
    print("Rane Sixty-Eight destination not found!")
    exit(1)
}

var client: MIDIClientRef = 0
MIDIClientCreate("TapTestClient" as CFString, nil, nil, &client)

var outPort: MIDIPortRef = 0
MIDIOutputPortCreate(client, "TapTestOut" as CFString, &outPort)

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

print("Testing Note 5 on Ch 0 (Note On / Note Off pulses every 500ms = 120 BPM)...")
for tap in 1...6 {
    print("  -> TAP #\(tap) (Note 5 On)")
    sendMidi([0x90, 5, 127]) // Note On
    usleep(50000)            // 50ms pulse
    sendMidi([0x80, 5, 0])   // Note Off
    usleep(450000)           // Wait remainder of 500ms (120 BPM)
}

print("Done. Check if Tap LED flashed or BPM display changed!")
