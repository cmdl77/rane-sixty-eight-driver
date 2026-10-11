import Foundation
import CoreMIDI

print("=== Rane Sixty-Eight MIDI Clock Diagnostic Tool ===")

let numDests = MIDIGetNumberOfDestinations()
var raneDest: MIDIEndpointRef = 0

for i in 0..<numDests {
    let dest = MIDIGetDestination(i)
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(dest, kMIDIPropertyName, &name)
    let destName = (name?.takeRetainedValue() as String?) ?? "Unknown"
    if destName.contains("Sixty-Eight") || destName.contains("Rane") {
        raneDest = dest
    }
}

let numSrcs = MIDIGetNumberOfSources()
var raneSrc: MIDIEndpointRef = 0

for i in 0..<numSrcs {
    let src = MIDIGetSource(i)
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(src, kMIDIPropertyName, &name)
    let srcName = (name?.takeRetainedValue() as String?) ?? "Unknown"
    if srcName.contains("Sixty-Eight") || srcName.contains("Rane") {
        raneSrc = src
    }
}

if raneDest == 0 {
    print("ERROR: Rane Sixty-Eight MIDI Destination not found!")
    exit(1)
}

print("Found Rane Destination: \(raneDest)")

var client: MIDIClientRef = 0
MIDIClientCreate("ClockTestClient" as CFString, nil, nil, &client)

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
        print("  [MIXER REPLY] len=\(packet.length): \(hex)")
        packet = MIDIPacketNext(&packet).pointee
    }
}
MIDIInputPortCreate(client, "ClockTestIn" as CFString, readProc, nil, &inPort)

if raneSrc != 0 {
    MIDIPortConnectSource(inPort, raneSrc, nil)
    print("Listening on Rane Sixty-Eight Source...")
}

var outPort: MIDIPortRef = 0
MIDIOutputPortCreate(client, "ClockTestOut" as CFString, &outPort)

func sendBytes(_ bytes: [UInt8]) {
    var packet = MIDIPacket()
    packet.timeStamp = 0
    packet.length = UInt16(bytes.count)
    withUnsafeMutableBytes(of: &packet.data) { ptr in
        for i in 0..<bytes.count {
            ptr[i] = bytes[i]
        }
    }
    var list = MIDIPacketList(numPackets: 1, packet: packet)
    let err = MIDISend(outPort, raneDest, &list)
    if err != noErr {
        print("MIDISend error: \(err)")
    }
}

print("\nStarting MIDI Clock generator at 120.0 BPM (24 ppqn = 1 tick every ~20.8ms)...")
print("Sending MIDI START (0xFA)...")
sendBytes([0xFA])

var clockCount = 0
let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
// 120 BPM: 60 / 120 / 24 = 0.020833333s = 20,833,333 ns
timer.schedule(deadline: .now(), repeating: .nanoseconds(20_833_333))
timer.setEventHandler {
    sendBytes([0xF8])
    clockCount += 1
    if clockCount % 24 == 0 {
        let beat = clockCount / 24
        print("Tick beat \(beat) (pulses: \(clockCount))")
    }
}
timer.resume()

// Run for 5 seconds
RunLoop.current.run(until: Date().addingTimeInterval(5.0))
timer.cancel()

print("Sending MIDI STOP (0xFC)...")
sendBytes([0xFC])
print("Completed. Sent \(clockCount) clock pulses.")
