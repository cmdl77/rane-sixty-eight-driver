/* SPDX-License-Identifier: MIT */
/* RaneMidiService.swift - CoreMIDI and USB hardware monitor engine */

import Foundation
import CoreMIDI
import IOKit
import IOKit.hid

class RaneMidiService {
    static let shared = RaneMidiService()

    private var midiClient: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    private var inPort: MIDIPortRef = 0
    private var destEndpoint: MIDIEndpointRef = 0
    private var srcEndpoint: MIDIEndpointRef = 0
    private var connectedSources = Set<MIDIEndpointRef>()

    // USB Hardware Detection via IOHIDManager
    private var hidManager: IOHIDManager?
    private var pingTimer: Timer?
    private var lastActivityTime: TimeInterval = Date().timeIntervalSince1970
    private var isResponsive: Bool = true
    private var lastReportedState: Bool = false

    var isConnected: Bool {
        guard isUsbAttached else { return false }
        guard destEndpoint != 0, isEndpointOnline(destEndpoint) else { return false }
        return isResponsive
    }

    private var isUsbAttached: Bool {
        guard let mgr = hidManager, let set = IOHIDManagerCopyDevices(mgr) else { return false }
        let count = CFSetGetCount(set)
        return count > 0
    }

    var onMidiReceived: ((UInt8, UInt8, UInt8) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?

    init() {
        setupMidi()
        setupUsbMonitor()
        startHeartbeat()
    }

    private func setupMidi() {
        let notifyProc: MIDINotifyProc = { message, refCon in
            guard let refCon = refCon else { return }
            let service = Unmanaged<RaneMidiService>.fromOpaque(refCon).takeUnretainedValue()
            DispatchQueue.main.async {
                service.connectEndpoints()
            }
        }

        var status = MIDIClientCreate("RaneControlPanelClient" as CFString, notifyProc, Unmanaged.passUnretained(self).toOpaque(), &midiClient)
        if status != noErr { return }

        status = MIDIOutputPortCreate(midiClient, "ControlPanelOut" as CFString, &outPort)
        if status != noErr { return }

        let readProc: MIDIReadProc = { pktList, readRefCon, _ in
            guard let refCon = readRefCon else { return }
            let service = Unmanaged<RaneMidiService>.fromOpaque(refCon).takeUnretainedValue()
            service.processIncomingPacketList(pktList)
        }

        status = MIDIInputPortCreate(midiClient, "ControlPanelIn" as CFString, readProc, Unmanaged.passUnretained(self).toOpaque(), &inPort)

        connectEndpoints()
    }

    private func setupUsbMonitor() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let mgr = hidManager else { return }

        let matchArray: [NSDictionary] = [
            [kIOHIDVendorIDKey: 0x1CC5, kIOHIDProductIDKey: 0x0004], // Sixty-Eight USB A
            [kIOHIDVendorIDKey: 0x1CC5, kIOHIDProductIDKey: 0x0008]  // Sixty-Eight USB B
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matchArray as CFArray)

        let matchCb: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let service = Unmanaged<RaneMidiService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                service.connectEndpoints()
            }
        }

        let removeCb: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let service = Unmanaged<RaneMidiService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                service.isResponsive = false
                service.connectEndpoints()
            }
        }

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, matchCb, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, removeCb, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func startHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkHardwareHeartbeat()
        }
    }

    private func checkHardwareHeartbeat() {
        let attached = isUsbAttached && destEndpoint != 0 && isEndpointOnline(destEndpoint)
        if attached != isResponsive {
            isResponsive = attached
            evaluateConnectionState()
        }
    }

    func requestHardwareDump() {
        sendSysEx([0xF0, 0x17, 0x04, 0x00, 0xF7])
    }

    func isEndpointOnline(_ endpoint: MIDIEndpointRef) -> Bool {
        guard endpoint != 0 else { return false }
        var offline: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        if status == noErr && offline != 0 {
            return false
        }
        return true
    }

    func connectEndpoints() {
        var foundDest: MIDIEndpointRef = 0

        let numDests = MIDIGetNumberOfDestinations()
        for i in 0..<numDests {
            let d = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(d, kMIDIPropertyName, &name)
            if let str = name?.takeRetainedValue() as String? {
                if str.contains("Sixty-Eight") || str.contains("Rane") {
                    if isEndpointOnline(d) {
                        foundDest = d
                        break
                    }
                }
            }
        }

        destEndpoint = foundDest

        let numSrcs = MIDIGetNumberOfSources()

        // Connect ALL online MIDI sources (Rane Sixty-Eight, external controllers, keyboards, Xone, etc.)
        // so that MIDI Learn can learn from any controller seamlessly!
        for i in 0..<numSrcs {
            let s = MIDIGetSource(i)
            if isEndpointOnline(s) {
                if !connectedSources.contains(s) {
                    let status = MIDIPortConnectSource(inPort, s, nil)
                    if status == noErr {
                        connectedSources.insert(s)
                    }
                }
            }
        }

        evaluateConnectionState()
    }

    private func evaluateConnectionState() {
        let current = isConnected
        if current != lastReportedState {
            lastReportedState = current
            if current {
                requestHardwareDump()
            }
            DispatchQueue.main.async {
                self.onConnectionStateChanged?(current)
            }
        }
    }

    // Echo suppression: Outgoing MIDI messages sent to hardware/virtual endpoints
    private struct OutgoingEcho {
        let status: UInt8
        let d1: UInt8
        let d2: UInt8
        let timestamp: TimeInterval
    }
    private var sentEchoes: [OutgoingEcho] = []
    private let echoLock = NSLock()

    private func recordSentMidi(status: UInt8, d1: UInt8, d2: UInt8) {
        echoLock.lock()
        defer { echoLock.unlock() }
        let now = Date().timeIntervalSince1970
        // Clean up entries older than 0.5s
        sentEchoes.removeAll { now - $0.timestamp > 0.5 }
        sentEchoes.append(OutgoingEcho(status: status, d1: d1, d2: d2, timestamp: now))
    }

    private func isEchoOfSentMidi(status: UInt8, d1: UInt8, d2: UInt8) -> Bool {
        echoLock.lock()
        defer { echoLock.unlock() }
        let now = Date().timeIntervalSince1970
        // Clean up entries older than 0.5s
        sentEchoes.removeAll { now - $0.timestamp > 0.5 }

        let isIncomingNoteOff = (status & 0xF0 == 0x80) || ((status & 0xF0 == 0x90) && d2 == 0)

        // Check if this matches a recently sent message
        if let idx = sentEchoes.firstIndex(where: { echo in
            // Exact status & number match
            if (echo.status & 0x0F) == (status & 0x0F) && echo.d1 == d1 {
                let isSentNoteOff = (echo.status & 0xF0 == 0x80) || ((echo.status & 0xF0 == 0x90) && echo.d2 == 0)
                if isIncomingNoteOff && isSentNoteOff {
                    return true
                }
                if echo.status == status && echo.d2 == d2 {
                    return true
                }
            }
            return false
        }) {
            sentEchoes.remove(at: idx)
            return true
        }
        return false
    }

    func sendCC(cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        guard isConnected else { return }
        if destEndpoint == 0 { connectEndpoints() }
        guard destEndpoint != 0 else { return }

        let st = 0xB0 | (channel & 0x0F)
        let c = cc & 0x7F
        let v = value & 0x7F
        recordSentMidi(status: st, d1: c, d2: v)

        var packet = MIDIPacket()
        packet.length = 3
        packet.timeStamp = 0
        packet.data.0 = st
        packet.data.1 = c
        packet.data.2 = v

        var list = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(outPort, destEndpoint, &list)
    }

    func sendNoteOn(note: UInt8, velocity: UInt8 = 127, channel: UInt8 = 0) {
        guard isConnected else { return }
        if destEndpoint == 0 { connectEndpoints() }
        guard destEndpoint != 0 else { return }

        let st = 0x90 | (channel & 0x0F)
        let n = note & 0x7F
        let vel = velocity & 0x7F
        recordSentMidi(status: st, d1: n, d2: vel)

        var packet = MIDIPacket()
        packet.length = 3
        packet.timeStamp = 0
        packet.data.0 = st
        packet.data.1 = n
        packet.data.2 = vel

        var list = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(outPort, destEndpoint, &list)
    }

    func sendNoteOff(note: UInt8, channel: UInt8 = 0) {
        guard isConnected else { return }
        if destEndpoint == 0 { connectEndpoints() }
        guard destEndpoint != 0 else { return }

        let ch = channel & 0x0F
        let n = note & 0x7F
        let st = 0x80 | ch
        recordSentMidi(status: st, d1: n, d2: 0)

        var packet = MIDIPacket()
        packet.length = 3
        packet.timeStamp = 0
        packet.data.0 = st
        packet.data.1 = n
        packet.data.2 = 0

        var list = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(outPort, destEndpoint, &list)
    }

    /// Turns off all hardware LEDs across all MIDI notes and channels (0..127) as an initial clean slate
    func resetAllHardwareLeds() {
        guard isConnected else { return }
        if destEndpoint == 0 { connectEndpoints() }
        guard destEndpoint != 0 else { return }

        // Turn off all standard MIDI notes (0..127) on Channel 0 (and common control channels)
        for note in UInt8(0)...UInt8(127) {
            sendNoteOff(note: note, channel: 0)
        }
        for ch in UInt8(1)...UInt8(3) {
            for note in [UInt8(62), UInt8(65), UInt8(66), UInt8(67), UInt8(68), UInt8(69), UInt8(70), UInt8(71)] {
                sendNoteOff(note: note, channel: ch)
            }
        }
        // Turn off cue & flexfx CCs
        for cc in [UInt8(0), UInt8(4), UInt8(5), UInt8(8), UInt8(9), UInt8(10), UInt8(11), UInt8(12), UInt8(13), UInt8(14), UInt8(15), UInt8(40), UInt8(41), UInt8(56), UInt8(62), UInt8(65), UInt8(66), UInt8(67), UInt8(68), UInt8(69), UInt8(70), UInt8(71)] {
            sendCC(cc: cc, value: 0, channel: 0)
        }
    }

    func sendSysEx(_ bytes: [UInt8]) {
        guard destEndpoint != 0, isEndpointOnline(destEndpoint), !bytes.isEmpty else { return }

        var packet = MIDIPacket()
        packet.timeStamp = 0
        let len = min(bytes.count, 256)
        packet.length = UInt16(len)
        withUnsafeMutableBytes(of: &packet.data) { ptr in
            for i in 0..<len {
                ptr[i] = bytes[i]
            }
        }
        var list = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(outPort, destEndpoint, &list)
    }

    private func processIncomingPacketList(_ pktList: UnsafePointer<MIDIPacketList>) {
        lastActivityTime = Date().timeIntervalSince1970
        if !isResponsive {
            isResponsive = true
            evaluateConnectionState()
        }
        var packet = pktList.pointee.packet
        for _ in 0..<pktList.pointee.numPackets {
            let status = packet.data.0
            let d1 = packet.data.1
            let d2 = packet.data.2

            // Filter out echoes of messages that our application just transmitted
            if !isEchoOfSentMidi(status: status, d1: d1, d2: d2) {
                DispatchQueue.main.async {
                    self.onMidiReceived?(status, d1, d2)
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }
}
