/* SPDX-License-Identifier: MIT */
/* test_bpm_sync_100.swift - Systematic Hardware BPM Sync Test (100 BPM) for Rane Sixty-Eight */

import Foundation
import CoreMIDI

print("=================================================================")
print("   Rane Sixty-Eight: Hardware BPM Sync Test (Ziel: 100 BPM)     ")
print("=================================================================")

// 1. Locate Rane Sixty-Eight MIDI Destination & Source
var raneDest: MIDIEndpointRef = 0
var raneSrc: MIDIEndpointRef = 0

let numDests = MIDIGetNumberOfDestinations()
for i in 0..<numDests {
    let d = MIDIGetDestination(i)
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(d, kMIDIPropertyName, &name)
    let n = (name?.takeRetainedValue() as String?) ?? ""
    if n.contains("Sixty-Eight") || n.contains("Rane") {
        raneDest = d
        print("✓ MIDI-Ausgang gefunden: \(n)")
        break
    }
}

let numSrcs = MIDIGetNumberOfSources()
for i in 0..<numSrcs {
    let s = MIDIGetSource(i)
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(s, kMIDIPropertyName, &name)
    let n = (name?.takeRetainedValue() as String?) ?? ""
    if n.contains("Sixty-Eight") || n.contains("Rane") {
        raneSrc = s
        print("✓ MIDI-Eingang gefunden:  \(n)")
        break
    }
}

guard raneDest != 0 else {
    print("❌ FEHLER: Rane Sixty-Eight MIDI-Destination nicht gefunden!")
    exit(1)
}

// 2. Setup CoreMIDI Client & Ports
var midiClient: MIDIClientRef = 0
MIDIClientCreate("RaneBpmTestClient" as CFString, nil, nil, &midiClient)

var outPort: MIDIPortRef = 0
MIDIOutputPortCreate(midiClient, "RaneBpmTestOut" as CFString, &outPort)

var inPort: MIDIPortRef = 0
let readProc: MIDIReadProc = { pktList, _, _ in
    var p = pktList.pointee.packet
    for _ in 0..<pktList.pointee.numPackets {
        let len = Int(p.length)
        let m = Mirror(reflecting: p.data)
        let b: [UInt8] = m.children.prefix(len).map { $0.value as! UInt8 }
        // Ignore heartbeat CC #86
        if !(len == 3 && b[0] == 0xB0 && b[1] == 0x56) {
            let hex = b.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("   <<< ANTWORT VOM MIXER [\(len) Bytes]: \(hex)")
        }
        p = MIDIPacketNext(&p).pointee
    }
}
MIDIInputPortCreate(midiClient, "RaneBpmTestIn" as CFString, readProc, nil, &inPort)
if raneSrc != 0 {
    MIDIPortConnectSource(inPort, raneSrc, nil)
}

func sendRawBytes(_ bytes: [UInt8]) {
    var packet = MIDIPacket()
    packet.timeStamp = 0
    packet.length = UInt16(bytes.count)
    withUnsafeMutableBytes(of: &packet.data) { ptr in
        for i in 0..<bytes.count { ptr[i] = bytes[i] }
    }
    var list = MIDIPacketList(numPackets: 1, packet: packet)
    MIDISend(outPort, raneDest, &list)
}

func sendSysEx(_ bytes: [UInt8]) {
    let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("   >>> SENDE SYSEX: \(hex)")
    sendRawBytes(bytes)
}

// 3. User Instruction
print("\n-----------------------------------------------------------------")
print("BITTE JETZT AM MIXER PRÜFEN:")
print("1. Stelle sicher, dass NUR PGM 1 (Kanal 1) auf FlexFX geroutet ist")
print("   (Die gelbe FlexFX-Taste an Kanal 1 leuchtet, alle anderen aus).")
print("2. SCHAUE JETZT AUF DAS KLEINE LCD-DISPLAY DER FLEXFX-SEKTION!")
print("   Achte auf: Wechselt die BPM auf '100' oder '100.0'?")
print("   Blinkt das Sternchen (*)?")
print("-----------------------------------------------------------------\n")

print("Test startet in 3 Sekunden...")
sleep(1)
print("2...")
sleep(1)
print("1... JETZT AUFS DISPLAY SCHAUEN!\n")
sleep(1)

// =================================================================
// TEST 1: MIDI Real-Time Timing Clock (0xF8) bei exakt 100.0 BPM
// =================================================================
print("=================================================================")
print("▶ TEST 1: MIDI Real-Time Clock (100.0 BPM kontinuierlich)")
print("  (Sende MIDI Start 0xFA + 24 Clock-Ticks/Beat für 4 Sekunden)")
print("=================================================================")
sendRawBytes([0xFA]) // MIDI Start
let bpm100IntervalUsec = useconds_t(60.0 / (100.0 * 24.0) * 1_000_000.0) // 25.0 ms = 25000 us
for _ in 0..<160 { // ca. 4 Sekunden (160 Ticks = ca. 6.6 Beats)
    sendRawBytes([0xF8])
    usleep(bpm100IntervalUsec)
}
print("  [Test 1 beendet - Hat sich auf 100 geändert?]")
sleep(2)

// =================================================================
// TEST 2: Rane SysEx Opcode 0x18 (DSP FX Params - 1-Byte BPM)
// =================================================================
print("\n=================================================================")
print("▶ TEST 2: SysEx Opcode 0x18 (Direct BPM = 100 / 0x64)")
print("=================================================================")
// 2A: Opcode 0x18, BPM 100
sendSysEx([0xF0, 0x17, 0x18, 100, 0xF7])
usleep(500000)

// 2B: Opcode 0x18, Deck 0 (PGM 1), BPM 100
sendSysEx([0xF0, 0x17, 0x18, 0x00, 100, 0xF7])
usleep(500000)

// 2C: Opcode 0x18, Deck 1, BPM 100
sendSysEx([0xF0, 0x17, 0x18, 0x01, 100, 0xF7])
usleep(500000)

// 2D: Opcode 0x18, Sub-Command 0x01 (Set Tempo), BPM 100
sendSysEx([0xF0, 0x17, 0x18, 0x01, 0x00, 100, 0xF7])
sleep(2)

// =================================================================
// TEST 3: Rane SysEx Opcode 0x18 (14-Bit BPM)
// 100.0 BPM * 10 = 1000 = (0x07 << 7) | 0x68
// 100.00 BPM * 100 = 10000 = (0x4E << 7) | 0x10
// =================================================================
print("\n=================================================================")
print("▶ TEST 3: SysEx Opcode 0x18 (14-Bit High-Res BPM: 1000 / 10000)")
print("=================================================================")
// 3A: 100.0 BPM (MSB/LSB: 0x07, 0x68)
sendSysEx([0xF0, 0x17, 0x18, 0x07, 0x68, 0xF7])
usleep(400000)
sendSysEx([0xF0, 0x17, 0x18, 0x68, 0x07, 0xF7])
usleep(400000)

// 3B: Deck 0 + 100.0 BPM
sendSysEx([0xF0, 0x17, 0x18, 0x00, 0x07, 0x68, 0xF7])
usleep(400000)
sendSysEx([0xF0, 0x17, 0x18, 0x00, 0x68, 0x07, 0xF7])
usleep(400000)

// 3C: 100.00 BPM (MSB/LSB: 0x4E, 0x10)
sendSysEx([0xF0, 0x17, 0x18, 0x4E, 0x10, 0xF7])
usleep(400000)
sendSysEx([0xF0, 0x17, 0x18, 0x00, 0x4E, 0x10, 0xF7])
sleep(2)

// =================================================================
// TEST 4: Rane SysEx Opcode 0x02 (Get/Set Parameter)
// =================================================================
print("\n=================================================================")
print("▶ TEST 4: SysEx Opcode 0x02 (Parameter Set BPM)")
print("=================================================================")
let paramCandidates: [UInt8] = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x14, 0x18, 0x20]
for p in paramCandidates {
    // Param ID, Value 100
    sendSysEx([0xF0, 0x17, 0x02, p, 100, 0xF7])
    usleep(250000)
}
sleep(2)

// =================================================================
// TEST 5: Serato DJ Deck Sync Pattern (Deck 1 Active FlexFX)
// =================================================================
print("\n=================================================================")
print("▶ TEST 5: Serato-Style Deck Sync Handshake")
print("=================================================================")
// Emulate Deck 1 Active FlexFX + Tagged BPM
// Deck 1 = Channel 1 (Note 68 = 0x44)
sendSysEx([0xF0, 0x17, 0x18, 0x44, 100, 0xF7])
usleep(300000)
sendSysEx([0xF0, 0x17, 0x18, 0x44, 0x07, 0x68, 0xF7])
usleep(300000)
// With sub-command 0x53 (Sync)
sendSysEx([0xF0, 0x17, 0x53, 0x01, 100, 0xF7])
usleep(300000)

print("\n=================================================================")
print("✓ Alle 5 Test-Muster wurden an den Rane Sixty-Eight gesendet.")
print("=================================================================")
