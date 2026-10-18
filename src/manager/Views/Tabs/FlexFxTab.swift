/* SPDX-License-Identifier: MIT */
/* FlexFxTab.swift - 3-Bus Parallel Audio Signal-Flow & MIDI-Control Matrix with VST/AU MIDI & Clock Sync */

import Cocoa

extension MainWindowController {
    // MARK: - FlexFX UI State & References
    struct FlexFxUiReferences {
        var channelSegmentedControl: NSSegmentedControl!
        var modulePowerSwitch: NSSwitch!
        var moduleStatusBadge: NSTextField!
        var midiLearnToggleButton: NSButton!
        var fxControlsContainer: NSView!

        // Top OLED Bar (Pure BPM Display, Tempo Control & Ableton Link)
        var oledDisplay: NSView!
        var oledBpmLabel: NSTextField!
        var oledClockBadge: NSTextField!
        var oledLinkBadge: NSTextField!
        var beatDots: [NSView] = []
        var tempoSlider: NSSlider!
        var tempoBadge: NSTextField!
        var linkButton: NSButton!

        // Left / Right Record / Playback Columns (Removed in 5-channel direct DAW architecture)
        var usbRecordPopup: NSPopUpButton?
        var usbRecordChannelBadge: NSTextField?
        var usbRecordMeterFill: NSLayoutConstraint?
        var usbPlaybackPopup: NSPopUpButton?
        var usbPlaybackChannelBadge: NSTextField?
        var prePostButton: NSButton?

        // 6 Gain Faders (3x Pre-Gain + 3x Post-Gain)
        var fx1PreGainSlider: NSSlider!
        var fx1PreGainBadge: NSTextField!
        var fx2PreGainSlider: NSSlider!
        var fx2PreGainBadge: NSTextField!
        var dryPreGainSlider: NSSlider!
        var dryPreGainBadge: NSTextField!

        var fx1PostGainSlider: NSSlider!
        var fx1PostGainBadge: NSTextField!
        var fx2PostGainSlider: NSSlider!
        var fx2PostGainBadge: NSTextField!
        var dryPostGainSlider: NSSlider!
        var dryPostGainBadge: NSTextField!

        // Proportional Dry Pre-Gain Ducking Controls (VST 1 & VST 2 -> Dry Pre-Gain)
        var fx1DryDuckSlider: NSSlider!
        var fx1DryDuckBadge: NSTextField!
        var fx2DryDuckSlider: NSSlider!
        var fx2DryDuckBadge: NSTextField!
        var dryBaseInfoBadge: NSTextField!

        // Center Bus Rows: VST Effekt 1 (Slot 0), VST Effekt 2 (Slot 1), Dry Path
        var vstToggleButtons: [Int: NSButton] = [:]
        var vstUiButtons: [Int: NSButton] = [:]
        var vstPluginPopups: [Int: NSPopUpButton] = [:]
        var vstMidiSourcePopups: [Int: NSPopUpButton] = [:]
        var vstMidiChannelPopups: [Int: NSPopUpButton] = [:]
        var vstMidiClockCheckboxes: [Int: NSButton] = [:]
        var vstMidiStatusLabels: [Int: NSTextField] = [:]

        // Interactive MIDI Learn Badges (Per-Channel & Global)
        var channelMidiLearnButtons: [ChannelControlType: NSButton] = [:]
        var midiLearnButtons: [FlexFxMidiTarget: NSButton] = [:]

        var rescanPluginsButton: NSButton!
    }

    private static var flexFxRefs = FlexFxUiReferences()

    func buildFlexFxPage() -> NSView {
        Self.flexFxRefs.vstToggleButtons.removeAll()
        Self.flexFxRefs.vstUiButtons.removeAll()
        Self.flexFxRefs.vstPluginPopups.removeAll()
        Self.flexFxRefs.vstMidiSourcePopups.removeAll()
        Self.flexFxRefs.vstMidiChannelPopups.removeAll()
        Self.flexFxRefs.vstMidiClockCheckboxes.removeAll()
        Self.flexFxRefs.vstMidiStatusLabels.removeAll()
        Self.flexFxRefs.channelMidiLearnButtons.removeAll()
        Self.flexFxRefs.midiLearnButtons.removeAll()

        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 8
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let sec1Outer = NSStackView()
        sec1Outer.orientation = .vertical
        sec1Outer.alignment = .leading
        sec1Outer.spacing = 8

        // =========================================================================
        // TOP HEADER BAR: Title, MIDI Learn Mode, VST Scan & Module Master Switch
        // =========================================================================
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        }
        iconView.contentTintColor = .systemYellow
        topBar.addArrangedSubview(iconView)

        let titleLabel = NSTextField(labelWithString: Localization.tr(
            en: "FlexFX Parallel Signal-Flow & VST/MIDI Matrix",
            de: "FlexFX Parallel-Signalfluß & VST/MIDI-Matrix"
        ))
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = NSColor(white: 0.92, alpha: 1.0)
        topBar.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topBar.addArrangedSubview(spacer)

        // Interactive MIDI Learn Toggle
        let learnBtn = NSButton(
            title: "🎹 MIDI Learn: AUS",
            target: self,
            action: #selector(onFlexFxMidiLearnModeToggled(_:))
        )
        learnBtn.bezelStyle = .inline
        learnBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        learnBtn.wantsLayer = true
        learnBtn.layer?.cornerRadius = 5
        learnBtn.layer?.borderWidth = 1.0
        learnBtn.translatesAutoresizingMaskIntoConstraints = false
        learnBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        topBar.addArrangedSubview(learnBtn)
        Self.flexFxRefs.midiLearnToggleButton = learnBtn

        // Rescan Plugins Button
        let rescanBtn = NSButton(
            title: Localization.tr(en: "🔄 Scan VST", de: "🔄 VST scannen"),
            target: self,
            action: #selector(onRescanPluginsClicked(_:))
        )
        rescanBtn.bezelStyle = .inline
        rescanBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        rescanBtn.wantsLayer = true
        rescanBtn.layer?.cornerRadius = 5
        rescanBtn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.85).cgColor
        rescanBtn.contentTintColor = NSColor.white
        rescanBtn.translatesAutoresizingMaskIntoConstraints = false
        rescanBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        topBar.addArrangedSubview(rescanBtn)
        Self.flexFxRefs.rescanPluginsButton = rescanBtn

        // Master Switch for Module Power
        let pwrLabel = NSTextField(labelWithString: Localization.tr(en: "Power:", de: "Modul:"))
        pwrLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        pwrLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        topBar.addArrangedSubview(pwrLabel)

        let pwrSwitch = NSSwitch()
        pwrSwitch.controlSize = .small
        pwrSwitch.state = RaneFlexFxService.shared.isModuleEnabled ? .on : .off
        pwrSwitch.target = self
        pwrSwitch.action = #selector(onModulePowerToggled(_:))
        topBar.addArrangedSubview(pwrSwitch)
        Self.flexFxRefs.modulePowerSwitch = pwrSwitch

        let statusBadge = NSTextField(labelWithString: " ● AKTIV ")
        statusBadge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        statusBadge.textColor = NSColor.systemGreen
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 4
        statusBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
        topBar.addArrangedSubview(statusBadge)
        Self.flexFxRefs.moduleStatusBadge = statusBadge

        sec1Outer.addArrangedSubview(topBar)
        topBar.widthAnchor.constraint(equalTo: sec1Outer.widthAnchor).isActive = true

        // =========================================================================
        // CHANNEL STRIP SELECTOR: PGM 1 (Deck 1) .. PGM 4 (Deck 4) & FLEXFX RETURN
        // =========================================================================
        let chSegment = NSSegmentedControl(labels: [
            "🎛️ PGM 1 (Deck 1)",
            "🎛️ PGM 2 (Deck 2)",
            "🎛️ PGM 3 (Deck 3)",
            "🎛️ PGM 4 (Deck 4)",
            "🔁 FlexFX (Return)"
        ], trackingMode: .selectOne, target: self, action: #selector(onChannelStripSelected(_:)))
        chSegment.selectedSegment = RaneFlexFxService.shared.selectedChannelIndex
        chSegment.segmentDistribution = .fillEqually
        chSegment.controlSize = .regular
        chSegment.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        chSegment.translatesAutoresizingMaskIntoConstraints = false
        chSegment.heightAnchor.constraint(equalToConstant: 28).isActive = true
        sec1Outer.addArrangedSubview(chSegment)
        chSegment.widthAnchor.constraint(equalTo: sec1Outer.widthAnchor).isActive = true
        Self.flexFxRefs.channelSegmentedControl = chSegment

        let fxCardStack = NSStackView()
        fxCardStack.orientation = .vertical
        fxCardStack.alignment = .leading
        fxCardStack.spacing = 10

        // =========================================================================
        // SECTION A: PURE BPM DISPLAY, TEMPO CONTROL & ABLETON LINK (OLED BAR)
        // =========================================================================
        let oledBar = createTempoAndLinkOledBar()
        fxCardStack.addArrangedSubview(oledBar)
        oledBar.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        // =========================================================================
        // SECTION B: 3-BUS PARALLEL AUDIO SIGNAL-FLOW & MIDI-CONTROL MATRIX
        // =========================================================================
        let matrixSection = createParallelSignalFlowMatrix()
        fxCardStack.addArrangedSubview(matrixSection)
        matrixSection.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        Self.flexFxRefs.fxControlsContainer = fxCardStack

        let topCard = fxCardStack.wrapInCard(
            cornerRadius: 10,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.14, green: 0.145, blue: 0.165, alpha: 1.0),
            padding: NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        )
        sec1Outer.addArrangedSubview(topCard)
        topCard.widthAnchor.constraint(equalTo: sec1Outer.widthAnchor).isActive = true

        let sec1Inset = sec1Outer.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        )
        page.addArrangedSubview(sec1Inset)
        sec1Inset.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        updateFlexFxUi()
        setupFlexFxCallbacks()

        return page
    }

    // MARK: - Section A: Pure BPM Display, Tempo Control & Ableton Link OLED Bar
    private func createTempoAndLinkOledBar() -> NSView {
        let oled = NSView()
        oled.wantsLayer = true
        oled.layer?.cornerRadius = 8
        oled.layer?.backgroundColor = NSColor(red: 0.04, green: 0.06, blue: 0.09, alpha: 1.0).cgColor
        oled.layer?.borderColor = NSColor(red: 0.18, green: 0.26, blue: 0.36, alpha: 0.85).cgColor
        oled.layer?.borderWidth = 1.5
        oled.translatesAutoresizingMaskIntoConstraints = false
        oled.heightAnchor.constraint(equalToConstant: 72).isActive = true
        Self.flexFxRefs.oledDisplay = oled

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        oled.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: oled.topAnchor),
            stack.bottomAnchor.constraint(equalTo: oled.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: oled.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: oled.trailingAnchor)
        ])

        // 1. LEFT: Pure BPM Readout & 4 Beat Phase Dots
        let bpmCol = NSStackView()
        bpmCol.orientation = .vertical
        bpmCol.alignment = .leading
        bpmCol.spacing = 3

        let bpmTopRow = NSStackView()
        bpmTopRow.orientation = .horizontal
        bpmTopRow.alignment = .centerY
        bpmTopRow.spacing = 8

        let bpmHeader = NSTextField(labelWithString: "MASTER TEMPO / CLOCK")
        bpmHeader.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        bpmHeader.textColor = NSColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 0.9)
        bpmTopRow.addArrangedSubview(bpmHeader)

        // 4 Beat Pulse Dots
        let dotsStack = NSStackView()
        dotsStack.orientation = .horizontal
        dotsStack.spacing = 5
        Self.flexFxRefs.beatDots.removeAll()
        for _ in 0..<4 {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = NSColor(white: 0.25, alpha: 0.6).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dotsStack.addArrangedSubview(dot)
            Self.flexFxRefs.beatDots.append(dot)
        }
        bpmTopRow.addArrangedSubview(dotsStack)
        bpmCol.addArrangedSubview(bpmTopRow)

        let bpmValueRow = NSStackView()
        bpmValueRow.orientation = .horizontal
        bpmValueRow.alignment = .lastBaseline
        bpmValueRow.spacing = 8

        let bpmLabel = NSTextField(labelWithString: "120.0 BPM")
        bpmLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .black)
        bpmLabel.textColor = NSColor(red: 0.20, green: 0.95, blue: 0.85, alpha: 1.0)
        bpmValueRow.addArrangedSubview(bpmLabel)
        Self.flexFxRefs.oledBpmLabel = bpmLabel

        let clockBadge = NSTextField(labelWithString: "🕒 MIDI CLOCK 24 PPQN")
        clockBadge.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        clockBadge.textColor = NSColor.systemYellow
        clockBadge.wantsLayer = true
        clockBadge.layer?.cornerRadius = 3
        clockBadge.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.14).cgColor
        bpmValueRow.addArrangedSubview(clockBadge)
        Self.flexFxRefs.oledClockBadge = clockBadge

        bpmCol.addArrangedSubview(bpmValueRow)
        stack.addArrangedSubview(bpmCol)

        // Vertical Divider inside OLED
        let vDiv1 = NSView()
        vDiv1.wantsLayer = true
        vDiv1.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
        vDiv1.translatesAutoresizingMaskIntoConstraints = false
        vDiv1.widthAnchor.constraint(equalToConstant: 1).isActive = true
        vDiv1.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(vDiv1)

        // 2. CENTER: Tempo Steuerung (Slider, Fine Nudge -/+, Tap Tempo, MIDI Learn)
        let tempoCol = NSStackView()
        tempoCol.orientation = .vertical
        tempoCol.alignment = .leading
        tempoCol.spacing = 5
        tempoCol.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let tempoTopRow = NSStackView()
        tempoTopRow.orientation = .horizontal
        tempoTopRow.alignment = .centerY
        tempoTopRow.spacing = 6

        let tempoTitle = NSTextField(labelWithString: "TEMPO-STEUERUNG:")
        tempoTitle.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        tempoTitle.textColor = NSColor(white: 0.75, alpha: 1.0)
        tempoTopRow.addArrangedSubview(tempoTitle)

        let minusBtn = NSButton(title: "−0.5", target: self, action: #selector(onTempoMinusClicked))
        minusBtn.bezelStyle = .inline
        minusBtn.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        minusBtn.wantsLayer = true
        minusBtn.layer?.cornerRadius = 3
        minusBtn.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.8).cgColor
        minusBtn.contentTintColor = .white
        tempoTopRow.addArrangedSubview(minusBtn)

        let plusBtn = NSButton(title: "+0.5", target: self, action: #selector(onTempoPlusClicked))
        plusBtn.bezelStyle = .inline
        plusBtn.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        plusBtn.wantsLayer = true
        plusBtn.layer?.cornerRadius = 3
        plusBtn.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.8).cgColor
        plusBtn.contentTintColor = .white
        tempoTopRow.addArrangedSubview(plusBtn)

        let tapBtn = NSButton(title: "TAP TEMPO", target: self, action: #selector(onTapTempoClicked))
        tapBtn.bezelStyle = .inline
        tapBtn.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        tapBtn.wantsLayer = true
        tapBtn.layer?.cornerRadius = 3
        tapBtn.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.22).cgColor
        tapBtn.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.7).cgColor
        tapBtn.layer?.borderWidth = 1.0
        tapBtn.contentTintColor = NSColor.systemTeal
        tempoTopRow.addArrangedSubview(tapBtn)

        let tempoLearnBtn = createMidiLearnBadgeButton(for: .tempo, compact: true)
        tempoTopRow.addArrangedSubview(tempoLearnBtn)

        tempoCol.addArrangedSubview(tempoTopRow)

        let sliderRow = NSStackView()
        sliderRow.orientation = .horizontal
        sliderRow.alignment = .centerY
        sliderRow.spacing = 8

        let tpSlider = RaneResettableSlider(value: RaneFlexFxService.shared.bpm, minValue: 60.0, maxValue: 200.0, defaultValue: 120.0, target: self, action: #selector(onTempoSliderChanged(_:)))
        tpSlider.isContinuous = true
        tpSlider.controlSize = .small
        tpSlider.toolTip = "Doppelklick: Nullstellung (120.0 BPM)"
        tpSlider.translatesAutoresizingMaskIntoConstraints = false
        tpSlider.widthAnchor.constraint(equalToConstant: 195).isActive = true
        sliderRow.addArrangedSubview(tpSlider)
        Self.flexFxRefs.tempoSlider = tpSlider

        let tpBadge = createValueBadge(text: String(format: "%.1f BPM", RaneFlexFxService.shared.bpm))
        sliderRow.addArrangedSubview(tpBadge)
        Self.flexFxRefs.tempoBadge = tpBadge

        tempoCol.addArrangedSubview(sliderRow)
        stack.addArrangedSubview(tempoCol)

        // Vertical Divider 2
        let vDiv2 = NSView()
        vDiv2.wantsLayer = true
        vDiv2.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
        vDiv2.translatesAutoresizingMaskIntoConstraints = false
        vDiv2.widthAnchor.constraint(equalToConstant: 1).isActive = true
        vDiv2.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(vDiv2)

        // 3. RIGHT: Ableton Link Sync
        let linkCol = NSStackView()
        linkCol.orientation = .vertical
        linkCol.alignment = .trailing
        linkCol.spacing = 4

        let linkBadge = NSTextField(labelWithString: "● ABLETON LINK: OFF")
        linkBadge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        linkBadge.textColor = NSColor(white: 0.65, alpha: 1.0)
        linkCol.addArrangedSubview(linkBadge)
        Self.flexFxRefs.oledLinkBadge = linkBadge

        let linkBtnRow = NSStackView()
        linkBtnRow.orientation = .horizontal
        linkBtnRow.alignment = .centerY
        linkBtnRow.spacing = 6

        let linkLearnBtn = createMidiLearnBadgeButton(for: .abletonLink, compact: true)
        linkBtnRow.addArrangedSubview(linkLearnBtn)

        let linkBtn = NSButton(title: " 🔗 Ableton Link ", target: self, action: #selector(onLinkToggleClicked))
        linkBtn.bezelStyle = .inline
        linkBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        linkBtn.wantsLayer = true
        linkBtn.layer?.cornerRadius = 5
        linkBtn.layer?.borderWidth = 1.0
        linkBtn.translatesAutoresizingMaskIntoConstraints = false
        linkBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        linkBtnRow.addArrangedSubview(linkBtn)
        Self.flexFxRefs.linkButton = linkBtn

        linkCol.addArrangedSubview(linkBtnRow)
        stack.addArrangedSubview(linkCol)

        return oled
    }

    // MARK: - Section B: 3-Bus Parallel Audio Signal-Flow & MIDI-Control Matrix
    private func createParallelSignalFlowMatrix() -> NSView {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6

        // Matrix Legend Header
        let headerBar = NSStackView()
        headerBar.orientation = .horizontal
        headerBar.alignment = .centerY
        headerBar.spacing = 10
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        let flowTitle = NSTextField(labelWithString: "AUDIO SIGNALFLUSS & MIDI STEUERUNG (VST-EFFEKT + DRY-SIGNAL)")
        flowTitle.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        flowTitle.textColor = NSColor(red: 0.95, green: 0.78, blue: 0.25, alpha: 1.0)
        headerBar.addArrangedSubview(flowTitle)

        let hSpacer = NSView()
        hSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerBar.addArrangedSubview(hSpacer)

        let hintLbl = NSTextField(labelWithString: "DAW-Signal wird direkt verarbeitet und latenzfrei auf den Mixer ausgegeben")
        hintLbl.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        hintLbl.textColor = NSColor(white: 0.60, alpha: 1.0)
        headerBar.addArrangedSubview(hintLbl)

        outer.addArrangedSubview(headerBar)
        headerBar.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true

        // 2 Signal Paths: PATH 1 (Dedicated VST Slot) + PATH 2 (Dry Pass-Through)
        let busesStack = NSStackView()
        busesStack.orientation = .vertical
        busesStack.alignment = .leading
        busesStack.spacing = 8
        busesStack.translatesAutoresizingMaskIntoConstraints = false
        busesStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // PATH 1: Pre-Gain -> VST Effekt (Kanal-Slot 0..4) -> Post-Gain
        let bus1Row = createVstParallelBusRow(
            slotIndex: 0,
            title: "VST EFFEKT",
            accentColor: NSColor(red: 1.0, green: 0.78, blue: 0.15, alpha: 1.0),
            preControl: .slot1PreGain,
            toggleControl: .slot1Toggle,
            postControl: .slot1PostGain,
            preSliderAction: #selector(onFx1PreGainChanged(_:)),
            toggleAction: #selector(onVst1ToggleClicked(_:)),
            postSliderAction: #selector(onFx1PostGainChanged(_:))
        )
        busesStack.addArrangedSubview(bus1Row)
        bus1Row.widthAnchor.constraint(equalTo: busesStack.widthAnchor).isActive = true

        // PATH 2: Dry Pre-Gain -> Direct Pass-Through Line + Ducking -> Dry Post-Gain
        let bus2Row = createDryParallelBusRow()
        busesStack.addArrangedSubview(bus2Row)
        bus2Row.widthAnchor.constraint(equalTo: busesStack.widthAnchor).isActive = true

        outer.addArrangedSubview(busesStack)
        busesStack.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true

        return outer
    }

    // MARK: - Parallel VST Bus Row (Pre-Gain -> VST Effect + MIDI Routing -> Post-Gain)
    private func createVstParallelBusRow(
        slotIndex: Int,
        title: String,
        accentColor: NSColor,
        preControl: ChannelControlType,
        toggleControl: ChannelControlType,
        postControl: ChannelControlType,
        preSliderAction: Selector,
        toggleAction: Selector,
        postSliderAction: Selector
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        // 1. PRE-GAIN FADER MODULE (Left)
        let preBox = createGainFaderBox(
            label: "PRE-GAIN",
            initialGain: RaneFlexFxService.shared.fx1PreGain,
            channelControl: preControl,
            action: preSliderAction,
            sliderOut: { slider, badge in
                Self.flexFxRefs.fx1PreGainSlider = slider
                Self.flexFxRefs.fx1PreGainBadge = badge
            }
        )
        row.addArrangedSubview(preBox)

        let arrow1 = NSTextField(labelWithString: "──►")
        arrow1.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        arrow1.textColor = accentColor.withAlphaComponent(0.85)
        row.addArrangedSubview(arrow1)

        // 2. CENTER VST EFFECT & MIDI ROUTING CARD
        let centerStack = NSStackView()
        centerStack.orientation = .vertical
        centerStack.alignment = .leading
        centerStack.spacing = 5
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        centerStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Top Row inside VST Card: [ON/OFF Toggle] + [MIDI Badge] + [Plugin Dropdown] + [🎛 UI Button]
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let onOffBtn = FxEffectButton(title: "\(title): ON", target: self, action: toggleAction)
        onOffBtn.bezelStyle = .regularSquare
        onOffBtn.isBordered = false
        onOffBtn.wantsLayer = true
        onOffBtn.layer?.cornerRadius = 5
        onOffBtn.layer?.borderWidth = 1.4
        onOffBtn.font = NSFont.systemFont(ofSize: 11, weight: .black)
        onOffBtn.tag = slotIndex
        onOffBtn.toolTip = "Linksklick: \(title) EIN/AUS • Rechtsklick: VST Editor öffnen"
        onOffBtn.translatesAutoresizingMaskIntoConstraints = false
        onOffBtn.widthAnchor.constraint(equalToConstant: 128).isActive = true
        onOffBtn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        onOffBtn.onRightClick = { [weak self] in
            guard self != nil else { return }
            let s = RaneFlexFxService.shared
            let actSlotIdx = s.activeChannel.slotIndex
            let slot = RanePluginHostService.shared.slots[actSlotIdx]
            if slot.isCustomPlugin && slot.isLoaded {
                RanePluginHostService.shared.openPluginUI(for: actSlotIdx)
            }
        }
        topRow.addArrangedSubview(onOffBtn)
        Self.flexFxRefs.vstToggleButtons[slotIndex] = onOffBtn

        let toggleLearnBtn = createChannelMidiLearnBadgeButton(for: toggleControl, compact: true)
        topRow.addArrangedSubview(toggleLearnBtn)

        // Plugin Selector Dropdown
        let pluginPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        pluginPopup.bezelStyle = .rounded
        pluginPopup.controlSize = .small
        pluginPopup.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        pluginPopup.tag = slotIndex
        pluginPopup.target = self
        pluginPopup.action = #selector(onPluginSelected(_:))
        pluginPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rebuildPluginMenu(for: pluginPopup, slotIndex: slotIndex)
        topRow.addArrangedSubview(pluginPopup)
        Self.flexFxRefs.vstPluginPopups[slotIndex] = pluginPopup

        // Open Native Plugin UI Button
        let uiBtn = NSButton(title: "🎛 Editor", target: self, action: #selector(onPluginUiButtonClicked(_:)))
        uiBtn.bezelStyle = .inline
        uiBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        uiBtn.wantsLayer = true
        uiBtn.layer?.cornerRadius = 4
        uiBtn.layer?.backgroundColor = NSColor(red: 0.16, green: 0.22, blue: 0.30, alpha: 0.95).cgColor
        uiBtn.layer?.borderColor = NSColor.cyan.withAlphaComponent(0.6).cgColor
        uiBtn.layer?.borderWidth = 1.0
        uiBtn.contentTintColor = NSColor.cyan
        uiBtn.tag = slotIndex
        uiBtn.translatesAutoresizingMaskIntoConstraints = false
        uiBtn.widthAnchor.constraint(equalToConstant: 64).isActive = true
        uiBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        topRow.addArrangedSubview(uiBtn)
        Self.flexFxRefs.vstUiButtons[slotIndex] = uiBtn

        centerStack.addArrangedSubview(topRow)
        topRow.widthAnchor.constraint(equalTo: centerStack.widthAnchor).isActive = true

        // Bottom Row inside VST Card: MIDI Input Device Selector, MIDI Channel, MIDI Clock & Live Activity
        let midiRow = NSStackView()
        midiRow.orientation = .horizontal
        midiRow.alignment = .centerY
        midiRow.spacing = 6
        midiRow.translatesAutoresizingMaskIntoConstraints = false

        let midiLbl = NSTextField(labelWithString: "🎹 MIDI-In:")
        midiLbl.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
        midiLbl.textColor = NSColor(white: 0.75, alpha: 1.0)
        midiRow.addArrangedSubview(midiLbl)

        let midiSourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        midiSourcePopup.controlSize = .small
        midiSourcePopup.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        midiSourcePopup.tag = slotIndex
        midiSourcePopup.target = self
        midiSourcePopup.action = #selector(onVstMidiSourceChanged(_:))
        midiSourcePopup.translatesAutoresizingMaskIntoConstraints = false
        midiSourcePopup.widthAnchor.constraint(equalToConstant: 155).isActive = true
        rebuildVstMidiSourceMenu(for: midiSourcePopup, slotIndex: slotIndex)
        midiRow.addArrangedSubview(midiSourcePopup)
        Self.flexFxRefs.vstMidiSourcePopups[slotIndex] = midiSourcePopup

        let midiChPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        midiChPopup.controlSize = .small
        midiChPopup.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        midiChPopup.tag = slotIndex
        midiChPopup.addItem(withTitle: "Alle Ch")
        for ch in 1...16 {
            midiChPopup.addItem(withTitle: "Ch \(ch)")
        }
        let savedCh = RanePluginHostService.shared.slots[slotIndex].midiChannelFilter
        midiChPopup.selectItem(at: min(16, max(0, savedCh)))
        midiChPopup.target = self
        midiChPopup.action = #selector(onVstMidiChannelChanged(_:))
        midiChPopup.translatesAutoresizingMaskIntoConstraints = false
        midiChPopup.widthAnchor.constraint(equalToConstant: 66).isActive = true
        midiRow.addArrangedSubview(midiChPopup)
        Self.flexFxRefs.vstMidiChannelPopups[slotIndex] = midiChPopup

        let clockCheck = NSButton(checkboxWithTitle: "MIDI Clock (BPM)", target: self, action: #selector(onVstMidiClockToggled(_:)))
        clockCheck.controlSize = .small
        clockCheck.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        clockCheck.tag = slotIndex
        clockCheck.state = RanePluginHostService.shared.slots[slotIndex].sendMidiClock ? .on : .off
        midiRow.addArrangedSubview(clockCheck)
        Self.flexFxRefs.vstMidiClockCheckboxes[slotIndex] = clockCheck

        let mSpacer = NSView()
        mSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        midiRow.addArrangedSubview(mSpacer)

        let midiActLabel = NSTextField(labelWithString: "🕒 Clock + MIDI aktiv")
        midiActLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        midiActLabel.textColor = NSColor(red: 0.30, green: 0.90, blue: 0.55, alpha: 0.9)
        midiRow.addArrangedSubview(midiActLabel)
        Self.flexFxRefs.vstMidiStatusLabels[slotIndex] = midiActLabel

        centerStack.addArrangedSubview(midiRow)
        midiRow.widthAnchor.constraint(equalTo: centerStack.widthAnchor).isActive = true

        let centerCard = centerStack.wrapInCard(
            cornerRadius: 7,
            borderColor: accentColor.withAlphaComponent(0.45),
            fillColor: NSColor(red: 0.11, green: 0.115, blue: 0.135, alpha: 1.0),
            padding: NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        )
        row.addArrangedSubview(centerCard)
        centerCard.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let arrow2 = NSTextField(labelWithString: "──►")
        arrow2.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        arrow2.textColor = accentColor.withAlphaComponent(0.85)
        row.addArrangedSubview(arrow2)

        // 3. POST-GAIN FADER MODULE (Right)
        let postBox = createGainFaderBox(
            label: "POST-GAIN",
            initialGain: RaneFlexFxService.shared.fx1PostGain,
            channelControl: postControl,
            action: postSliderAction,
            sliderOut: { slider, badge in
                Self.flexFxRefs.fx1PostGainSlider = slider
                Self.flexFxRefs.fx1PostGainBadge = badge
            }
        )
        row.addArrangedSubview(postBox)

        return row
    }

    // MARK: - Parallel Dry Bus Row (Dry Pre-Gain -> Direct Pass-Through Line -> Dry Post-Gain)
    private func createDryParallelBusRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let dryColor = NSColor(white: 0.80, alpha: 1.0)

        // 1. DRY PRE-GAIN FADER MODULE (Left)
        let preBox = createGainFaderBox(
            label: "DRY PRE-GAIN",
            initialGain: RaneFlexFxService.shared.dryPreGain,
            channelControl: .dryPreGain,
            action: #selector(onDryPreGainChanged(_:)),
            sliderOut: { slider, badge in
                Self.flexFxRefs.dryPreGainSlider = slider
                Self.flexFxRefs.dryPreGainBadge = badge
            }
        )
        row.addArrangedSubview(preBox)

        let arrow1 = NSTextField(labelWithString: "──►")
        arrow1.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        arrow1.textColor = dryColor.withAlphaComponent(0.8)
        row.addArrangedSubview(arrow1)

        // 2. CENTER DIRECT SIGNAL LINE & AUTO DRY-DUCKING CONTROLS (Dry / Bypass Bus)
        let centerVertStack = NSStackView()
        centerVertStack.orientation = .vertical
        centerVertStack.alignment = .leading
        centerVertStack.spacing = 5
        centerVertStack.translatesAutoresizingMaskIntoConstraints = false
        centerVertStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Top Row inside Dry Card: Signal Path Label + Base Level Badge + Reset/Mute Buttons
        let centerTopRow = NSStackView()
        centerTopRow.orientation = .horizontal
        centerTopRow.alignment = .centerY
        centerTopRow.spacing = 8
        centerTopRow.translatesAutoresizingMaskIntoConstraints = false

        let directLabel = NSTextField(labelWithString: "──── DIREKTER SIGNALPFAD (DRY / ORIGINAL-AUDIO) ────►")
        directLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
        directLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        directLabel.alignment = .left
        directLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        centerTopRow.addArrangedSubview(directLabel)

        let baseBadge = NSTextField(labelWithString: "Ausgang: \(formatGainBadge(RaneFlexFxService.shared.dryBasePreGain))")
        baseBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        baseBadge.textColor = NSColor(white: 0.72, alpha: 1.0)
        centerTopRow.addArrangedSubview(baseBadge)
        Self.flexFxRefs.dryBaseInfoBadge = baseBadge

        let unityBtn = NSButton(title: "100% (0 dB)", target: self, action: #selector(onDryUnityResetClicked))
        unityBtn.bezelStyle = .inline
        unityBtn.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        unityBtn.wantsLayer = true
        unityBtn.layer?.cornerRadius = 4
        unityBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.20).cgColor
        unityBtn.contentTintColor = NSColor.systemGreen
        centerTopRow.addArrangedSubview(unityBtn)

        let muteDryBtn = NSButton(title: "MUTE DRY", target: self, action: #selector(onDryMuteClicked))
        muteDryBtn.bezelStyle = .inline
        muteDryBtn.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        muteDryBtn.wantsLayer = true
        muteDryBtn.layer?.cornerRadius = 4
        muteDryBtn.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.20).cgColor
        muteDryBtn.contentTintColor = NSColor.systemOrange
        centerTopRow.addArrangedSubview(muteDryBtn)

        centerVertStack.addArrangedSubview(centerTopRow)
        centerTopRow.widthAnchor.constraint(equalTo: centerVertStack.widthAnchor).isActive = true

        // Bottom Row inside Dry Card: Proportional Dry Pre-Gain Ducking Sliders for VST 1 & VST 2
        let duckRow = NSStackView()
        duckRow.orientation = .horizontal
        duckRow.alignment = .centerY
        duckRow.spacing = 8
        duckRow.translatesAutoresizingMaskIntoConstraints = false

        let duckHeader = NSTextField(labelWithString: "📉 Dry-Rückgang bei Pre-Gain:")
        duckHeader.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        duckHeader.textColor = NSColor(white: 0.72, alpha: 1.0)
        duckRow.addArrangedSubview(duckHeader)

        // VST Ducking Ratio (0% .. 100%)
        let vstDuckLbl = NSTextField(labelWithString: "VST Ducking:")
        vstDuckLbl.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        vstDuckLbl.textColor = NSColor(red: 1.0, green: 0.78, blue: 0.15, alpha: 1.0)
        duckRow.addArrangedSubview(vstDuckLbl)

        let initDuck1 = RaneFlexFxService.shared.fx1DryDuckRatio * 100.0
        let duck1Slider = RaneResettableSlider(value: initDuck1, minValue: 0.0, maxValue: 100.0, defaultValue: 50.0, alternateDefaultValue: 0.0, target: self, action: #selector(onFx1DryDuckRatioChanged(_:)))
        duck1Slider.isContinuous = true
        duck1Slider.controlSize = .small
        duck1Slider.toolTip = "Anteiliger Rückgang des Dry Pre-Gain beim Aufdrehen des VST Pre-Gain (Doppelklick: 50% / 0%)"
        duck1Slider.translatesAutoresizingMaskIntoConstraints = false
        duck1Slider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        duckRow.addArrangedSubview(duck1Slider)
        Self.flexFxRefs.fx1DryDuckSlider = duck1Slider

        let duck1Badge = NSTextField(labelWithString: String(format: "%.0f%%", initDuck1))
        duck1Badge.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        duck1Badge.textColor = NSColor(red: 1.0, green: 0.78, blue: 0.15, alpha: 1.0)
        duck1Badge.translatesAutoresizingMaskIntoConstraints = false
        duck1Badge.widthAnchor.constraint(equalToConstant: 36).isActive = true
        duckRow.addArrangedSubview(duck1Badge)
        Self.flexFxRefs.fx1DryDuckBadge = duck1Badge

        centerVertStack.addArrangedSubview(duckRow)
        duckRow.widthAnchor.constraint(equalTo: centerVertStack.widthAnchor).isActive = true

        let centerCard = centerVertStack.wrapInCard(
            cornerRadius: 7,
            borderColor: NSColor(white: 0.35, alpha: 0.55),
            fillColor: NSColor(red: 0.10, green: 0.105, blue: 0.12, alpha: 1.0),
            padding: NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        )
        row.addArrangedSubview(centerCard)
        centerCard.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let arrow2 = NSTextField(labelWithString: "──►")
        arrow2.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        arrow2.textColor = dryColor.withAlphaComponent(0.8)
        row.addArrangedSubview(arrow2)

        // 3. DRY POST-GAIN FADER MODULE (Right)
        let postBox = createGainFaderBox(
            label: "DRY POST-GAIN",
            initialGain: RaneFlexFxService.shared.dryPostGain,
            channelControl: .dryPostGain,
            action: #selector(onDryPostGainChanged(_:)),
            sliderOut: { slider, badge in
                Self.flexFxRefs.dryPostGainSlider = slider
                Self.flexFxRefs.dryPostGainBadge = badge
            }
        )
        row.addArrangedSubview(postBox)

        return row
    }

    // MARK: - Gain Fader Module Helper (Pre-Gain & Post-Gain)
    private func createGainFaderBox(
        label: String,
        initialGain: Double,
        channelControl: ChannelControlType,
        action: Selector,
        sliderOut: (NSSlider, NSTextField) -> Void
    ) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .centerX
        box.spacing = 3
        box.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 4

        let titleLbl = NSTextField(labelWithString: label)
        titleLbl.font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold)
        titleLbl.textColor = NSColor(white: 0.80, alpha: 1.0)
        topRow.addArrangedSubview(titleLbl)

        let badge = NSTextField(labelWithString: formatGainBadge(initialGain))
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
        badge.textColor = NSColor.systemYellow
        topRow.addArrangedSubview(badge)

        box.addArrangedSubview(topRow)

        let isVstPreGain = (channelControl == .slot1PreGain || channelControl == .slot2PreGain)
        let defVal: Double = isVstPreGain ? 0.0 : 100.0
        let altVal: Double? = isVstPreGain ? 100.0 : 0.0
        let slider = RaneResettableSlider(value: initialGain * 100.0, minValue: 0.0, maxValue: 150.0, defaultValue: defVal, alternateDefaultValue: altVal, target: self, action: action)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.toolTip = isVstPreGain ? "Doppelklick: Nullstellung (-∞ dB zu / 0.0 dB auf)" : "Doppelklick: Nullstellung (0.0 dB)"
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 104).isActive = true
        box.addArrangedSubview(slider)

        let learnBtn = createChannelMidiLearnBadgeButton(for: channelControl, compact: true)
        box.addArrangedSubview(learnBtn)

        sliderOut(slider, badge)

        let card = box.wrapInCard(
            cornerRadius: 6,
            borderColor: NSColor(white: 0.30, alpha: 0.5),
            fillColor: NSColor(red: 0.11, green: 0.115, blue: 0.135, alpha: 1.0),
            padding: NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: 118).isActive = true
        return card
    }

    private func createSignalConnectorView(symbol: String) -> NSView {
        let v = NSStackView()
        v.orientation = .vertical
        v.alignment = .centerX
        v.spacing = 36
        for _ in 0..<3 {
            let lbl = NSTextField(labelWithString: symbol)
            lbl.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            lbl.textColor = NSColor(white: 0.45, alpha: 1.0)
            v.addArrangedSubview(lbl)
        }
        return v
    }

    private func createChannelMidiLearnBadgeButton(for control: ChannelControlType, compact: Bool) -> NSButton {
        let btn = NSButton(title: "🎹 MIDI", target: self, action: #selector(onChannelMidiLearnTargetClicked(_:)))
        btn.bezelStyle = .inline
        btn.font = NSFont.monospacedSystemFont(ofSize: compact ? 8.5 : 9.0, weight: .bold)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.layer?.borderWidth = 1.0
        btn.identifier = NSUserInterfaceItemIdentifier(control.rawValue)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: compact ? 17 : 20).isActive = true
        if !compact {
            btn.widthAnchor.constraint(equalToConstant: 124).isActive = true
        }
        Self.flexFxRefs.channelMidiLearnButtons[control] = btn
        return btn
    }

    @objc func onChannelMidiLearnTargetClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let control = ChannelControlType(rawValue: raw) else { return }
        let chIdx = RaneFlexFxService.shared.selectedChannelIndex
        let target = FlexFxMidiTarget.target(forChannel: chIdx, control: control)
        let learn = RaneMidiLearnService.shared
        if learn.isLearnModeActive && learn.selectedTarget == target {
            learn.isLearnModeActive = false
            learn.selectedTarget = nil
        } else {
            learn.isLearnModeActive = true
            learn.selectedTarget = target
            appendMidiLog("MIDI Learn: Bitte jetzt Knopf/Fader am MIDI-Controller für [\(target.displayName)] bewegen...")
        }
        updateFlexFxUi()
    }

    private func createMidiLearnBadgeButton(for target: FlexFxMidiTarget, compact: Bool) -> NSButton {
        let btn = NSButton(title: "🎹 MIDI", target: self, action: #selector(onMatrixMidiLearnTargetClicked(_:)))
        btn.bezelStyle = .inline
        btn.font = NSFont.monospacedSystemFont(ofSize: compact ? 8.5 : 9.0, weight: .bold)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.layer?.borderWidth = 1.0
        btn.identifier = NSUserInterfaceItemIdentifier(target.rawValue)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: compact ? 17 : 20).isActive = true
        if !compact {
            btn.widthAnchor.constraint(equalToConstant: 124).isActive = true
        }
        Self.flexFxRefs.midiLearnButtons[target] = btn
        return btn
    }

    // MARK: - Plugin & MIDI Menu Builders
    private func rebuildPluginMenu(for popup: NSPopUpButton, slotIndex: Int) {
        popup.removeAllItems()
        guard slotIndex >= 0 && slotIndex < RanePluginHostService.shared.slots.count else { return }
        let slot = RanePluginHostService.shared.slots[slotIndex]

        // 1. Leer / Deaktiviert (0% CPU)
        let emptyItem = NSMenuItem(title: "● Leer / Deaktiviert (0% CPU)", action: nil, keyEquivalent: "")
        emptyItem.representedObject = "EMPTY"
        popup.menu?.addItem(emptyItem)

        // 2. Installierte VST2 Plugins
        let plugins = RanePluginHostService.shared.availablePlugins
        if !plugins.isEmpty {
            popup.menu?.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: "— Installierte VST2 Plugins —", action: nil, keyEquivalent: "")
            header.isEnabled = false
            popup.menu?.addItem(header)

            for p in plugins {
                let item = NSMenuItem(title: "🔌 \(p.name) [\(p.format.rawValue)] — \(p.manufacturer)", action: nil, keyEquivalent: "")
                item.representedObject = p.id
                popup.menu?.addItem(item)
            }
        }

        // Select current item
        if slot.isCustomPlugin && slot.isLoaded {
            if let idx = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == slot.pluginId }) {
                popup.selectItem(at: idx)
            } else {
                popup.selectItem(at: 0)
            }
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func rebuildVstMidiSourceMenu(for popup: NSPopUpButton, slotIndex: Int) {
        popup.removeAllItems()
        guard slotIndex >= 0 && slotIndex < RanePluginHostService.shared.slots.count else { return }
        let currentSourceId = RanePluginHostService.shared.slots[slotIndex].midiInputSourceId

        let omniItem = NSMenuItem(title: "Alle Controller (Omni)", action: nil, keyEquivalent: "")
        omniItem.representedObject = "OMNI"
        popup.menu?.addItem(omniItem)

        let clockOnlyItem = NSMenuItem(title: "Nur MIDI-Clock (Tempo)", action: nil, keyEquivalent: "")
        clockOnlyItem.representedObject = "CLOCK_ONLY"
        popup.menu?.addItem(clockOnlyItem)

        let offItem = NSMenuItem(title: "MIDI-Eingang Aus", action: nil, keyEquivalent: "")
        offItem.representedObject = "OFF"
        popup.menu?.addItem(offItem)

        let devices = RaneMidiService.shared.availableInputDevices
        if !devices.isEmpty {
            popup.menu?.addItem(NSMenuItem.separator())
            let hdr = NSMenuItem(title: "— Angeschlossene MIDI-Controller —", action: nil, keyEquivalent: "")
            hdr.isEnabled = false
            popup.menu?.addItem(hdr)

            for dev in devices {
                let item = NSMenuItem(title: "🎛 \(dev.displayName)", action: nil, keyEquivalent: "")
                item.representedObject = dev.id
                popup.menu?.addItem(item)
            }
        }

        // If saved device is currently disconnected, still show it so selection isn't lost
        if currentSourceId != "OMNI" && currentSourceId != "CLOCK_ONLY" && currentSourceId != "OFF" {
            if !popup.itemArray.contains(where: { ($0.representedObject as? String) == currentSourceId }) {
                let item = NSMenuItem(title: "🎛 \(currentSourceId) (Offline)", action: nil, keyEquivalent: "")
                item.representedObject = currentSourceId
                popup.menu?.addItem(item)
            }
        }

        if let idx = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == currentSourceId }) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
    }

    func rebuildAllPluginMenus() {
        let s = RaneFlexFxService.shared
        let slotIdx = s.activeChannel.slotIndex

        if let popup = Self.flexFxRefs.vstPluginPopups[0] {
            rebuildPluginMenu(for: popup, slotIndex: slotIdx)
        }
        if let popup = Self.flexFxRefs.vstMidiSourcePopups[0] {
            rebuildVstMidiSourceMenu(for: popup, slotIndex: slotIdx)
        }
    }

    func showEffectDetailPopover(for fx: FlexFxType, relativeTo button: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = FxDetailPopoverViewController(fxType: fx)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    // MARK: - UI Updates & State Sync
    func updateFlexFxUi() {
        let s = RaneFlexFxService.shared
        let learn = RaneMidiLearnService.shared

        // 1. Master Module Power Status
        Self.flexFxRefs.modulePowerSwitch?.state = s.isModuleEnabled ? .on : .off
        if s.isModuleEnabled {
            Self.flexFxRefs.moduleStatusBadge?.stringValue = " ● AKTIV "
            Self.flexFxRefs.moduleStatusBadge?.textColor = NSColor.systemGreen
            Self.flexFxRefs.moduleStatusBadge?.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
            Self.flexFxRefs.fxControlsContainer?.alphaValue = 1.0
        } else {
            Self.flexFxRefs.moduleStatusBadge?.stringValue = " ○ STANDBY "
            Self.flexFxRefs.moduleStatusBadge?.textColor = NSColor.systemGray
            Self.flexFxRefs.moduleStatusBadge?.layer?.backgroundColor = NSColor(white: 0.25, alpha: 0.20).cgColor
            Self.flexFxRefs.fxControlsContainer?.alphaValue = 0.45
        }

        // 2. MIDI Learn Header Button
        if let learnBtn = Self.flexFxRefs.midiLearnToggleButton {
            if learn.isLearnModeActive {
                if let sel = learn.selectedTarget {
                    learnBtn.title = "🎹 Warte auf MIDI für: \(sel.displayName)..."
                } else {
                    learnBtn.title = "🎹 MIDI Learn AKTIV (Steuerelement anklicken)"
                }
                learnBtn.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.28).cgColor
                learnBtn.layer?.borderColor = NSColor.systemYellow.cgColor
                learnBtn.contentTintColor = NSColor.systemYellow
            } else {
                learnBtn.title = "🎹 MIDI Learn"
                learnBtn.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.8).cgColor
                learnBtn.layer?.borderColor = NSColor(white: 0.35, alpha: 0.6).cgColor
                learnBtn.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
            }
        }

        // 3. Top OLED Bar: BPM, Tempo Slider & Ableton Link
        Self.flexFxRefs.oledBpmLabel?.stringValue = String(format: "%.1f BPM", s.bpm)
        Self.flexFxRefs.tempoSlider?.doubleValue = s.bpm
        Self.flexFxRefs.tempoBadge?.stringValue = String(format: "%.1f BPM", s.bpm)

        if s.isLinkEnabled {
            let peers = s.linkPeers
            Self.flexFxRefs.oledLinkBadge?.stringValue = "● ABLETON LINK: ON (\(peers) PEER\(peers == 1 ? "" : "S"))"
            Self.flexFxRefs.oledLinkBadge?.textColor = peers > 0 ? NSColor.systemGreen : NSColor.systemOrange
        } else {
            Self.flexFxRefs.oledLinkBadge?.stringValue = "○ ABLETON LINK: OFF (INTERN)"
            Self.flexFxRefs.oledLinkBadge?.textColor = NSColor(white: 0.55, alpha: 1.0)
        }

        for lBtn in [self.headerLinkButton, Self.flexFxRefs.linkButton].compactMap({ $0 }) {
            lBtn.isEnabled = true
            if s.isLinkEnabled {
                let peerStr = s.linkPeers > 0 ? " (\(s.linkPeers))" : ""
                lBtn.title = " 🔗 Ableton Link: ON\(peerStr) "
                lBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.22).cgColor
                lBtn.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.75).cgColor
                lBtn.contentTintColor = NSColor.systemGreen
            } else {
                lBtn.title = " 🔗 Ableton Link: OFF "
                lBtn.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.55).cgColor
                lBtn.layer?.borderColor = NSColor(white: 0.38, alpha: 0.5).cgColor
                lBtn.contentTintColor = NSColor(white: 0.68, alpha: 1.0)
            }
        }


        // 5. Gain Faders & Proportional Dry Ducking
        Self.flexFxRefs.fx1PreGainSlider?.doubleValue = s.fx1PreGain * 100.0
        Self.flexFxRefs.fx1PreGainBadge?.stringValue = formatGainBadge(s.fx1PreGain)
        Self.flexFxRefs.dryPreGainSlider?.doubleValue = s.dryPreGain * 100.0
        Self.flexFxRefs.dryPreGainBadge?.stringValue = formatGainBadge(s.dryPreGain)

        Self.flexFxRefs.fx1PostGainSlider?.doubleValue = s.fx1PostGain * 100.0
        Self.flexFxRefs.fx1PostGainBadge?.stringValue = formatGainBadge(s.fx1PostGain)
        Self.flexFxRefs.dryPostGainSlider?.doubleValue = s.dryPostGain * 100.0
        Self.flexFxRefs.dryPostGainBadge?.stringValue = formatGainBadge(s.dryPostGain)

        Self.flexFxRefs.fx1DryDuckSlider?.doubleValue = s.fx1DryDuckRatio * 100.0
        Self.flexFxRefs.fx1DryDuckBadge?.stringValue = String(format: "%.0f%%", s.fx1DryDuckRatio * 100.0)
        Self.flexFxRefs.dryBaseInfoBadge?.stringValue = "Ausgang: \(formatGainBadge(s.dryBasePreGain))"

        // 6. Dedicated VST Card for Selected Channel Strip (Slot 0..4)
        let slotIdx = s.activeChannel.slotIndex
        let slot = RanePluginHostService.shared.slots[slotIdx]
        let isSlotEnabled = s.isFx1Enabled
        let accent = NSColor(red: 1.0, green: 0.78, blue: 0.15, alpha: 1.0)

        if let btn = Self.flexFxRefs.vstToggleButtons[0] {
            let stateText = isSlotEnabled ? "ON" : "OFF"
            btn.title = "SLOT [\(s.activeChannel.shortName)]: \(stateText)"
            if isSlotEnabled && s.isModuleEnabled && slot.isLoaded {
                btn.layer?.backgroundColor = accent.withAlphaComponent(0.88).cgColor
                btn.layer?.borderColor = accent.cgColor
                btn.contentTintColor = NSColor.black
            } else {
                btn.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.85).cgColor
                btn.layer?.borderColor = NSColor(white: 0.34, alpha: 0.6).cgColor
                btn.contentTintColor = NSColor(white: 0.68, alpha: 1.0)
            }
        }

        if let uiBtn = Self.flexFxRefs.vstUiButtons[0] {
            uiBtn.title = "🎛 Editor"
            uiBtn.isEnabled = slot.isCustomPlugin && slot.isLoaded
        }

        if let popup = Self.flexFxRefs.vstPluginPopups[0] {
            if slot.isCustomPlugin && slot.isLoaded {
                if let idx = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == slot.pluginId }) {
                    popup.selectItem(at: idx)
                } else {
                    popup.selectItem(at: 0)
                }
            } else {
                popup.selectItem(at: 0) // "Leer / Deaktiviert"
            }
        }

        if let srcPopup = Self.flexFxRefs.vstMidiSourcePopups[0] {
            let curSrc = slot.midiInputSourceId
            if let idx = srcPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == curSrc }) {
                srcPopup.selectItem(at: idx)
            } else {
                srcPopup.selectItem(at: 0)
            }
        }

        if let chPopup = Self.flexFxRefs.vstMidiChannelPopups[0] {
            chPopup.selectItem(at: min(16, max(0, slot.midiChannelFilter)))
        }

        if let clockCheck = Self.flexFxRefs.vstMidiClockCheckboxes[0] {
            clockCheck.state = slot.sendMidiClock ? .on : .off
        }

        if let statusLbl = Self.flexFxRefs.vstMidiStatusLabels[0] {
            if !slot.isLoaded {
                statusLbl.stringValue = "● Slot leer (0% CPU)"
                statusLbl.textColor = NSColor(white: 0.6, alpha: 1.0)
            } else {
                let clkStr = slot.sendMidiClock ? "🕒 \(String(format: "%.1f", s.bpm)) BPM" : "Clock Aus"
                if !slot.lastMidiEventSummary.isEmpty && (Date().timeIntervalSince1970 - slot.lastMidiEventTime) < 10.0 {
                    statusLbl.stringValue = "⚡ \(slot.lastMidiEventSummary) • \(clkStr)"
                    statusLbl.textColor = NSColor.systemYellow
                } else {
                    statusLbl.stringValue = "\(clkStr) • VST2 aktiv"
                    statusLbl.textColor = NSColor(red: 0.30, green: 0.90, blue: 0.55, alpha: 0.85)
                }
            }
        }

        // 7. Update all interactive MIDI Learn Badges
        // 7a. Per-Channel Matrix Badges (PGM 1..4 & FlexFX)
        let chIdx = s.selectedChannelIndex
        for (control, btn) in Self.flexFxRefs.channelMidiLearnButtons {
            let target = FlexFxMidiTarget.target(forChannel: chIdx, control: control)
            let isSelectingThis = (learn.isLearnModeActive && learn.selectedTarget == target)
            if isSelectingThis {
                btn.title = "⏳ Bewege MIDI..."
                btn.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.32).cgColor
                btn.layer?.borderColor = NSColor.systemYellow.cgColor
                btn.contentTintColor = NSColor.systemYellow
            } else if let m = learn.mappingFor(target: target) {
                let chText = (m.channel == 255) ? "All" : "Ch\(m.channel + 1)"
                let typeText = (m.type == .note) ? "Note \(m.number)" : "CC #\(m.number)"
                btn.title = "🎹 \(typeText) (\(chText))"
                btn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.20).cgColor
                btn.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.65).cgColor
                btn.contentTintColor = NSColor.systemGreen
            } else {
                btn.title = learn.isLearnModeActive ? "🎯 Hier klicken" : "🎹 MIDI Learn"
                btn.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.75).cgColor
                btn.layer?.borderColor = learn.isLearnModeActive ? NSColor.systemYellow.withAlphaComponent(0.6).cgColor : NSColor(white: 0.32, alpha: 0.5).cgColor
                btn.contentTintColor = learn.isLearnModeActive ? NSColor.systemYellow : NSColor(white: 0.65, alpha: 1.0)
            }
        }

        // 7b. Global Badges (Tempo, Ableton Link, etc.)
        for (target, btn) in Self.flexFxRefs.midiLearnButtons {
            let isSelectingThis = (learn.isLearnModeActive && learn.selectedTarget == target)
            if isSelectingThis {
                btn.title = "⏳ Bewege MIDI..."
                btn.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.32).cgColor
                btn.layer?.borderColor = NSColor.systemYellow.cgColor
                btn.contentTintColor = NSColor.systemYellow
            } else if let m = learn.mappingFor(target: target) {
                let chText = (m.channel == 255) ? "All" : "Ch\(m.channel + 1)"
                let typeText = (m.type == .note) ? "Note \(m.number)" : "CC #\(m.number)"
                btn.title = "🎹 \(typeText) (\(chText))"
                btn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.20).cgColor
                btn.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.65).cgColor
                btn.contentTintColor = NSColor.systemGreen
            } else {
                btn.title = learn.isLearnModeActive ? "🎯 Hier klicken" : "🎹 MIDI Learn"
                btn.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.75).cgColor
                btn.layer?.borderColor = learn.isLearnModeActive ? NSColor.systemYellow.withAlphaComponent(0.6).cgColor : NSColor(white: 0.32, alpha: 0.5).cgColor
                btn.contentTintColor = learn.isLearnModeActive ? NSColor.systemYellow : NSColor(white: 0.65, alpha: 1.0)
            }
        }

        updateMiniHudUI()
    }

    private func setupFlexFxCallbacks() {
        RaneFlexFxService.shared.onStateChanged = { [weak self] in
            self?.updateFlexFxUi()
        }
        RaneFlexFxService.shared.onAudioStreamingChanged = { [weak self] _ in
            self?.updateFlexFxUi()
        }
        RaneFlexFxService.shared.onBeatPulse = { [weak self] beat in
            guard self != nil else { return }
            guard RaneFlexFxService.shared.isModuleEnabled else { return }
            for (idx, dot) in Self.flexFxRefs.beatDots.enumerated() {
                if idx == beat {
                    dot.layer?.backgroundColor = NSColor.systemYellow.cgColor
                } else {
                    dot.layer?.backgroundColor = NSColor(white: 0.25, alpha: 0.6).cgColor
                }
            }
        }

        RaneMidiService.shared.onMidiDevicesChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.rebuildAllPluginMenus()
                self?.updateFlexFxUi()
            }
        }

        RaneMidiLearnService.shared.addLearnModeObserver { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateFlexFxUi()
            }
        }
        RaneMidiLearnService.shared.addSelectedTargetObserver { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateFlexFxUi()
            }
        }
        RaneMidiLearnService.shared.addMappingObserver { [weak self] in
            DispatchQueue.main.async {
                self?.updateFlexFxUi()
            }
        }
        RaneMidiLearnService.shared.addMidiActionObserver { [weak self] target, val in
            DispatchQueue.main.async {
                self?.appendMidiLog("MIDI MATRIX: [\(target.displayName)] -> \(String(format: "%.0f%%", val * 100.0))")
                self?.updateFlexFxUi()
            }
        }

        RanePluginHostService.shared.onSlotsChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.updateFlexFxUi()
            }
        }
    }

    // MARK: - Action Handlers
    @objc func onFlexFxMidiLearnModeToggled(_ sender: NSButton) {
        let learn = RaneMidiLearnService.shared
        learn.isLearnModeActive.toggle()
        if learn.isLearnModeActive {
            appendMidiLog("MIDI Learn aktiviert: Klicke auf einen Button/Fader in der FlexFX-Matrix und bewege deinen MIDI-Controller.")
        } else {
            appendMidiLog("MIDI Learn beendet.")
        }
        updateFlexFxUi()
    }

    @objc func onMatrixMidiLearnTargetClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let target = FlexFxMidiTarget(rawValue: raw) else { return }
        let learn = RaneMidiLearnService.shared
        if learn.isLearnModeActive && learn.selectedTarget == target {
            learn.isLearnModeActive = false
            learn.selectedTarget = nil
        } else {
            learn.isLearnModeActive = true
            learn.selectedTarget = target
            appendMidiLog("MIDI Learn: Bitte jetzt Knopf/Fader am MIDI-Controller für [\(target.displayName)] bewegen...")
        }
        updateFlexFxUi()
    }

    @objc func onChannelStripSelected(_ sender: NSSegmentedControl) {
        RaneFlexFxService.shared.selectedChannelIndex = sender.selectedSegment
        rebuildAllPluginMenus()
        updateFlexFxUi()
    }

    @objc func onPluginSelected(_ sender: NSPopUpButton) {
        let s = RaneFlexFxService.shared
        let slotIdx = s.activeChannel.slotIndex
        guard let rep = sender.selectedItem?.representedObject as? String else { return }

        if rep == "EMPTY" {
            RanePluginHostService.shared.unloadSlot(slotIndex: slotIdx)
            appendMidiLog("Kanal \(s.activeChannel.shortName): VST entladen (Leer / 0% CPU).")
            updateFlexFxUi()
        } else if let info = RanePluginHostService.shared.availablePlugins.first(where: { $0.id == rep }) {
            RanePluginHostService.shared.loadPlugin(slotIndex: slotIdx, pluginInfo: info) { [weak self] success in
                if success {
                    self?.appendMidiLog("Kanal \(s.activeChannel.shortName): VST2 Plugin '\(info.name)' geladen!")
                } else {
                    self?.appendMidiLog("Kanal \(s.activeChannel.shortName): Fehler beim Laden von '\(info.name)'!")
                }
                self?.updateFlexFxUi()
            }
        }
    }

    @objc func onPluginUiButtonClicked(_ sender: NSButton) {
        let s = RaneFlexFxService.shared
        let slotIdx = s.activeChannel.slotIndex
        let slot = RanePluginHostService.shared.slots[slotIdx]
        if slot.isCustomPlugin && slot.isLoaded {
            RanePluginHostService.shared.openPluginUI(for: slotIdx)
        }
    }

    @objc func onVstMidiSourceChanged(_ sender: NSPopUpButton) {
        let s = RaneFlexFxService.shared
        let slotIdx = s.activeChannel.slotIndex
        guard let sourceId = sender.selectedItem?.representedObject as? String else { return }
        RanePluginHostService.shared.setSlotMidiSource(slotIndex: slotIdx, sourceId: sourceId)
        appendMidiLog("\(s.activeChannel.shortName): MIDI-Eingang -> [\(sender.selectedItem?.title ?? sourceId)]")
    }

    @objc func onVstMidiChannelChanged(_ sender: NSPopUpButton) {
        let s = RaneFlexFxService.shared
        let slotIdx = s.activeChannel.slotIndex
        let ch = max(0, sender.indexOfSelectedItem) // 0 = All, 1..16 = Ch 1..16
        RanePluginHostService.shared.setSlotMidiChannel(slotIndex: slotIdx, channel: ch)
        appendMidiLog("\(s.activeChannel.shortName): MIDI-Kanal -> [\(ch == 0 ? "Alle Kanäle" : "Ch \(ch)")]")
    }

    @objc func onVstMidiClockToggled(_ sender: NSButton) {
        let s = RaneFlexFxService.shared
        let slotIdx = s.activeChannel.slotIndex
        let enabled = (sender.state == .on)
        RanePluginHostService.shared.setSlotSendMidiClock(slotIndex: slotIdx, enabled: enabled)
        appendMidiLog("\(s.activeChannel.shortName): MIDI Clock Sync -> [\(enabled ? "EIN" : "AUS")]")
    }

    @objc func onVst1ToggleClicked(_ sender: NSButton) {
        RaneFlexFxService.shared.isFx1Enabled.toggle()
        appendMidiLog("VST Effekt [\(RaneFlexFxService.shared.activeChannel.shortName)]: [\(RaneFlexFxService.shared.isFx1Enabled ? "ON" : "OFF")]")
    }

    @objc func onVst2ToggleClicked(_ sender: NSButton) {
        RaneFlexFxService.shared.isFx2Enabled.toggle()
        appendMidiLog("VST Effekt 2: [\(RaneFlexFxService.shared.isFx2Enabled ? "ON" : "OFF")]")
    }

    @objc func onFx1PreGainChanged(_ sender: NSSlider) {
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.fx1PreGain = val
        Self.flexFxRefs.fx1PreGainBadge?.stringValue = formatGainBadge(val)
        let dry = RaneFlexFxService.shared.dryPreGain
        Self.flexFxRefs.dryPreGainSlider?.doubleValue = dry * 100.0
        Self.flexFxRefs.dryPreGainBadge?.stringValue = formatGainBadge(dry)
    }

    @objc func onFx2PreGainChanged(_ sender: NSSlider) {
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.fx2PreGain = val
        Self.flexFxRefs.fx2PreGainBadge?.stringValue = formatGainBadge(val)
        let dry = RaneFlexFxService.shared.dryPreGain
        Self.flexFxRefs.dryPreGainSlider?.doubleValue = dry * 100.0
        Self.flexFxRefs.dryPreGainBadge?.stringValue = formatGainBadge(dry)
    }

    @objc func onDryPreGainChanged(_ sender: NSSlider) {
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.dryBasePreGain = val
        RaneFlexFxService.shared.recalculateLinkedDryPreGain()
        let dry = RaneFlexFxService.shared.dryPreGain
        Self.flexFxRefs.dryPreGainSlider?.doubleValue = dry * 100.0
        Self.flexFxRefs.dryPreGainBadge?.stringValue = formatGainBadge(dry)
        Self.flexFxRefs.dryBaseInfoBadge?.stringValue = "Ausgang: \(formatGainBadge(RaneFlexFxService.shared.dryBasePreGain))"
    }

    @objc func onFx1DryDuckRatioChanged(_ sender: NSSlider) {
        let ratio = max(0.0, min(1.0, sender.doubleValue / 100.0))
        RaneFlexFxService.shared.fx1DryDuckRatio = ratio
        Self.flexFxRefs.fx1DryDuckBadge?.stringValue = String(format: "%.0f%%", ratio * 100.0)
        let dry = RaneFlexFxService.shared.dryPreGain
        Self.flexFxRefs.dryPreGainSlider?.doubleValue = dry * 100.0
        Self.flexFxRefs.dryPreGainBadge?.stringValue = formatGainBadge(dry)
    }

    @objc func onFx2DryDuckRatioChanged(_ sender: NSSlider) {
        let ratio = max(0.0, min(1.0, sender.doubleValue / 100.0))
        RaneFlexFxService.shared.fx2DryDuckRatio = ratio
        Self.flexFxRefs.fx2DryDuckBadge?.stringValue = String(format: "%.0f%%", ratio * 100.0)
        let dry = RaneFlexFxService.shared.dryPreGain
        Self.flexFxRefs.dryPreGainSlider?.doubleValue = dry * 100.0
        Self.flexFxRefs.dryPreGainBadge?.stringValue = formatGainBadge(dry)
    }

    @objc func onFx1PostGainChanged(_ sender: NSSlider) {
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.fx1PostGain = val
        Self.flexFxRefs.fx1PostGainBadge?.stringValue = formatGainBadge(val)
    }

    @objc func onFx2PostGainChanged(_ sender: NSSlider) {
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.fx2PostGain = val
        Self.flexFxRefs.fx2PostGainBadge?.stringValue = formatGainBadge(val)
    }

    @objc func onDryPostGainChanged(_ sender: NSSlider) {
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.dryPostGain = val
        Self.flexFxRefs.dryPostGainBadge?.stringValue = formatGainBadge(val)
    }

    @objc func onDryUnityResetClicked() {
        RaneFlexFxService.shared.dryBasePreGain = 1.0
        RaneFlexFxService.shared.dryPreGain = 1.0
        RaneFlexFxService.shared.dryPostGain = 1.0
        RaneFlexFxService.shared.recalculateLinkedDryPreGain()
        updateFlexFxUi()
    }

    @objc func onDryMuteClicked() {
        RaneFlexFxService.shared.dryPostGain = 0.0
        updateFlexFxUi()
    }

    @objc func onPrevInputSourceClicked() {
        RaneFlexFxService.shared.cycleInputSource(forward: false)
        appendMidiLog("USB RECORD Stereo-Paar -> [\(RaneFlexFxService.shared.inputSource.displayName)]")
    }

    @objc func onNextInputSourceClicked() {
        RaneFlexFxService.shared.cycleInputSource(forward: true)
        appendMidiLog("USB RECORD Stereo-Paar -> [\(RaneFlexFxService.shared.inputSource.displayName)]")
    }

    @objc func onPrevOutputDestClicked() {
        RaneFlexFxService.shared.cycleOutputDestination(forward: false)
        appendMidiLog("USB PLAYBACK Stereo-Paar -> [\(RaneFlexFxService.shared.outputDestination.displayName)]")
    }

    @objc func onNextOutputDestClicked() {
        RaneFlexFxService.shared.cycleOutputDestination(forward: true)
        appendMidiLog("USB PLAYBACK Stereo-Paar -> [\(RaneFlexFxService.shared.outputDestination.displayName)]")
    }

    @objc func onAudioInputSelected(_ sender: NSPopUpButton) {
        guard let src = FlexFxInputSource(rawValue: sender.selectedTag()) else { return }
        RaneFlexFxService.shared.inputSource = src
        appendMidiLog("USB RECORD Stereo-Paar gewählt -> [\(src.displayName)]")
        updateFlexFxUi()
    }

    @objc func onAudioOutputSelected(_ sender: NSPopUpButton) {
        guard let dst = FlexFxOutputDestination(rawValue: sender.selectedTag()) else { return }
        RaneFlexFxService.shared.outputDestination = dst
        appendMidiLog("USB PLAYBACK Stereo-Paar gewählt -> [\(dst.displayName)]")
        updateFlexFxUi()
    }

    @objc func onTempoMinusClicked() {
        RaneFlexFxService.shared.setManualBpm(RaneFlexFxService.shared.bpm - 0.5)
    }

    @objc func onTempoPlusClicked() {
        RaneFlexFxService.shared.setManualBpm(RaneFlexFxService.shared.bpm + 0.5)
    }

    @objc func onTapTempoClicked() {
        RaneFlexFxService.shared.tapTempo()
    }

    @objc func onPrevBeatClicked() {
        RaneFlexFxService.shared.cycleBeatDivision(forward: false)
    }

    @objc func onNextBeatClicked() {
        RaneFlexFxService.shared.cycleBeatDivision(forward: true)
    }

    @objc func onModulePowerToggled(_ sender: NSSwitch) {
        let isPowerOn = (sender.state == .on)
        RaneFlexFxService.shared.isModuleEnabled = isPowerOn
        appendMidiLog("FlexFX Engine: Modul-Hauptschalter -> [\(isPowerOn ? "AKTIVIERT" : "STANDBY / BYPASS")]")
    }

    @objc func onFlexFxToggleClicked() {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        RaneFlexFxService.shared.isFx1Enabled.toggle()
        appendMidiLog("FlexFX Engine: VST Effekt 1 -> [\(RaneFlexFxService.shared.isFx1Enabled ? "EIN" : "OFF")]")
    }

    @objc func onLinkToggleClicked() {
        RaneFlexFxService.shared.isLinkEnabled.toggle()
        appendMidiLog("Ableton Link (Global): Status -> [\(RaneFlexFxService.shared.isLinkEnabled ? "AKTIV" : "AUS / STANDALONE")]")
        updateFlexFxUi()
    }

    @objc func onPrePostToggled() {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        RaneFlexFxService.shared.isPreFader.toggle()
        let modeStr = RaneFlexFxService.shared.isPreFader ? "PRE-FADER (Hard Cut)" : "POST-FADER (Reverb/Delay Tail)"
        appendMidiLog("FlexFX Engine: Signal-Routing -> [\(modeStr)]")
        updateFlexFxUi()
    }

    @objc func onTempoSliderChanged(_ sender: NSSlider) {
        let rounded = round(sender.doubleValue * 10.0) / 10.0
        RaneFlexFxService.shared.setManualBpm(rounded)
        Self.flexFxRefs.tempoBadge?.stringValue = String(format: "%.1f BPM", rounded)
    }

    @objc func onRescanPluginsClicked(_ sender: NSButton) {
        appendMidiLog("Plugin Host: Scanne nach installierten VST2 Plugins (.vst)...")
        RanePluginHostService.shared.rescanAvailablePlugins()
        let count = RanePluginHostService.shared.availablePlugins.count
        appendMidiLog("Plugin Host: Scan abgeschlossen — \(count) VST2 Plugins gefunden.")
        rebuildAllPluginMenus()
        updateFlexFxUi()
    }

    private func formatGainBadge(_ gain: Double) -> String {
        if gain <= 0.001 {
            return "-∞ dB"
        }
        let db = 20.0 * log10(gain)
        if abs(db) < 0.05 {
            return "0.0 dB"
        }
        return String(format: "%+.1f dB", db)
    }
}
