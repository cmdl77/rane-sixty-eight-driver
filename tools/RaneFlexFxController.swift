/* SPDX-License-Identifier: MIT */
/* RaneFlexFxController.swift - Dedicated Hardware FlexFX DSP Controller for Rane Sixty-Eight */

import Cocoa
import CoreMIDI

// MARK: - Protocol Constants
enum RaneProtocol {
    static let manufacturerId: UInt8 = 0x17
    static let sysExStart: UInt8 = 0xF0
    static let sysExEnd: UInt8 = 0xF7

    enum Opcode {
        static let getAllControls: UInt8 = 0x04
        static let bulkLedMatrix: UInt8 = 0x09
        static let dspFxParams: UInt8 = 0x18
        static let audioUnmute: UInt8 = 0x52
        static let audioMute: UInt8 = 0x53
    }

    enum FX {
        static let filter: UInt8  = 0x0C // 12
        static let flanger: UInt8 = 0x0B // 11
        static let phaser: UInt8  = 0x0A // 10
        static let echo: UInt8    = 0x0D // 13
        static let robot: UInt8   = 0x09 // 9
        static let reverb: UInt8  = 0x08 // 8

        static let beatUp: UInt8   = 0x0E // 14
        static let beatDown: UInt8 = 0x0F // 15
        static let tap: UInt8      = 0x05 // 5

        static let fxButton: UInt8    = 0x00
        static let fxCueButton: UInt8 = 0x04
        static let fxEncoderButton: UInt8 = 0x02

        static let timeEncoderCC: UInt8 = 0x14 // 20
        static let loopLevelCC: UInt8   = 0x60 // 96
    }

    enum Routing {
        static let pgm1: UInt8 = 0x52 // 82
        static let pgm2: UInt8 = 0x54 // 84
        static let pgm3: UInt8 = 0x56 // 86
        static let pgm4: UInt8 = 0x50 // 80
        static let mic1: UInt8 = 0x27 // 39
        static let mic2: UInt8 = 0x21 // 33
        static let extInsert: UInt8 = 0x26 // 38
        static let usbInsert: UInt8 = 0x20 // 32
    }
}

// MARK: - Controller Window
class FlexFxWindowController: NSWindowController, NSWindowDelegate {
    private var midiClient: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    private var inPort: MIDIPortRef = 0
    private var destEndpoint: MIDIEndpointRef = 0
    private var srcEndpoint: MIDIEndpointRef = 0

    // UI Elements
    private let statusLabel = NSTextField(labelWithString: "● OFFLINE - Searching Rane Sixty-Eight...")
    private let logTextView = NSTextView()
    private var effectButtons: [UInt8: NSButton] = [:]
    private var routingButtons: [UInt8: NSButton] = [:]
    private var fxOnButton = NSButton()
    private var fxCueButton = NSButton()
    private var timeSlider = NSSlider()
    private var timeLabel = NSTextField(labelWithString: "0")
    private var loopLevelSlider = NSSlider()
    private var loopLevelLabel = NSTextField(labelWithString: "100%")

    // State tracking
    private var activeEffect: UInt8? = nil
    private var routingStates: [UInt8: Bool] = [:]
    private var isFxOn: Bool = false
    private var isFxCueOn: Bool = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rane Sixty-Eight - Hardware FlexFX DSP Controller"
        window.minSize = NSSize(width: 860, height: 680)
        self.init(window: window)
        window.delegate = self
        setupUI()
        setupMIDI()
    }

    private func setupUI() {
        guard let window = window else { return }

        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView = visualEffect

        let mainScroll = NSScrollView(frame: visualEffect.bounds)
        mainScroll.autoresizingMask = [.width, .height]
        mainScroll.hasVerticalScroller = true
        mainScroll.drawsBackground = false
        visualEffect.addSubview(mainScroll)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))

        // Header
        let titleLabel = NSTextField(labelWithString: "RANE SIXTY-EIGHT")
        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.15, alpha: 1.0)
        titleLabel.frame = NSRect(x: 24, y: 650, width: 300, height: 28)
        content.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "HARDWARE FLEXFX DSP MASTER CONTROLLER")
        subtitleLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 24, y: 634, width: 400, height: 16)
        content.addSubview(subtitleLabel)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .systemRed
        statusLabel.frame = NSRect(x: 440, y: 648, width: 320, height: 22)
        content.addSubview(statusLabel)

        let syncBtn = createActionButton(title: "SYNC (0x04)", x: 770, y: 642, width: 110, color: .systemBlue)
        syncBtn.target = self
        syncBtn.action = #selector(onSyncClicked)
        content.addSubview(syncBtn)

        // 1. SECTION: DSP EFFECT SELECTION (6 Internal Effects)
        let fxBox = NSBox(frame: NSRect(x: 20, y: 470, width: 860, height: 150))
        fxBox.title = "INTERNAL DSP EFFECTS (HARDWARE ENGINE)"
        fxBox.titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let fxView = NSView(frame: fxBox.contentView!.bounds)

        let effects: [(name: String, note: UInt8, color: NSColor)] = [
            ("FILTER", RaneProtocol.FX.filter, .systemTeal),
            ("FLANGER", RaneProtocol.FX.flanger, .systemPurple),
            ("PHASER", RaneProtocol.FX.phaser, .systemIndigo),
            ("ECHO", RaneProtocol.FX.echo, .systemGreen),
            ("ROBOT", RaneProtocol.FX.robot, .systemOrange),
            ("REVERB", RaneProtocol.FX.reverb, .systemYellow)
        ]

        var fxX: CGFloat = 20
        for fx in effects {
            let btn = NSButton(frame: NSRect(x: fxX, y: 55, width: 125, height: 50))
            btn.title = fx.name
            btn.bezelStyle = .regularSquare
            btn.isBordered = true
            btn.font = NSFont.systemFont(ofSize: 14, weight: .black)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 8
            btn.layer?.borderWidth = 2
            btn.layer?.borderColor = fx.color.withAlphaComponent(0.4).cgColor
            btn.tag = Int(fx.note)
            btn.target = self
            btn.action = #selector(onEffectClicked(_:))
            effectButtons[fx.note] = btn
            fxView.addSubview(btn)
            fxX += 138
        }

        // Action Buttons under FX: Master FX ON / CUE
        fxOnButton = NSButton(frame: NSRect(x: 20, y: 12, width: 190, height: 34))
        fxOnButton.title = "⚡ MASTER FLEXFX ON"
        fxOnButton.bezelStyle = .regularSquare
        fxOnButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        fxOnButton.wantsLayer = true
        fxOnButton.layer?.cornerRadius = 6
        fxOnButton.target = self
        fxOnButton.action = #selector(onMasterFxToggle)
        fxView.addSubview(fxOnButton)

        fxCueButton = NSButton(frame: NSRect(x: 220, y: 12, width: 160, height: 34))
        fxCueButton.title = "🎧 FX HEADPHONE CUE"
        fxCueButton.bezelStyle = .regularSquare
        fxCueButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        fxCueButton.wantsLayer = true
        fxCueButton.layer?.cornerRadius = 6
        fxCueButton.target = self
        fxCueButton.action = #selector(onFxCueToggle)
        fxView.addSubview(fxCueButton)

        let clearLedsBtn = createActionButton(title: "CLEAR ALL LEDS (0x09)", x: 670, y: 12, width: 170, color: .systemGray)
        clearLedsBtn.target = self
        clearLedsBtn.action = #selector(onClearLedsClicked)
        fxView.addSubview(clearLedsBtn)

        fxBox.contentView = fxView
        content.addSubview(fxBox)

        // 2. SECTION: BEAT DIVISIONS & TIMING
        let timingBox = NSBox(frame: NSRect(x: 20, y: 320, width: 420, height: 140))
        timingBox.title = "BEAT SYNC & TIME ENCODER"
        timingBox.titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let timingView = NSView(frame: timingBox.contentView!.bounds)

        let beatDownBtn = createActionButton(title: "◀ BEAT DOWN", x: 15, y: 65, width: 120, color: .systemBlue)
        beatDownBtn.target = self
        beatDownBtn.action = #selector(onBeatDownClicked)
        timingView.addSubview(beatDownBtn)

        let beatUpBtn = createActionButton(title: "BEAT UP ▶", x: 145, y: 65, width: 120, color: .systemBlue)
        beatUpBtn.target = self
        beatUpBtn.action = #selector(onBeatUpClicked)
        timingView.addSubview(beatUpBtn)

        let tapBtn = createActionButton(title: "TAP TEMPO", x: 275, y: 65, width: 115, color: .systemOrange)
        tapBtn.target = self
        tapBtn.action = #selector(onTapClicked)
        timingView.addSubview(tapBtn)

        let timeTitle = NSTextField(labelWithString: "FX Time / Parameter (CC #20):")
        timeTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        timeTitle.frame = NSRect(x: 15, y: 22, width: 180, height: 16)
        timingView.addSubview(timeTitle)

        timeSlider.frame = NSRect(x: 195, y: 18, width: 160, height: 24)
        timeSlider.minValue = 0
        timeSlider.maxValue = 127
        timeSlider.intValue = 64
        timeSlider.target = self
        timeSlider.action = #selector(onTimeSliderChanged(_:))
        timingView.addSubview(timeSlider)

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        timeLabel.frame = NSRect(x: 365, y: 22, width: 40, height: 16)
        timeLabel.stringValue = "64"
        timingView.addSubview(timeLabel)

        timingBox.contentView = timingView
        content.addSubview(timingBox)

        // 3. SECTION: RETURN LEVEL & DRY/WET
        let levelBox = NSBox(frame: NSRect(x: 460, y: 320, width: 420, height: 140))
        levelBox.title = "FLEXFX RETURN / LOOP LEVEL"
        levelBox.titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let levelView = NSView(frame: levelBox.contentView!.bounds)

        let loopLevelTitle = NSTextField(labelWithString: "Return Level (CC #96):")
        loopLevelTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        loopLevelTitle.frame = NSRect(x: 20, y: 70, width: 160, height: 18)
        levelView.addSubview(loopLevelTitle)

        loopLevelSlider.frame = NSRect(x: 20, y: 35, width: 300, height: 28)
        loopLevelSlider.minValue = 0
        loopLevelSlider.maxValue = 127
        loopLevelSlider.intValue = 100
        loopLevelSlider.target = self
        loopLevelSlider.action = #selector(onLoopLevelSliderChanged(_:))
        levelView.addSubview(loopLevelSlider)

        loopLevelLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .black)
        loopLevelLabel.frame = NSRect(x: 330, y: 38, width: 60, height: 20)
        loopLevelLabel.stringValue = "100"
        levelView.addSubview(loopLevelLabel)

        levelBox.contentView = levelView
        content.addSubview(levelBox)

        // 4. SECTION: ROUTING MATRIX (Channel Sends)
        let routingBox = NSBox(frame: NSRect(x: 20, y: 190, width: 860, height: 120))
        routingBox.title = "FLEXFX CHANNEL ROUTING (WHERE EFFECTS ARE INSERTED)"
        routingBox.titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let routingView = NSView(frame: routingBox.contentView!.bounds)

        let channels: [(title: String, note: UInt8)] = [
            ("PGM 1", RaneProtocol.Routing.pgm1),
            ("PGM 2", RaneProtocol.Routing.pgm2),
            ("PGM 3", RaneProtocol.Routing.pgm3),
            ("PGM 4", RaneProtocol.Routing.pgm4),
            ("MIC 1", RaneProtocol.Routing.mic1),
            ("MIC 2", RaneProtocol.Routing.mic2),
            ("EXT INSERT", RaneProtocol.Routing.extInsert),
            ("USB INSERT", RaneProtocol.Routing.usbInsert)
        ]

        var rX: CGFloat = 15
        for ch in channels {
            let btn = NSButton(frame: NSRect(x: rX, y: 25, width: 95, height: 50))
            btn.title = ch.title
            btn.bezelStyle = .regularSquare
            btn.isBordered = true
            btn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.tag = Int(ch.note)
            btn.target = self
            btn.action = #selector(onRoutingClicked(_:))
            routingButtons[ch.note] = btn
            routingStates[ch.note] = false
            updateRoutingButtonStyle(btn, active: false)
            routingView.addSubview(btn)
            rX += 105
        }

        routingBox.contentView = routingView
        content.addSubview(routingBox)

        // 5. SECTION: LIVE MIDI / SYSEX MONITOR
        let logBox = NSBox(frame: NSRect(x: 20, y: 15, width: 860, height: 165))
        logBox.title = "LIVE HARDWARE EVENT LOG (MIDI IN & OUT)"
        logBox.titleFont = NSFont.systemFont(ofSize: 11, weight: .bold)

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 840, height: 125))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        logTextView.isEditable = false
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1.0)
        logTextView.textColor = NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)
        scroll.documentView = logTextView
        logBox.contentView = scroll
        content.addSubview(logBox)

        mainScroll.documentView = content
    }

    private func createActionButton(title: String, x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor) -> NSButton {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: width, height: 30))
        btn.title = title
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        btn.wantsLayer = true
        return btn
    }

    // MARK: - CoreMIDI Setup
    private func setupMIDI() {
        let notifyProc: MIDINotifyProc = { _, refCon in
            guard let refCon = refCon else { return }
            let ctrl = Unmanaged<FlexFxWindowController>.fromOpaque(refCon).takeUnretainedValue()
            DispatchQueue.main.async { ctrl.connectEndpoints() }
        }

        var status = MIDIClientCreate("FlexFxTestClient" as CFString, notifyProc, Unmanaged.passUnretained(self).toOpaque(), &midiClient)
        if status != noErr { appendLog("ERROR: MIDIClientCreate failed: \(status)"); return }

        status = MIDIOutputPortCreate(midiClient, "FlexFxOut" as CFString, &outPort)
        if status != noErr { appendLog("ERROR: MIDIOutputPortCreate failed: \(status)"); return }

        let readProc: MIDIReadProc = { pktList, readRefCon, _ in
            guard let refCon = readRefCon else { return }
            let ctrl = Unmanaged<FlexFxWindowController>.fromOpaque(refCon).takeUnretainedValue()
            ctrl.processIncomingPackets(pktList)
        }

        status = MIDIInputPortCreate(midiClient, "FlexFxIn" as CFString, readProc, Unmanaged.passUnretained(self).toOpaque(), &inPort)
        connectEndpoints()
    }

    private func connectEndpoints() {
        let numDests = MIDIGetNumberOfDestinations()
        for i in 0..<numDests {
            let d = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(d, kMIDIPropertyName, &name)
            if let str = name?.takeRetainedValue() as String?, str.contains("Sixty-Eight") {
                destEndpoint = d
                break
            }
        }

        let numSrcs = MIDIGetNumberOfSources()
        for i in 0..<numSrcs {
            let s = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(s, kMIDIPropertyName, &name)
            if let str = name?.takeRetainedValue() as String?, str.contains("Sixty-Eight") {
                srcEndpoint = s
                MIDIPortConnectSource(inPort, s, nil)
                break
            }
        }

        if destEndpoint != 0 {
            statusLabel.stringValue = "● ONLINE - Connected to Rane Sixty-Eight"
            statusLabel.textColor = .systemGreen
            appendLog("Connected to Rane Sixty-Eight MIDI endpoints.")
            // Instant Unmute & Sync
            sendUnmute()
            onSyncClicked()
        } else {
            statusLabel.stringValue = "● OFFLINE - Rane Sixty-Eight not found"
            statusLabel.textColor = .systemRed
        }
    }

    // MARK: - MIDI Transmission
    private func sendMidiPacket(_ bytes: [UInt8]) {
        guard destEndpoint != 0 else { return }
        var packet = MIDIPacket()
        packet.length = UInt16(min(bytes.count, 256))
        packet.timeStamp = 0
        withUnsafeMutableBytes(of: &packet.data) { ptr in
            for i in 0..<Int(packet.length) { ptr[i] = bytes[i] }
        }
        var list = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(outPort, destEndpoint, &list)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        appendLog(">> SEND: \(hex)")
    }

    private func sendNote(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        let st = (velocity > 0 ? 0x90 : 0x80) | (channel & 0x0F)
        sendMidiPacket([st, note & 0x7F, velocity & 0x7F])
    }

    private func sendCC(cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        let st = 0xB0 | (channel & 0x0F)
        sendMidiPacket([st, cc & 0x7F, value & 0x7F])
    }

    private func sendUnmute() {
        sendMidiPacket([RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.audioUnmute, 0x00, RaneProtocol.sysExEnd])
    }

    // MARK: - Actions
    @objc private func onEffectClicked(_ sender: NSButton) {
        let note = UInt8(sender.tag)
        activeEffect = note

        // Update button visual states
        for (n, btn) in effectButtons {
            if n == note {
                btn.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.4).cgColor
                btn.layer?.borderColor = NSColor.systemOrange.cgColor
            } else {
                btn.layer?.backgroundColor = NSColor.clear.cgColor
                btn.layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor
            }
        }

        // Send hardware Note trigger
        sendNote(note: note, velocity: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendNote(note: note, velocity: 0)
        }
    }

    @objc private func onMasterFxToggle() {
        isFxOn.toggle()
        updateToggleStyle(fxOnButton, active: isFxOn, activeColor: .systemGreen, title: isFxOn ? "⚡ MASTER FLEXFX ACTIVE" : "⚡ MASTER FLEXFX ON")
        // Send hardware trigger Note 0
        sendNote(note: RaneProtocol.FX.fxButton, velocity: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendNote(note: RaneProtocol.FX.fxButton, velocity: 0)
        }
    }

    @objc private func onFxCueToggle() {
        isFxCueOn.toggle()
        updateToggleStyle(fxCueButton, active: isFxCueOn, activeColor: .systemYellow, title: isFxCueOn ? "🎧 FX CUE ACTIVE" : "🎧 FX HEADPHONE CUE")
        sendNote(note: RaneProtocol.FX.fxCueButton, velocity: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendNote(note: RaneProtocol.FX.fxCueButton, velocity: 0)
        }
    }

    @objc private func onBeatDownClicked() {
        sendNote(note: RaneProtocol.FX.beatDown, velocity: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendNote(note: RaneProtocol.FX.beatDown, velocity: 0)
        }
    }

    @objc private func onBeatUpClicked() {
        sendNote(note: RaneProtocol.FX.beatUp, velocity: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendNote(note: RaneProtocol.FX.beatUp, velocity: 0)
        }
    }

    @objc private func onTapClicked() {
        sendNote(note: RaneProtocol.FX.tap, velocity: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendNote(note: RaneProtocol.FX.tap, velocity: 0)
        }
    }

    @objc private func onTimeSliderChanged(_ sender: NSSlider) {
        let val = UInt8(sender.intValue)
        timeLabel.stringValue = "\(val)"
        sendCC(cc: RaneProtocol.FX.timeEncoderCC, value: val)
    }

    @objc private func onLoopLevelSliderChanged(_ sender: NSSlider) {
        let val = UInt8(sender.intValue)
        loopLevelLabel.stringValue = "\(val)"
        sendCC(cc: RaneProtocol.FX.loopLevelCC, value: val)
    }

    @objc private func onRoutingClicked(_ sender: NSButton) {
        let note = UInt8(sender.tag)
        let newState = !(routingStates[note] ?? false)
        routingStates[note] = newState
        updateRoutingButtonStyle(sender, active: newState)

        // Send hardware Note trigger
        sendNote(note: note, velocity: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendNote(note: note, velocity: 0)
        }
    }

    @objc private func onSyncClicked() {
        appendLog("Requesting full hardware dump (Opcode 0x04)...")
        sendMidiPacket([RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.getAllControls, RaneProtocol.sysExEnd])
    }

    @objc private func onClearLedsClicked() {
        appendLog("Clearing all LEDs via Bulk Matrix (Opcode 0x09)...")
        var msg = [RaneProtocol.sysExStart, RaneProtocol.manufacturerId, RaneProtocol.Opcode.bulkLedMatrix]
        msg.append(contentsOf: [UInt8](repeating: 0, count: 9))
        msg.append(RaneProtocol.sysExEnd)
        sendMidiPacket(msg)
    }

    private func updateRoutingButtonStyle(_ btn: NSButton, active: Bool) {
        btn.wantsLayer = true
        if active {
            btn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.4).cgColor
            btn.layer?.borderColor = NSColor.systemGreen.cgColor
            btn.layer?.borderWidth = 2
        } else {
            btn.layer?.backgroundColor = NSColor.clear.cgColor
            btn.layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor
            btn.layer?.borderWidth = 1
        }
    }

    private func updateToggleStyle(_ btn: NSButton, active: Bool, activeColor: NSColor, title: String) {
        btn.title = title
        if active {
            btn.layer?.backgroundColor = activeColor.withAlphaComponent(0.4).cgColor
            btn.layer?.borderColor = activeColor.cgColor
            btn.layer?.borderWidth = 2
        } else {
            btn.layer?.backgroundColor = NSColor.clear.cgColor
            btn.layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor
            btn.layer?.borderWidth = 1
        }
    }

    // MARK: - Incoming Packet Processing
    private func processIncomingPackets(_ pktList: UnsafePointer<MIDIPacketList>) {
        var p = pktList.pointee.packet
        for _ in 0..<pktList.pointee.numPackets {
            let len = Int(p.length)
            let m = Mirror(reflecting: p.data)
            let b: [UInt8] = m.children.prefix(len).map { $0.value as! UInt8 }

            // Filter heartbeat CC #86
            if !(len == 3 && b[0] == 0xB0 && b[1] == 0x56) {
                let hex = b.map { String(format: "%02X", $0) }.joined(separator: " ")
                DispatchQueue.main.async {
                    self.appendLog("<< RECV [\(len)b]: \(hex)")
                    self.handleIncomingHardwareMessage(b)
                }
            }
            p = MIDIPacketNext(&p).pointee
        }
    }

    private func handleIncomingHardwareMessage(_ b: [UInt8]) {
        guard !b.isEmpty else { return }
        let status = b[0]

        // Control Change (CC)
        if (status & 0xF0) == 0xB0 && b.count >= 3 {
            let cc = b[1]
            let val = b[2]
            if cc == RaneProtocol.FX.timeEncoderCC {
                timeSlider.intValue = Int32(val)
                timeLabel.stringValue = "\(val)"
            } else if cc == RaneProtocol.FX.loopLevelCC {
                loopLevelSlider.intValue = Int32(val)
                loopLevelLabel.stringValue = "\(val)"
            }
        }
        // Note On (Channel 1: 0x90 or Channel 2: 0x91)
        else if (status & 0xF0) == 0x90 && b.count >= 3 {
            let ch = status & 0x0F
            let note = b[1]
            let vel = b[2]

            if ch == 1 { // Channel 2 (Mix Functions feedback from dump)
                if note == 0x01 { // FX On
                    isFxOn = (vel > 0)
                    updateToggleStyle(fxOnButton, active: isFxOn, activeColor: .systemGreen, title: isFxOn ? "⚡ MASTER FLEXFX ACTIVE" : "⚡ MASTER FLEXFX ON")
                } else if note == 0x03 { // FX Cue
                    isFxCueOn = (vel > 0)
                    updateToggleStyle(fxCueButton, active: isFxCueOn, activeColor: .systemYellow, title: isFxCueOn ? "🎧 FX CUE ACTIVE" : "🎧 FX HEADPHONE CUE")
                } else if let btn = routingButtons[note] {
                    routingStates[note] = (vel > 0)
                    updateRoutingButtonStyle(btn, active: vel > 0)
                }
            }
        }
    }

    private func appendLog(_ text: String) {
        DispatchQueue.main.async {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            let line = "[\(df.string(from: Date()))] \(text)\n"
            let attrStr = NSAttributedString(string: line, attributes: [
                .foregroundColor: NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.4, alpha: 1.0),
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            ])
            guard let storage = self.logTextView.textStorage else { return }
            if storage.length > 50000 {
                storage.deleteCharacters(in: NSRange(location: 0, length: 20000))
            }
            storage.append(attrStr)
            let len = storage.length
            self.logTextView.scrollRangeToVisible(NSRange(location: len, length: 0))
            self.logTextView.scrollToEndOfDocument(nil)
        }
    }
}

// MARK: - App Delegate & Main
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: FlexFxWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = FlexFxWindowController()
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
