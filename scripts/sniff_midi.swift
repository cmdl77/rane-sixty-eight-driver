import Foundation
import CoreMIDI

print("=== Listening for Rane Sixty-Eight MIDI IN ===")
print("Please press the physical TAP button (and any other FlexFX buttons) on the mixer now...")

var client: MIDIClientRef = 0
MIDIClientCreate("TapSnifferClient" as CFString, nil, nil, &client)

var inPort: MIDIPortRef = 0
let readProc: MIDIReadProc = { pktList, _, _ in
    var packet = pktList.pointee.packet
    for _ in 0..<pktList.pointee.numPackets {
        var bytes = [UInt8]()
        withUnsafePointer(to: packet.data) { ptr in
            let bytePtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
            for j in 0..<Int(packet.length) {
                bytes.append(bytePtr[j])
            }
        }
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print(">>> MIXER PRESSED: len=\(packet.length) -> \(hex)")
        packet = MIDIPacketNext(&packet).pointee
    }
}
MIDIInputPortCreate(client, "TapSnifferIn" as CFString, readProc, nil, &inPort)

let numSrcs = MIDIGetNumberOfSources()
var raneSrc: MIDIEndpointRef = 0
for i in 0..<numSrcs {
    let src = MIDIGetSource(i)
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(src, kMIDIPropertyName, &name)
    let srcName = (name?.takeRetainedValue() as String?) ?? ""
    if srcName.contains("Sixty-Eight") || srcName.contains("Rane") {
        raneSrc = src
        break
    }
}

guard raneSrc != 0 else {
    print("Rane Sixty-Eight source not found!")
    exit(1)
}

MIDIPortConnectSource(inPort, raneSrc, nil)
print("Connected! Listening for 10 seconds...")

RunLoop.current.run(until: Date().addingTimeInterval(10.0))
print("Finished listening.")
