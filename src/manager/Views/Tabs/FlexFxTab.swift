/* SPDX-License-Identifier: MIT */
/* FlexFxTab.swift - Authentic Rane Sixty-Eight Hardware FlexFX Panel Replica with DaisySP & Ableton Link */

import Cocoa

extension MainWindowController {
    // MARK: - FlexFX UI State & References
    struct FlexFxUiReferences {
        var modulePowerSwitch: NSSwitch!
        var moduleStatusBadge: NSTextField!
        var fxControlsContainer: NSView!
        var oledDisplay: NSView!
        var oledEffectName: NSTextField!
        var oledBeatLabel: NSTextField!
        var oledBpmLabel: NSTextField!
        var oledLinkBadge: NSTextField!
        var beatDots: [NSView] = []
        var fxButtons: [FlexFxType: NSButton] = [:]
        var prevBeatButton: NSButton!
        var nextBeatButton: NSButton!
        var beatSegments: NSSegmentedControl!
        var flexFxOnButton: NSButton!
        var linkButton: NSButton!
        var prePostButton: NSButton!
        var dryWetSlider: NSSlider!
        var dryWetBadge: NSTextField!
        var depthSlider: NSSlider!
        var depthBadge: NSTextField!
        var routingBadge: NSTextField!
    }

    private static var flexFxRefs = FlexFxUiReferences()

    func buildFlexFxPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 10
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        // SECTION 1: HARDWARE FLEXFX MODUL (Authentic Mixer Look)
        let sec1Outer = NSStackView()
        sec1Outer.orientation = .vertical
        sec1Outer.alignment = .leading
        sec1Outer.spacing = 10

        // Top Bar mit Titel & Master Power Switch
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 10
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "waveform.badge.magnifyingglass", accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        }
        iconView.contentTintColor = .systemYellow
        topBar.addArrangedSubview(iconView)

        let titleLabel = NSTextField(labelWithString: Localization.tr(
            en: "Software FlexFX Module & Ableton Link Sync",
            de: "Software FlexFX Modul & Ableton Link Sync"
        ))
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = NSColor(white: 0.90, alpha: 1.0)
        topBar.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topBar.addArrangedSubview(spacer)

        // Master Switch für Modul An/Aus
        let pwrLabel = NSTextField(labelWithString: Localization.tr(en: "Module Power:", de: "Modul-Status:"))
        pwrLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        pwrLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        topBar.addArrangedSubview(pwrLabel)

        let pwrSwitch = NSSwitch()
        pwrSwitch.state = RaneFlexFxService.shared.isModuleEnabled ? .on : .off
        pwrSwitch.target = self
        pwrSwitch.action = #selector(onModulePowerToggled(_:))
        topBar.addArrangedSubview(pwrSwitch)
        Self.flexFxRefs.modulePowerSwitch = pwrSwitch

        let statusBadge = NSTextField(labelWithString: "  ● AKTIV  ")
        statusBadge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        statusBadge.textColor = NSColor.systemGreen
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 4
        statusBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
        topBar.addArrangedSubview(statusBadge)
        Self.flexFxRefs.moduleStatusBadge = statusBadge

        sec1Outer.addArrangedSubview(topBar)
        topBar.widthAnchor.constraint(equalTo: sec1Outer.widthAnchor).isActive = true

        let fxCardStack = NSStackView()
        fxCardStack.orientation = .vertical
        fxCardStack.alignment = .leading
        fxCardStack.spacing = 12

        // --- SUB-SECTION A: AUTHENTIC HARDWARE OLED DISPLAY ---
        let oledContainer = createHardwareOledDisplay()
        fxCardStack.addArrangedSubview(oledContainer)
        oledContainer.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        let div1 = createDivider()
        fxCardStack.addArrangedSubview(div1)
        div1.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        // --- SUB-SECTION B: 6 PHYSICAL EFFECT SELECTOR BUTTONS (Clean Text, No Icons) ---
        let selectorLabel = NSTextField(labelWithString: Localization.tr(en: "EFFECT SELECTOR (HARDWARE MATRIX)", de: "EFFEKT-AUSWAHL (HARDWARE-MATRIX)"))
        selectorLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        selectorLabel.textColor = NSColor(white: 0.70, alpha: 1.0)
        fxCardStack.addArrangedSubview(selectorLabel)

        let fxButtonsGrid = createFxButtonsMatrix()
        fxCardStack.addArrangedSubview(fxButtonsGrid)
        fxButtonsGrid.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        let div2 = createDivider()
        fxCardStack.addArrangedSubview(div2)
        div2.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        // --- SUB-SECTION C: BEAT DIVISION & TAP TEMPO ---
        let beatRow = createBeatDivisionRow()
        fxCardStack.addArrangedSubview(beatRow)
        beatRow.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        let div3 = createDivider()
        fxCardStack.addArrangedSubview(div3)
        div3.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        // --- SUB-SECTION D: MASTER CONTROLS & ROUTING ---
        let masterControls = createMasterControlsRow()
        fxCardStack.addArrangedSubview(masterControls)
        masterControls.widthAnchor.constraint(equalTo: fxCardStack.widthAnchor).isActive = true

        Self.flexFxRefs.fxControlsContainer = fxCardStack

        let topCard = fxCardStack.wrapInCard(
            cornerRadius: 10,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.176, green: 0.180, blue: 0.200, alpha: 1.0),
            padding: NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        )
        sec1Outer.addArrangedSubview(topCard)
        topCard.widthAnchor.constraint(equalTo: sec1Outer.widthAnchor).isActive = true

        let sec1Inset = sec1Outer.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        )
        page.addArrangedSubview(sec1Inset)
        sec1Inset.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        // Initial UI Synchronization
        updateFlexFxUi()
        setupFlexFxCallbacks()

        return page
    }

    // MARK: - Authentic OLED Display Component
    private func createHardwareOledDisplay() -> NSView {
        let oled = NSView()
        oled.wantsLayer = true
        oled.layer?.cornerRadius = 8
        oled.layer?.backgroundColor = NSColor(red: 0.04, green: 0.06, blue: 0.09, alpha: 1.0).cgColor
        oled.layer?.borderColor = NSColor(red: 0.16, green: 0.22, blue: 0.30, alpha: 0.8).cgColor
        oled.layer?.borderWidth = 1.5
        oled.translatesAutoresizingMaskIntoConstraints = false
        oled.heightAnchor.constraint(equalToConstant: 86).isActive = true
        Self.flexFxRefs.oledDisplay = oled

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        oled.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: oled.topAnchor),
            stack.bottomAnchor.constraint(equalTo: oled.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: oled.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: oled.trailingAnchor)
        ])

        // Column 1: Effect Title & Indicator
        let col1 = NSStackView()
        col1.orientation = .vertical
        col1.alignment = .leading
        col1.spacing = 2

        let fxHeader = NSTextField(labelWithString: "FLEXFX ENGINE")
        fxHeader.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        fxHeader.textColor = NSColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 0.9)
        col1.addArrangedSubview(fxHeader)

        let fxName = NSTextField(labelWithString: "ECHO")
        fxName.font = NSFont.systemFont(ofSize: 24, weight: .black)
        fxName.textColor = NSColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1.0) // Amber OLED
        col1.addArrangedSubview(fxName)
        Self.flexFxRefs.oledEffectName = fxName

        stack.addArrangedSubview(col1)

        // Column 2: Beat Division & Metronome Dots
        let col2 = NSStackView()
        col2.orientation = .vertical
        col2.alignment = .centerX
        col2.spacing = 4

        let beatVal = NSTextField(labelWithString: "1/2 BEAT (241.9 ms)")
        beatVal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .heavy)
        beatVal.textColor = NSColor(white: 0.95, alpha: 1.0)
        col2.addArrangedSubview(beatVal)
        Self.flexFxRefs.oledBeatLabel = beatVal

        // 4 Beat Pulse Dots
        let dotsStack = NSStackView()
        dotsStack.orientation = .horizontal
        dotsStack.spacing = 8
        Self.flexFxRefs.beatDots.removeAll()
        for _ in 0..<4 {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 5
            dot.layer?.backgroundColor = NSColor(white: 0.25, alpha: 0.6).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
            dotsStack.addArrangedSubview(dot)
            Self.flexFxRefs.beatDots.append(dot)
        }
        col2.addArrangedSubview(dotsStack)
        stack.addArrangedSubview(col2)

        // Column 3: Ableton Link & BPM Display
        let col3 = NSStackView()
        col3.orientation = .vertical
        col3.alignment = .trailing
        col3.spacing = 2

        let linkBadge = NSTextField(labelWithString: "● LINK: 0 PEERS")
        linkBadge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        linkBadge.textColor = NSColor.systemGreen
        col3.addArrangedSubview(linkBadge)
        Self.flexFxRefs.oledLinkBadge = linkBadge

        let bpmLabel = NSTextField(labelWithString: "124.0 BPM")
        bpmLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .black)
        bpmLabel.textColor = NSColor(red: 0.20, green: 0.95, blue: 0.85, alpha: 1.0) // Cyan OLED
        col3.addArrangedSubview(bpmLabel)
        Self.flexFxRefs.oledBpmLabel = bpmLabel

        stack.addArrangedSubview(col3)

        return oled
    }

    // MARK: - 6 Effect Matrix Buttons (Clean, Authentic Look Without Icons)
    private func createFxButtonsMatrix() -> NSView {
        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.alignment = .leading
        gridStack.spacing = 8

        let row1 = NSStackView()
        row1.orientation = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 10

        let row2 = NSStackView()
        row2.orientation = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 10

        let effectsRow1: [FlexFxType] = [.filter, .flanger, .phaser]
        let effectsRow2: [FlexFxType] = [.echo, .robot, .reverb]

        for fx in effectsRow1 {
            let btn = createTactileFxButton(type: fx)
            row1.addArrangedSubview(btn)
        }
        for fx in effectsRow2 {
            let btn = createTactileFxButton(type: fx)
            row2.addArrangedSubview(btn)
        }

        gridStack.addArrangedSubview(row1)
        gridStack.addArrangedSubview(row2)
        row1.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true
        row2.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true

        return gridStack
    }

    private func createTactileFxButton(type: FlexFxType) -> NSButton {
        // Reine, zentrierte Schrift ohne Icons genau wie auf den echten Tasten des Sixty-Eight
        let btn = NSButton(title: type.displayName, target: self, action: #selector(onFxButtonClicked(_:)))
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.borderWidth = 1.2
        btn.layer?.borderColor = NSColor(white: 0.32, alpha: 0.5).cgColor
        btn.layer?.backgroundColor = NSColor(red: 0.13, green: 0.135, blue: 0.15, alpha: 1.0).cgColor
        btn.font = NSFont.systemFont(ofSize: 13, weight: .heavy)
        btn.alignment = .center
        btn.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
        btn.tag = type.rawValue
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 34).isActive = true

        Self.flexFxRefs.fxButtons[type] = btn
        return btn
    }

    // MARK: - Beat Division & Tap Row
    private func createBeatDivisionRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        // Beat < Button
        let prevBeatBtn = NSButton(title: "◀ BEAT", target: self, action: #selector(onPrevBeatClicked))
        prevBeatBtn.bezelStyle = .inline
        prevBeatBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        prevBeatBtn.wantsLayer = true
        prevBeatBtn.layer?.cornerRadius = 5
        prevBeatBtn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
        row.addArrangedSubview(prevBeatBtn)
        Self.flexFxRefs.prevBeatButton = prevBeatBtn

        // Beat Multiplier Segments (1/8 ... 4/1)
        let labels = BeatDivision.allCases.map { $0.label }
        let seg = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(onBeatSegmentChanged(_:)))
        seg.selectedSegment = RaneFlexFxService.shared.currentDivision.rawValue
        seg.segmentStyle = .texturedRounded
        seg.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        row.addArrangedSubview(seg)
        Self.flexFxRefs.beatSegments = seg

        // Beat > Button
        let nextBeatBtn = NSButton(title: "BEAT ▶", target: self, action: #selector(onNextBeatClicked))
        nextBeatBtn.bezelStyle = .inline
        nextBeatBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        nextBeatBtn.wantsLayer = true
        nextBeatBtn.layer?.cornerRadius = 5
        nextBeatBtn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
        row.addArrangedSubview(nextBeatBtn)
        Self.flexFxRefs.nextBeatButton = nextBeatBtn

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        return row
    }

    // MARK: - Master Controls & Ableton Link Row
    private func createMasterControlsRow() -> NSView {
        let main = NSStackView()
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 10

        let row1 = NSStackView()
        row1.orientation = .horizontal
        row1.alignment = .centerY
        row1.spacing = 16

        // Big FLEXFX ON/OFF Button
        let onBtn = NSButton(title: "FLEXFX ON", target: self, action: #selector(onFlexFxToggleClicked))
        onBtn.bezelStyle = .regularSquare
        onBtn.isBordered = false
        onBtn.wantsLayer = true
        onBtn.layer?.cornerRadius = 6
        onBtn.layer?.borderWidth = 1.5
        onBtn.font = NSFont.systemFont(ofSize: 13, weight: .black)
        onBtn.translatesAutoresizingMaskIntoConstraints = false
        onBtn.heightAnchor.constraint(equalToConstant: 36).isActive = true
        onBtn.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row1.addArrangedSubview(onBtn)
        Self.flexFxRefs.flexFxOnButton = onBtn

        // Ableton Link Button
        let linkBtn = NSButton(title: "  LINK (Ableton / DJ Sync)", target: self, action: #selector(onLinkToggleClicked))
        linkBtn.bezelStyle = .inline
        linkBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        linkBtn.wantsLayer = true
        linkBtn.layer?.cornerRadius = 6
        linkBtn.translatesAutoresizingMaskIntoConstraints = false
        linkBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        if let img = NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: nil) {
            linkBtn.image = img
            linkBtn.imagePosition = .imageLeading
        }
        row1.addArrangedSubview(linkBtn)
        Self.flexFxRefs.linkButton = linkBtn

        // Pre/Post Fader Mode Switch (Tail Preservation for Reverb/Echo)
        let ppBtn = NSButton(title: "POST-FADER (Tail)", target: self, action: #selector(onPrePostToggled))
        ppBtn.bezelStyle = .inline
        ppBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        ppBtn.wantsLayer = true
        ppBtn.layer?.cornerRadius = 6
        ppBtn.layer?.borderWidth = 1.0
        ppBtn.layer?.borderColor = NSColor.systemBlue.cgColor
        ppBtn.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.20).cgColor
        ppBtn.contentTintColor = NSColor.systemBlue
        ppBtn.translatesAutoresizingMaskIntoConstraints = false
        ppBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        row1.addArrangedSubview(ppBtn)
        Self.flexFxRefs.prePostButton = ppBtn

        // Routing Badge
        let routingBadge = NSTextField(labelWithString: "  ● Hardware: Schalter auf USB INSERT (Ch 9/10 Loop)  ")
        routingBadge.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        routingBadge.textColor = NSColor.systemTeal
        routingBadge.wantsLayer = true
        routingBadge.layer?.cornerRadius = 4
        routingBadge.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.15).cgColor
        row1.addArrangedSubview(routingBadge)
        Self.flexFxRefs.routingBadge = routingBadge

        main.addArrangedSubview(row1)

        // Sliders: Dry/Wet & Depth/Feedback
        let slidersRow = NSStackView()
        slidersRow.orientation = .horizontal
        slidersRow.alignment = .centerY
        slidersRow.spacing = 20

        // Dry/Wet Slider & Clickable Learn Label
        let dwStack = NSStackView()
        dwStack.orientation = .horizontal
        dwStack.spacing = 8
        dwStack.alignment = .centerY
        let dwLabel = NSTextField(labelWithString: "Dry / Wet:")
        dwLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        dwLabel.textColor = NSColor(white: 0.90, alpha: 1.0)
        let dwSlider = NSSlider(value: RaneFlexFxService.shared.dryWet * 100.0, minValue: 0, maxValue: 100, target: self, action: #selector(onDryWetChanged(_:)))
        dwSlider.isContinuous = true
        dwSlider.translatesAutoresizingMaskIntoConstraints = false
        dwSlider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        let dwBadge = createValueBadge(text: "\(Int(RaneFlexFxService.shared.dryWet * 100.0))%")
        dwStack.addArrangedSubview(dwLabel)
        dwStack.addArrangedSubview(dwSlider)
        dwStack.addArrangedSubview(dwBadge)
        Self.flexFxRefs.dryWetSlider = dwSlider
        Self.flexFxRefs.dryWetBadge = dwBadge
        slidersRow.addArrangedSubview(dwStack)

        // Depth / Feedback Slider
        let dpStack = NSStackView()
        dpStack.orientation = .horizontal
        dpStack.spacing = 8
        dpStack.alignment = .centerY
        let dpLabel = NSTextField(labelWithString: Localization.tr(en: "Feedback / Depth:", de: "Feedback / Tiefe:"))
        dpLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        dpLabel.textColor = NSColor(white: 0.90, alpha: 1.0)
        let dpSlider = NSSlider(value: RaneFlexFxService.shared.depth * 100.0, minValue: 0, maxValue: 100, target: self, action: #selector(onDepthChanged(_:)))
        dpSlider.isContinuous = true
        dpSlider.translatesAutoresizingMaskIntoConstraints = false
        dpSlider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        let dpBadge = createValueBadge(text: "\(Int(RaneFlexFxService.shared.depth * 100.0))%")
        dpStack.addArrangedSubview(dpLabel)
        dpStack.addArrangedSubview(dpSlider)
        dpStack.addArrangedSubview(dpBadge)
        Self.flexFxRefs.depthSlider = dpSlider
        Self.flexFxRefs.depthBadge = dpBadge
        slidersRow.addArrangedSubview(dpStack)

        main.addArrangedSubview(slidersRow)

        return main
    }

    // MARK: - UI Updates & State Sync
    func updateFlexFxUi() {
        let s = RaneFlexFxService.shared

        // 1. Master Modul Power Status
        Self.flexFxRefs.modulePowerSwitch?.state = s.isModuleEnabled ? .on : .off
        if s.isModuleEnabled {
            Self.flexFxRefs.moduleStatusBadge?.stringValue = "  ● AKTIV  "
            Self.flexFxRefs.moduleStatusBadge?.textColor = NSColor.systemGreen
            Self.flexFxRefs.moduleStatusBadge?.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
            Self.flexFxRefs.fxControlsContainer?.alphaValue = 1.0
        } else {
            Self.flexFxRefs.moduleStatusBadge?.stringValue = "  ○ AUS (BYPASS)  "
            Self.flexFxRefs.moduleStatusBadge?.textColor = NSColor.systemGray
            Self.flexFxRefs.moduleStatusBadge?.layer?.backgroundColor = NSColor(white: 0.25, alpha: 0.20).cgColor
            Self.flexFxRefs.fxControlsContainer?.alphaValue = 0.38
        }

        // Enable / Disable sub-controls based on module power (or active MIDI Learn mode)
        let learn = RaneMidiLearnService.shared
        let controlsActive = s.isModuleEnabled || learn.isLearnModeActive

        Self.flexFxRefs.prevBeatButton?.isEnabled = controlsActive
        Self.flexFxRefs.nextBeatButton?.isEnabled = controlsActive
        Self.flexFxRefs.beatSegments?.isEnabled = controlsActive
        Self.flexFxRefs.flexFxOnButton?.isEnabled = controlsActive
        Self.flexFxRefs.linkButton?.isEnabled = controlsActive
        Self.flexFxRefs.prePostButton?.isEnabled = controlsActive
        Self.flexFxRefs.dryWetSlider?.isEnabled = controlsActive
        Self.flexFxRefs.depthSlider?.isEnabled = controlsActive

        for (_, btn) in Self.flexFxRefs.fxButtons {
            btn.isEnabled = controlsActive
        }

        // 2. OLED Display Update
        if !s.isModuleEnabled {
            Self.flexFxRefs.oledEffectName?.stringValue = "-- AUS / STANDBY --"
            Self.flexFxRefs.oledEffectName?.textColor = NSColor(white: 0.38, alpha: 1.0)
            Self.flexFxRefs.oledBeatLabel?.stringValue = "EFFEKT-PROZESSOR BYPASS"
            Self.flexFxRefs.oledBeatLabel?.textColor = NSColor(white: 0.40, alpha: 1.0)
            Self.flexFxRefs.oledBpmLabel?.stringValue = "---.- BPM"
            Self.flexFxRefs.oledBpmLabel?.textColor = NSColor(white: 0.35, alpha: 1.0)
            Self.flexFxRefs.oledLinkBadge?.stringValue = "○ INAKTIV"
            Self.flexFxRefs.oledLinkBadge?.textColor = NSColor(white: 0.35, alpha: 1.0)

            for dot in Self.flexFxRefs.beatDots {
                dot.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.4).cgColor
            }
        } else {
            if s.isEnabled {
                Self.flexFxRefs.oledEffectName?.stringValue = s.currentEffect.displayName
                Self.flexFxRefs.oledEffectName?.textColor = NSColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1.0)
                Self.flexFxRefs.oledBeatLabel?.stringValue = "\(s.currentDivision.label) BEAT (\(String(format: "%.1f", s.delayTimeMs)) ms)"
                Self.flexFxRefs.oledBeatLabel?.textColor = NSColor(white: 0.95, alpha: 1.0)
            } else {
                Self.flexFxRefs.oledEffectName?.stringValue = "\(s.currentEffect.displayName) (BYPASS)"
                Self.flexFxRefs.oledEffectName?.textColor = NSColor(white: 0.55, alpha: 1.0)
                Self.flexFxRefs.oledBeatLabel?.stringValue = "\(s.currentDivision.label) BEAT (BYPASS)"
                Self.flexFxRefs.oledBeatLabel?.textColor = NSColor(white: 0.55, alpha: 1.0)
            }

            Self.flexFxRefs.oledBpmLabel?.stringValue = "\(String(format: "%.1f", s.bpm)) BPM"
            Self.flexFxRefs.oledBpmLabel?.textColor = NSColor(red: 0.20, green: 0.95, blue: 0.85, alpha: 1.0)

            if s.isLinkEnabled {
                Self.flexFxRefs.oledLinkBadge?.stringValue = "● LINK: \(s.linkPeers) PEER\(s.linkPeers == 1 ? "" : "S")"
                Self.flexFxRefs.oledLinkBadge?.textColor = s.linkPeers > 0 ? NSColor.systemGreen : NSColor.systemOrange
            } else {
                Self.flexFxRefs.oledLinkBadge?.stringValue = "○ STANDALONE (Master)"
                Self.flexFxRefs.oledLinkBadge?.textColor = NSColor(white: 0.60, alpha: 1.0)
            }
        }

        // 3. Highlight Effect Buttons
        for (fx, btn) in Self.flexFxRefs.fxButtons {
            let isCurrent = (fx == s.currentEffect)
            if isCurrent && s.isModuleEnabled {
                btn.layer?.backgroundColor = NSColor(red: 0.32, green: 0.24, blue: 0.08, alpha: 1.0).cgColor
                btn.layer?.borderColor = NSColor.systemYellow.cgColor
                btn.contentTintColor = NSColor.systemYellow
            } else {
                btn.layer?.backgroundColor = NSColor(red: 0.13, green: 0.135, blue: 0.15, alpha: 1.0).cgColor
                btn.layer?.borderColor = NSColor(white: 0.32, alpha: 0.5).cgColor
                btn.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
            }
        }

        // 4. Beat Segments
        Self.flexFxRefs.beatSegments?.selectedSegment = s.currentDivision.rawValue

        // 4b. Dry/Wet & Depth Sliders & Badges live synchronization
        Self.flexFxRefs.dryWetSlider?.doubleValue = s.dryWet * 100.0
        Self.flexFxRefs.dryWetBadge?.stringValue = "\(Int(round(s.dryWet * 100.0)))%"
        Self.flexFxRefs.depthSlider?.doubleValue = s.depth * 100.0
        Self.flexFxRefs.depthBadge?.stringValue = "\(Int(round(s.depth * 100.0)))%"

        // 5. FLEXFX ON Button
        if let onBtn = Self.flexFxRefs.flexFxOnButton {
            if s.isEnabled && s.isModuleEnabled {
                onBtn.title = "FLEXFX ON"
                onBtn.layer?.backgroundColor = NSColor(red: 0.90, green: 0.72, blue: 0.10, alpha: 1.0).cgColor
                onBtn.layer?.borderColor = NSColor.systemYellow.cgColor
                onBtn.contentTintColor = NSColor.black
            } else {
                onBtn.title = "FLEXFX OFF"
                onBtn.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.8).cgColor
                onBtn.layer?.borderColor = NSColor(white: 0.32, alpha: 0.5).cgColor
                onBtn.contentTintColor = NSColor(white: 0.60, alpha: 1.0)
            }
        }

        // 6. Link Button
        if let lBtn = Self.flexFxRefs.linkButton {
            if s.isLinkEnabled && s.isModuleEnabled {
                lBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.20).cgColor
                lBtn.layer?.borderColor = NSColor.systemGreen.cgColor
                lBtn.contentTintColor = NSColor.systemGreen
            } else {
                lBtn.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.5).cgColor
                lBtn.layer?.borderColor = NSColor(white: 0.35, alpha: 0.4).cgColor
                lBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
        }

        // 8. Pre/Post Fader Mode
        if let ppBtn = Self.flexFxRefs.prePostButton {
            if s.isPreFader {
                ppBtn.title = "PRE-FADER (Bypass)"
                ppBtn.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.20).cgColor
                ppBtn.layer?.borderColor = NSColor.systemOrange.cgColor
                ppBtn.contentTintColor = NSColor.systemOrange
            } else {
                ppBtn.title = "POST-FADER (Tail)"
                ppBtn.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.20).cgColor
                ppBtn.layer?.borderColor = NSColor.systemBlue.cgColor
                ppBtn.contentTintColor = NSColor.systemBlue
            }
        }

        // Beat < / Beat > Buttons
        if let prevBtn = Self.flexFxRefs.prevBeatButton {
            prevBtn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
        }
        if let nextBtn = Self.flexFxRefs.nextBeatButton {
            nextBtn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.7).cgColor
        }

        // 9. CoreAudio Streaming Routing Badge
        if let rBadge = Self.flexFxRefs.routingBadge {
            if s.isAudioStreaming {
                rBadge.stringValue = Localization.tr(
                    en: "  ● Audio-Loop AKTIV: Send Ch 9/10 → Return Ch 9/10  ",
                    de: "  ● Audio-Loop AKTIV: Send Ch 9/10 → Return Ch 9/10  "
                )
                rBadge.textColor = NSColor.systemTeal
                rBadge.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.18).cgColor
            } else {
                rBadge.stringValue = Localization.tr(
                    en: "  ○ CoreAudio: Warte auf Sixty-Eight Gerät...  ",
                    de: "  ○ CoreAudio: Warte auf Sixty-Eight Gerät...  "
                )
                rBadge.textColor = NSColor.systemOrange
                rBadge.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.18).cgColor
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

        RaneMidiLearnService.shared.addLearnModeObserver { [weak self] _ in
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
                self?.appendMidiLog("MIDI TRIGGER: [\(target.displayName)] live ausgeführt (Wert: \(val))")
                self?.updateFlexFxUi()
            }
        }
    }

    // MARK: - Action Handlers
    @objc func onModulePowerToggled(_ sender: NSSwitch) {
        let isPowerOn = (sender.state == .on)
        RaneFlexFxService.shared.isModuleEnabled = isPowerOn
        appendMidiLog("FlexFX Engine: Modul-Hauptschalter -> [\(isPowerOn ? "AKTIVIERT" : "ABGESCHALTET / BYPASS")]")
    }

    @objc func onFxButtonClicked(_ sender: NSButton) {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        if let fx = FlexFxType(rawValue: sender.tag) {
            RaneFlexFxService.shared.currentEffect = fx
            appendMidiLog("FlexFX Engine: Effekt ausgewählt -> [\(fx.displayName)]")
        }
    }

    @objc func onPrevBeatClicked() {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        RaneFlexFxService.shared.cycleBeatDivision(forward: false)
        appendMidiLog("FlexFX Engine: Beat Division -> [\(RaneFlexFxService.shared.currentDivision.label)]")
    }

    @objc func onNextBeatClicked() {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        RaneFlexFxService.shared.cycleBeatDivision(forward: true)
        appendMidiLog("FlexFX Engine: Beat Division -> [\(RaneFlexFxService.shared.currentDivision.label)]")
    }

    @objc func onBeatSegmentChanged(_ sender: NSSegmentedControl) {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        if let div = BeatDivision(rawValue: sender.selectedSegment) {
            RaneFlexFxService.shared.currentDivision = div
            appendMidiLog("FlexFX Engine: Beat Division -> [\(div.label)]")
        }
    }

    @objc func onFlexFxToggleClicked() {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        RaneFlexFxService.shared.isEnabled.toggle()
        appendMidiLog("FlexFX Engine: Status -> [\(RaneFlexFxService.shared.isEnabled ? "EIN" : "BYPASS")]")
    }

    @objc func onLinkToggleClicked() {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        RaneFlexFxService.shared.isLinkEnabled.toggle()
        appendMidiLog("Ableton Link: Status -> [\(RaneFlexFxService.shared.isLinkEnabled ? "AKTIV" : "STANDALONE")]")
    }

    @objc func onDryWetChanged(_ sender: NSSlider) {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.dryWet = val
        Self.flexFxRefs.dryWetBadge?.stringValue = "\(Int(round(val * 100.0)))%"
    }

    @objc func onDepthChanged(_ sender: NSSlider) {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        let val = sender.doubleValue / 100.0
        RaneFlexFxService.shared.depth = val
        Self.flexFxRefs.depthBadge?.stringValue = "\(Int(round(val * 100.0)))%"
    }

    @objc func onPrePostToggled() {
        guard RaneFlexFxService.shared.isModuleEnabled else { return }
        RaneFlexFxService.shared.isPreFader.toggle()
        let modeStr = RaneFlexFxService.shared.isPreFader ? "PRE-FADER (Bypass)" : "POST-FADER (Reverb/Delay Tail)"
        appendMidiLog("FlexFX Engine: Signal-Routing -> [\(modeStr)]")
        updateFlexFxUi()
    }
}
