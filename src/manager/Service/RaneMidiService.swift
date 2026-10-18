/* SPDX-License-Identifier: MIT */
/* RaneMidiService.swift - CoreMIDI and USB hardware monitor engine */

import Foundation
import CoreMIDI
import IOKit
import IOKit.hid

public struct MidiInputDeviceInfo: Equatable {
    public let endpointRef: MIDIEndpointRef
    public let id: String
    public let displayName: String
}

class RaneMidiService {
    static let shared = RaneMidiService()

    private var midiClient: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    private var inPort: MIDIPortRef = 0
    private var destEndpoint: MIDIEndpointRef = 0
    private var srcEndpoint: MIDIEndpointRef = 0
    private var connectedSources = Set<MIDIEndpointRef>()
    private var allOnlineDestinations: [MIDIEndpointRef] = []

    public private(set) var availableInputDevices: [MidiInputDeviceInfo] = []
    private var endpointToDeviceId: [MIDIEndpointRef: String] = [:]
    private let endpointMapLock = NSLock()

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
    var onMidiDevicesChanged: (() -> Void)?

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

        let readProc: MIDIReadProc = { pktList, readRefCon, srcConnRefCon in
            guard let refCon = readRefCon else { return }
            let service = Unmanaged<RaneMidiService>.fromOpaque(refCon).takeUnretainedValue()
            service.processIncomingPacketList(pktList, srcConnRefCon: srcConnRefCon)
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
        sendSysEx([RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.getAllControls, RaneProtocol.sysExEnd])
    }

    /// Sets the full LED illumination matrix in a single 12-byte SysEx command (Opcode 0x09)
    func sendBulkLedMatrix(_ matrix: [UInt8]) {
        var payload = matrix
        if payload.count < 9 {
            payload += [UInt8](repeating: 0, count: 9 - payload.count)
        } else if payload.count > 9 {
            payload = Array(payload.prefix(9))
        }
        var msg = [RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.bulkLedMatrix]
        msg.append(contentsOf: payload)
        msg.append(RaneProtocol.sysExEnd)
        sendSysEx(msg)
    }

    private var hidSeqNum: UInt32 = 1000
    private let hidLock = NSLock()
    private var isRomUnlocked: Bool = false
    private var isCustomOledModeActive: Bool = false
    private var oledRevertWorkItem: DispatchWorkItem?

    private let oledGreetingLine1Key = "RaneSixtyEight_OledGreetingLine1_v1"
    private let oledGreetingLine2Key = "RaneSixtyEight_OledGreetingLine2_v1"

    public var oledGreetingLine1: String {
        get {
            return UserDefaults.standard.string(forKey: oledGreetingLine1Key) ?? "HENRY'S RANE68"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: oledGreetingLine1Key)
        }
    }

    public var oledGreetingLine2: String {
        get {
            return UserDefaults.standard.string(forKey: oledGreetingLine2Key) ?? "WELCOME BACK!"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: oledGreetingLine2Key)
        }
    }

    /// Unmutes the mixer audio engine and designates the active USB port (Opcode 0x52, 5 bytes)
    func sendUnmute(port: UInt8 = RaneProtocol.Port.usbPortA) {
        sendSysEx([RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.audioUnmute, port, RaneProtocol.sysExEnd])
    }

    /// Unlocks the LPC2468 hardware security gate using the verified 7-byte ROM key (Opcode 0x18, 11 bytes)
    func sendHardwareUnlock() {
        var msg: [UInt8] = [RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.securityUnlock]
        msg.append(contentsOf: RaneProtocol.romUnlockKey)
        msg.append(RaneProtocol.sysExEnd)
        sendSysEx(msg)
        isRomUnlocked = true
    }

    /// Formats any string to exactly 14 ASCII characters for a Rane Sixty-Eight OLED line
    private func formatOled14(_ text: String) -> [UInt8] {
        var normalized = text
        if normalized.count > 14 {
            normalized = normalized
                .replacingOccurrences(of: "Ableton Link off", with: "AbletonLinkoff")
                .replacingOccurrences(of: "Ableton Link on", with: "AbletonLink on")
                .replacingOccurrences(of: "Ableton Link ", with: "AbletonLink ")
        }
        let ascii = normalized.unicodeScalars.map { scalar -> UInt8 in
            let v = scalar.value
            return (v >= 0x20 && v <= 0x7E) ? UInt8(v) : 0x20
        }
        if ascii.count >= 14 {
            return Array(ascii.prefix(14))
        } else {
            return ascii + [UInt8](repeating: 0x20, count: 14 - ascii.count)
        }
    }

    /// Enables (0x7D) or disables (0x7C) Custom OLED Mode on the patched Rane Sixty-Eight firmware
    func setCustomOledMode(_ enabled: Bool) {
        guard isUsbAttached else { return }
        if !isRomUnlocked {
            sendUnmute(port: RaneProtocol.Port.usbPortA)
            sendHardwareUnlock()
        }
        if enabled {
            sendSysEx([RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.oledCustomModeOn, 0x01, RaneProtocol.sysExEnd])
            isCustomOledModeActive = true
        } else {
            sendSysEx([RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.oledCustomModeOff, 0x00, RaneProtocol.sysExEnd])
            isCustomOledModeActive = false
        }
    }

    /// Sets the hardware channel strip filter mode for PGM 1..4 via Firmware SysEx 0x06 (`F0 17 06 <arg> F7`)
    /// - Parameters:
    ///   - channel: 1..4 (PGM 1..4)
    ///   - mode: 0 = Normal (LP+HP), 1 = Low-Pass Only (270°), 2 = High-Pass Only (270°), 3 = Filter OFF (MIDI Only)
    func sendChannelFilterMode(channel: Int, mode: Int) {
        let chIdx = UInt8(max(0, min(3, channel - 1)))
        let modeIdx = UInt8(max(0, min(3, mode)))
        let arg = (chIdx << 4) | modeIdx
        sendSysEx([
            RaneProtocol.sysExStart,
            RaneProtocol.manufacturerId,
            RaneProtocol.Opcode.channelFilterMode,
            arg,
            RaneProtocol.sysExEnd
        ])
    }

    /// Writes 14 ASCII characters to Line 1 (0x400000E7) of the hardware OLED display (SysEx 0x01)
    func sendOledLine1(_ text: String) {
        guard isUsbAttached else { return }
        if !isCustomOledModeActive {
            setCustomOledMode(true)
        }
        var msg: [UInt8] = [RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.oledLine1]
        msg.append(contentsOf: formatOled14(text))
        msg.append(RaneProtocol.sysExEnd)
        sendSysEx(msg)
    }

    /// Writes 14 ASCII characters to Line 2 (0x400000F5) of the hardware OLED display (SysEx 0x02)
    func sendOledLine2(_ text: String) {
        guard isUsbAttached else { return }
        if !isCustomOledModeActive {
            setCustomOledMode(true)
        }
        var msg: [UInt8] = [RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.oledLine2]
        msg.append(contentsOf: formatOled14(text))
        msg.append(RaneProtocol.sysExEnd)
        sendSysEx(msg)
    }

    /// Displays the user-configured 2-line greeting text on the hardware OLED for 5 seconds, then restores the original display (0x7C)
    func showOledGreeting(durationSeconds: TimeInterval = 5.0) {
        guard isUsbAttached else { return }
        oledRevertWorkItem?.cancel()

        setCustomOledMode(true)
        sendOledLine1(oledGreetingLine1)
        sendOledLine2(oledGreetingLine2)

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.setCustomOledMode(false)
            self.sendHardwareBpmSync(
                bpm: RaneFlexFxService.shared.bpm,
                beatPulse: RaneFlexFxService.shared.isLinkEnabled
            )
        }
        oledRevertWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds, execute: work)
    }

    /// Shows "Ableton Link on" or "Ableton Link off" on OLED Line 2 for 2 seconds, then restores the original mixer display (0x7C)
    func sendOledAbletonLinkStatus(enabled: Bool, durationSeconds: TimeInterval = 2.0) {
        guard isUsbAttached else { return }
        oledRevertWorkItem?.cancel()

        setCustomOledMode(true)
        let clampedBpm = max(41.0, min(300.0, RaneFlexFxService.shared.bpm))
        let star = enabled ? "*" : " "
        let line1 = String(format: "BPM: %-6.1f  %@", clampedBpm, star)
        sendOledLine1(line1)
        sendOledLine2(enabled ? "Ableton Link on" : "Ableton Link off")

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Switch back to original firmware OLED display (BPM: / TIME:) via SysEx 0x7C
            self.setCustomOledMode(false)
            self.sendHardwareBpmSync(
                bpm: RaneFlexFxService.shared.bpm,
                beatPulse: RaneFlexFxService.shared.isLinkEnabled
            )
        }
        oledRevertWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds, execute: work)
    }

    /// Synchronizes the hardware OLED display BPM, DSP delay time & Serato asterisk (*) via 14-byte Nibble-Encoded Opcode 0x53
    func sendHardwareBpmSync(bpm: Double, beatPulse: Bool = true) {
        guard isUsbAttached else { return }
        if !isRomUnlocked {
            sendUnmute(port: RaneProtocol.Port.usbPortA)
            sendHardwareUnlock()
        }
        let clampedBpm = max(41.0, min(300.0, bpm))
        let bpmInt = UInt16(round(clampedBpm * 100.0))
        let hiByte = UInt8((bpmInt >> 8) & 0xFF)
        let loByte = UInt8(bpmInt & 0xFF)
        let astNib: UInt8 = beatPulse ? 0x01 : 0x00

        let sysex14: [UInt8] = [
            RaneProtocol.sysExStart,
            RaneProtocol.manufacturerId,
            RaneProtocol.Opcode.seratoBpmSync,
            0x00, 0x02,                         // Mode = 2 (Serato Sync)
            0x00, 0x01,                         // Beat Sync = 1
            (hiByte >> 4) & 0x0F, hiByte & 0x0F, // BPM High Byte Nibbles
            (loByte >> 4) & 0x0F, loByte & 0x0F, // BPM Low Byte Nibbles
            0x00, astNib,                       // Asterisk Blink Trigger
            RaneProtocol.sysExEnd
        ]
        sendSysEx(sysex14)
    }

    /// Releases Serato BPM Sync lock (returns mixer OLED display to manual/standalone mode)
    func sendMute() {
        let sysexRelease: [UInt8] = [
            RaneProtocol.sysExStart,
            RaneProtocol.manufacturerId,
            RaneProtocol.Opcode.seratoBpmSync,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            RaneProtocol.sysExEnd
        ]
        sendSysEx(sysexRelease)
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

    private func endpointDisplayName(_ endpoint: MIDIEndpointRef) -> String {
        var displayName: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &displayName) == noErr,
           let str = displayName?.takeRetainedValue() as String?, !str.isEmpty {
            return str
        }
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr,
           let str = name?.takeRetainedValue() as String?, !str.isEmpty {
            return str
        }
        return "MIDI Device (\(endpoint))"
    }

    func connectEndpoints() {
        var foundDest: MIDIEndpointRef = 0
        var onlineDests: [MIDIEndpointRef] = []

        let numDests = MIDIGetNumberOfDestinations()
        for i in 0..<numDests {
            let d = MIDIGetDestination(i)
            if isEndpointOnline(d) {
                onlineDests.append(d)
                let str = endpointDisplayName(d)
                if str.contains("Sixty-Eight") || str.contains("Rane") {
                    if foundDest == 0 {
                        foundDest = d
                    }
                }
            }
        }

        destEndpoint = foundDest
        allOnlineDestinations = onlineDests

        let numSrcs = MIDIGetNumberOfSources()
        var discoveredDevices: [MidiInputDeviceInfo] = []
        var newMap: [MIDIEndpointRef: String] = [:]

        // Connect ALL online MIDI sources (Rane Sixty-Eight, external controllers, keyboards, Xone, etc.)
        for i in 0..<numSrcs {
            let s = MIDIGetSource(i)
            if isEndpointOnline(s) {
                let dispName = endpointDisplayName(s)
                let devId = dispName
                newMap[s] = devId
                if !discoveredDevices.contains(where: { $0.id == devId }) {
                    discoveredDevices.append(MidiInputDeviceInfo(endpointRef: s, id: devId, displayName: dispName))
                }
                if !connectedSources.contains(s) {
                    let refPtr = UnsafeMutableRawPointer(bitPattern: UInt(s))
                    let status = MIDIPortConnectSource(inPort, s, refPtr)
                    if status == noErr {
                        connectedSources.insert(s)
                    }
                }
            }
        }

        endpointMapLock.lock()
        endpointToDeviceId = newMap
        endpointMapLock.unlock()

        let devicesChanged = (discoveredDevices != availableInputDevices)
        availableInputDevices = discoveredDevices
        if devicesChanged {
            DispatchQueue.main.async {
                self.onMidiDevicesChanged?()
            }
        }

        evaluateConnectionState()
    }

    private func evaluateConnectionState() {
        let current = isConnected
        if current != lastReportedState {
            lastReportedState = current
            if current {
                isRomUnlocked = false
                isCustomOledModeActive = false
                // 1. Set Control Point Port A (Opcode 0x52)
                sendUnmute(port: RaneProtocol.Port.usbPortA)
                // 2. Unlock LPC2468 Hardware Security Gate (Opcode 0x18)
                sendHardwareUnlock()
                // 3. Instant full blank of all hardware LEDs in 1 ms
                resetAllHardwareLeds()
                // 4. Request complete hardware state dump
                requestHardwareDump()
                // 5. Sync BPM and display 5-second startup greeting on OLED (reverts to original display after 5s)
                sendHardwareBpmSync(bpm: RaneFlexFxService.shared.bpm, beatPulse: RaneFlexFxService.shared.isLinkEnabled)
                showOledGreeting(durationSeconds: 5.0)
            } else {
                isRomUnlocked = false
                isCustomOledModeActive = false
            }
            DispatchQueue.main.async {
                self.onConnectionStateChanged?(current)
            }
        }
    }

    // Echo suppression: Outgoing MIDI messages sent to hardware/virtual endpoints
    private struct OutgoingEcho {
        let statusNibble: UInt8
        let channel: UInt8
        let number: UInt8
        let timestamp: TimeInterval
    }
    private var sentEchoes: [OutgoingEcho] = []
    private let echoLock = NSLock()

    private func recordSentMidi(status: UInt8, d1: UInt8, d2: UInt8) {
        echoLock.lock()
        defer { echoLock.unlock() }
        let now = Date().timeIntervalSince1970
        sentEchoes.removeAll { now - $0.timestamp > 1.5 }
        let nibble = status & 0xF0
        let ch = status & 0x0F
        sentEchoes.append(OutgoingEcho(statusNibble: nibble, channel: ch, number: d1, timestamp: now))
    }

    private func isEchoOfSentMidi(status: UInt8, d1: UInt8, d2: UInt8) -> Bool {
        echoLock.lock()
        defer { echoLock.unlock() }
        let now = Date().timeIntervalSince1970
        sentEchoes.removeAll { now - $0.timestamp > 1.5 }

        let incomingNibble = status & 0xF0
        let incomingCh = status & 0x0F

        if let idx = sentEchoes.firstIndex(where: { echo in
            if echo.channel == incomingCh && echo.number == d1 {
                // For Notes: both 0x90 and 0x80 match
                if (echo.statusNibble == 0x90 || echo.statusNibble == 0x80) &&
                   (incomingNibble == 0x90 || incomingNibble == 0x80) {
                    return true
                }
                // For CC: match CC nibble 0xB0
                if echo.statusNibble == 0xB0 && incomingNibble == 0xB0 {
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

    private func targetDestinations() -> [MIDIEndpointRef] {
        let selectedId = RaneMidiLearnService.shared.controllerMidiSourceId
        if selectedId != "OMNI" {
            let matched = allOnlineDestinations.filter { endpointDisplayName($0) == selectedId }
            if !matched.isEmpty {
                return matched
            }
        }
        return allOnlineDestinations
    }

    func sendCC(cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        if allOnlineDestinations.isEmpty { connectEndpoints() }
        let targets = targetDestinations()
        guard !targets.isEmpty else { return }

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
        for dest in targets {
            MIDISend(outPort, dest, &list)
        }
    }

    func sendNoteOn(note: UInt8, velocity: UInt8 = 127, channel: UInt8 = 0) {
        if allOnlineDestinations.isEmpty { connectEndpoints() }
        let targets = targetDestinations()
        guard !targets.isEmpty else { return }

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
        for dest in targets {
            MIDISend(outPort, dest, &list)
        }
    }

    func sendNoteOff(note: UInt8, channel: UInt8 = 0) {
        if allOnlineDestinations.isEmpty { connectEndpoints() }
        let targets = targetDestinations()
        guard !targets.isEmpty else { return }

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
        for dest in targets {
            MIDISend(outPort, dest, &list)
        }
    }

    /// Turns off all hardware LEDs across the mixer simultaneously using Opcode 0x09
    func resetAllHardwareLeds() {
        guard isConnected else { return }
        if destEndpoint == 0 { connectEndpoints() }
        guard destEndpoint != 0 else { return }

        // 1. High-speed Bulk LED Matrix Set: Clears all hardware LEDs simultaneously in 1 ms (Firmware Opcode 0x09)
        sendBulkLedMatrix([UInt8](repeating: 0, count: 9))

        // 2. Targeted note-offs for external/virtual mappings
        for ch in UInt8(0)...UInt8(1) {
            for note in [UInt8(62), UInt8(65), UInt8(66), UInt8(67), UInt8(68), UInt8(69), UInt8(70), UInt8(71)] {
                sendNoteOff(note: note, channel: ch)
            }
        }
    }

    func sendSysEx(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }

        // Direct hardware HID transmission with Cypress FX2 4-byte sequence header (0x41 + seq[4] + len + sysex)
        if let mgr = hidManager,
           let devSet = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
           let hidDev = devSet.first {
            hidLock.lock()
            let seq = hidSeqNum
            hidSeqNum &+= 1

            var pkt = [UInt8](repeating: 0, count: 64)
            pkt[0] = 0x41
            pkt[1] = UInt8((seq >> 24) & 0xFF)
            pkt[2] = UInt8((seq >> 16) & 0xFF)
            pkt[3] = UInt8((seq >> 8) & 0xFF)
            pkt[4] = UInt8(seq & 0xFF)
            let count = min(bytes.count, 58)
            pkt[5] = UInt8(count)
            for i in 0..<count {
                pkt[6 + i] = bytes[i]
            }
            let kr = IOHIDDeviceSetReport(hidDev, kIOHIDReportTypeOutput, 0, pkt, 64)
            usleep(12000) // 12ms pacing so back-to-back OLED SysEx packets (0x7D, 0x01, 0x02) never collide in FX2 EP1OUTBUF
            hidLock.unlock()
            if kr == kIOReturnSuccess {
                return
            }
        }

        // Fallback via CoreMIDI virtual endpoint
        guard destEndpoint != 0, isEndpointOnline(destEndpoint) else { return }
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

    private func processIncomingPacketList(_ pktList: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutableRawPointer?) {
        lastActivityTime = Date().timeIntervalSince1970
        if !isResponsive {
            isResponsive = true
            evaluateConnectionState()
        }

        var sourceId: String = "OMNI"
        if let ref = srcConnRefCon {
            let ep = MIDIEndpointRef(UInt(bitPattern: ref))
            endpointMapLock.lock()
            if let mapped = endpointToDeviceId[ep] {
                sourceId = mapped
            }
            endpointMapLock.unlock()
        }

        var packet = pktList.pointee.packet
        for _ in 0..<pktList.pointee.numPackets {
            let len = Int(packet.length)
            if len > 0 {
                let status = packet.data.0
                let d1 = len > 1 ? packet.data.1 : 0
                let d2 = len > 2 ? packet.data.2 : 0

                // System Real-Time MIDI Clock / Start / Continue / Stop (0xF8..0xFC)
                if status >= 0xF8 && status <= 0xFC {
                    RanePluginHostService.shared.routeIncomingMidi(fromSourceId: sourceId, status: status, d1: 0, d2: 0)
                } else if status >= 0x80 && status < 0xF0 {
                    // Filter out echoes of messages that our application just transmitted
                    if !isEchoOfSentMidi(status: status, d1: d1, d2: d2) {
                        // 1. Forward MIDI Event immediately to VST/AU Plugin Slots that listen to this controller
                        RanePluginHostService.shared.routeIncomingMidi(fromSourceId: sourceId, status: status, d1: d1, d2: d2)

                        // 2. Forward to Controller Manager / UI if source matches Controller Manager filter
                        if RaneMidiLearnService.shared.acceptsControllerMidi(fromSourceId: sourceId) {
                            DispatchQueue.main.async {
                                self.onMidiReceived?(status, d1, d2)
                            }
                        }
                    }
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }
}
