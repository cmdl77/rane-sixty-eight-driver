/* SPDX-License-Identifier: MIT */
/* PgmChannelsTab.swift - Tab 2: PGM Channels 1–4 routing & sensitivity controls */

import Cocoa

extension MainWindowController {
    func buildPgmPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 10
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        // Outer Dark Inset Container
        let insetOuter = NSStackView()
        insetOuter.orientation = .vertical
        insetOuter.alignment = .leading
        insetOuter.spacing = 14

        let topBarRow = NSStackView()
        topBarRow.orientation = .horizontal
        topBarRow.alignment = .centerY
        topBarRow.spacing = 10

        let topBar = createSectionTopBar(
            icon: "slider.vertical.3",
            title: Localization.tr(en: "Hardware Phono/Line Input Stages & Routing", de: "Hardware Phono/Line Eingangsstufen & Routing"),
            tintColor: .systemBlue
        )
        topBarRow.addArrangedSubview(topBar)

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topBarRow.addArrangedSubview(topSpacer)

        let fwBadge = NSTextField(labelWithString: Localization.tr(
            en: "  ⚪️ Filter Modes (SysEx 0x06): Requires FW v2.00 Custom  ",
            de: "  ⚪️ Filter-Modi (SysEx 0x06): Erfordert FW v2.00 Custom  "
        ))
        fwBadge.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .bold)
        fwBadge.textColor = NSColor.secondaryLabelColor
        fwBadge.wantsLayer = true
        fwBadge.layer?.cornerRadius = 5
        fwBadge.layer?.backgroundColor = NSColor(white: 0.25, alpha: 0.35).cgColor
        self.pgmFirmwareFeatureBadge = fwBadge
        topBarRow.addArrangedSubview(fwBadge)

        insetOuter.addArrangedSubview(topBarRow)
        topBarRow.widthAnchor.constraint(equalTo: insetOuter.widthAnchor).isActive = true

        let rowOfChannels = NSStackView()
        rowOfChannels.orientation = .horizontal
        rowOfChannels.distribution = .fillEqually
        rowOfChannels.spacing = 14

        channels.removeAll()

        for ch in 1...4 {
            let chStack = NSStackView()
            chStack.orientation = .vertical
            chStack.alignment = .leading
            chStack.spacing = 12

            // Header with channel number badge
            let header = NSStackView()
            header.orientation = .horizontal
            header.alignment = .centerY
            header.spacing = 8

            let chBadge = NSTextField(labelWithString: " PGM \(ch) ")
            chBadge.font = NSFont.boldSystemFont(ofSize: 12)
            chBadge.textColor = NSColor.white
            chBadge.wantsLayer = true
            chBadge.layer?.backgroundColor = NSColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1.0).cgColor
            chBadge.layer?.cornerRadius = 5

            let titleLbl = NSTextField(labelWithString: Localization.tr(en: "Channel Strip \(ch)", de: "Kanalzug \(ch)"))
            titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .bold)

            header.addArrangedSubview(chBadge)
            header.addArrangedSubview(titleLbl)
            chStack.addArrangedSubview(header)

            // 1. Hardware-Schalter: 2 getrennte, zentrierte Felder
            // Feld 1: Eingangswahl Rückseite (LINE (CD) oder PHONO / S/PDIF) - CC 112..115
            // Feld 2: Kanal-Quelle Drehschalter (PH/CD oder USB oder AUX) - CC 116..119
            let f1Title = NSTextField(labelWithString: Localization.tr(en: "1: Input (LINE / PHONO):", de: "1: Eingang (LINE / PHONO):"))
            f1Title.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            f1Title.textColor = NSColor.secondaryLabelColor
            f1Title.alignment = .center

            let inTypeBadge = PgmBadgeTextField(
                text: "LINE (CD)",
                font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                textColor: NSColor.systemBlue,
                bgColor: NSColor.systemBlue.withAlphaComponent(0.18),
                height: 20
            )

            let f2Title = NSTextField(labelWithString: Localization.tr(en: "2: Source (PH/CD, USB, AUX):", de: "2: Quelle (PH/CD / USB / AUX):"))
            f2Title.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            f2Title.textColor = NSColor.secondaryLabelColor
            f2Title.alignment = .center

            let defaultSourceText = (ch == 1 ? "USB 1" : (ch == 2 ? "USB 2" : (ch == 3 ? "USB 3" : "USB 4")))
            let sourceBadge = PgmBadgeTextField(
                text: defaultSourceText,
                font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                textColor: NSColor.systemTeal,
                bgColor: NSColor.systemTeal.withAlphaComponent(0.18),
                height: 20
            )

            chStack.addArrangedSubview(f1Title)
            f1Title.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true
            chStack.addArrangedSubview(inTypeBadge)
            inTypeBadge.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            chStack.addArrangedSubview(f2Title)
            f2Title.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true
            chStack.addArrangedSubview(sourceBadge)
            sourceBadge.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            let div1 = createDivider()
            chStack.addArrangedSubview(div1)
            div1.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            // 2. Phono Gain Sensitivity
            let sensTitle = NSTextField(labelWithString: Localization.tr(en: "Phono Sensitivity:", de: "Phono-Empfindlichkeit:"))
            sensTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            sensTitle.textColor = NSColor.secondaryLabelColor
            let sensPopup = NSPopUpButton(title: "5.0 mV", target: self, action: #selector(onPhonoSensPopupChanged(_:)))
            sensPopup.tag = ch
            sensPopup.controlSize = .small
            let sensOptions = [
                "2.5 mV (+12.0 dB)", "3.0 mV (+10.5 dB)", "3.5 mV (+9.1 dB)", "4.0 mV (+8.0 dB)",
                "4.5 mV (+6.9 dB)",  "5.0 mV (+6.0 dB)",   "5.5 mV (+5.2 dB)", "6.0 mV (+4.4 dB)",
                "6.5 mV (+3.7 dB)",  "7.0 mV (+3.1 dB)",   "7.5 mV (+2.5 dB)", "8.0 mV (+1.9 dB)",
                "8.5 mV (+1.4 dB)",  "9.0 mV (+0.9 dB)",   "9.5 mV (+0.5 dB)", "10.0 mV (0.0 dB)"
            ]
            sensPopup.addItems(withTitles: sensOptions)
            sensPopup.selectItem(at: 5)
            chStack.addArrangedSubview(sensTitle)
            chStack.addArrangedSubview(sensPopup)
            sensPopup.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            let div2 = createDivider()
            chStack.addArrangedSubview(div2)
            div2.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            // 3. Filter Resonance
            let resTitle = NSTextField(labelWithString: Localization.tr(en: "Filter Resonance:", de: "Filter-Resonanz:"))
            resTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            resTitle.textColor = NSColor.secondaryLabelColor
            let resSegment = NSSegmentedControl(labels: [Localization.tr(en: " Low ", de: " Low "), Localization.tr(en: " High ", de: " High ")], trackingMode: .selectOne, target: self, action: #selector(onFilterResChanged(_:)))
            resSegment.tag = ch
            resSegment.controlSize = .small
            resSegment.selectedSegment = 0
            chStack.addArrangedSubview(resTitle)
            chStack.addArrangedSubview(resSegment)
            resSegment.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            // 3b. Hardware Filter Mode (Firmware SysEx 0x06)
            let fModeTitle = NSTextField(labelWithString: Localization.tr(en: "Filter Mode (Knob):", de: "Filter-Modus (Poti):"))
            fModeTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            fModeTitle.textColor = NSColor.secondaryLabelColor
            let fModePopup = NSPopUpButton(title: "", target: self, action: #selector(onFilterModePopupChanged(_:)))
            fModePopup.tag = ch
            fModePopup.controlSize = .small
            fModePopup.addItems(withTitles: [
                Localization.tr(en: "Normal (LP + HP)", de: "Normal (LP + HP)"),
                Localization.tr(en: "Low-Pass Only (270°)", de: "Nur Low-Pass (270°)"),
                Localization.tr(en: "High-Pass Only (270°)", de: "Nur High-Pass (270°)"),
                Localization.tr(en: "Filter OFF (MIDI Only)", de: "Filter Aus (Nur MIDI)")
            ])
            let savedFilterMode = UserDefaults.standard.integer(forKey: "RaneSixtyEight_FilterMode_PGM\(ch)")
            fModePopup.selectItem(at: max(0, min(3, savedFilterMode)))
            chStack.addArrangedSubview(fModeTitle)
            chStack.addArrangedSubview(fModePopup)
            fModePopup.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            let div3 = createDivider()
            chStack.addArrangedSubview(div3)
            div3.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            // 4. USB Record Source
            let recTitle = NSTextField(labelWithString: Localization.tr(en: "USB Record Source:", de: "USB Record-Quelle:"))
            recTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            recTitle.textColor = NSColor.secondaryLabelColor
            let recSegment = NSSegmentedControl(labels: ["PH/CD", "Post", "AUX"], trackingMode: .selectOne, target: self, action: #selector(onRecordSourceChanged(_:)))
            recSegment.tag = ch
            recSegment.controlSize = .small
            recSegment.selectedSegment = 0
            chStack.addArrangedSubview(recTitle)
            chStack.addArrangedSubview(recSegment)
            recSegment.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            let div4 = createDivider()
            chStack.addArrangedSubview(div4)
            div4.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            // 5. Crossfader Position (Hardware-Anzeige im gleichen Badge-Stil wie oben)
            let xfTitle = NSTextField(labelWithString: Localization.tr(en: "Crossfader (A / POST / B):", de: "Crossfader (A / POST / B):"))
            xfTitle.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            xfTitle.textColor = NSColor.secondaryLabelColor
            xfTitle.alignment = .center

            let xfBadge = PgmBadgeTextField(
                text: "POST",
                font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                textColor: NSColor(white: 0.88, alpha: 1.0),
                bgColor: NSColor(white: 0.35, alpha: 0.25),
                height: 20
            )

            chStack.addArrangedSubview(xfTitle)
            xfTitle.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true
            chStack.addArrangedSubview(xfBadge)
            xfBadge.widthAnchor.constraint(equalTo: chStack.widthAnchor).isActive = true

            let chCard = chStack.wrapInCard(cornerRadius: 10, padding: NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
            rowOfChannels.addArrangedSubview(chCard)

            channels.append(PgmChannelControls(
                channelNumber: ch,
                container: chCard,
                inputTypeBadge: inTypeBadge,
                sourceBadge: sourceBadge,
                phonoPopup: sensPopup,
                resonanceSegment: resSegment,
                filterModePopup: fModePopup,
                recordSegment: recSegment,
                crossfaderBadge: xfBadge
            ))
        }

        insetOuter.addArrangedSubview(rowOfChannels)
        rowOfChannels.widthAnchor.constraint(equalTo: insetOuter.widthAnchor).isActive = true

        let insetCard = insetOuter.wrapInInsetCard()
        page.addArrangedSubview(insetCard)
        insetCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        page.addArrangedSubview(bottomSpacer)

        return page
    }

    // MARK: - Action Handlers (Tab 2)
    @objc func onPhonoSensPopupChanged(_ sender: NSPopUpButton) {
        let ch = sender.tag
        let ccNum: UInt8 = (ch == 1 ? 21 : (ch == 2 ? 24 : (ch == 3 ? 27 : 30)))
        let val = UInt8(sender.indexOfSelectedItem)
        sendUserCC(cc: ccNum, value: val)
        appendMidiLog("OUT: PGM \(ch) Phono Sensitivity -> CC#\(ccNum)=\(val) (\(sender.titleOfSelectedItem ?? "")) [Warte auf Quittung...]")
    }

    @objc func onFilterResChanged(_ sender: NSSegmentedControl) {
        let ch = sender.tag
        let isHigh = (sender.selectedSegment == 1)
        let ccNum: UInt8 = (ch == 1 ? 22 : (ch == 2 ? 25 : (ch == 3 ? 28 : 31)))
        let val: UInt8 = isHigh ? 127 : 0
        sendUserCC(cc: ccNum, value: val)
        appendMidiLog("OUT: PGM \(ch) Filter Resonance -> CC#\(ccNum)=\(val) (\(isHigh ? "High" : "Low")) [Warte auf Quittung...]")
    }

    @objc func onFilterModePopupChanged(_ sender: NSPopUpButton) {
        let ch = sender.tag
        let mode = max(0, min(3, sender.indexOfSelectedItem))
        UserDefaults.standard.set(mode, forKey: "RaneSixtyEight_FilterMode_PGM\(ch)")
        RaneMidiService.shared.sendChannelFilterMode(channel: ch, mode: mode)
        let arg = UInt8(((ch - 1) & 0x03) << 4 | (mode & 0x03))
        let modeTitle = sender.titleOfSelectedItem ?? ""
        appendMidiLog(String(format: "OUT: PGM %d Filter-Modus -> %@ [SysEx F0 17 06 %02X F7]", ch, modeTitle, arg))
    }

    @objc func onRecordSourceChanged(_ sender: NSSegmentedControl) {
        let ch = sender.tag
        let sel: UInt8 = UInt8(sender.selectedSegment + 1)
        let ccNum: UInt8 = (ch == 1 ? 23 : (ch == 2 ? 26 : (ch == 3 ? 29 : 32)))
        sendUserCC(cc: ccNum, value: sel)
        let name = (sel == 1 ? "PH/CD" : (sel == 2 ? "Post-Fader" : "AUX"))
        appendMidiLog("OUT: PGM \(ch) Record Select -> CC#\(ccNum)=\(sel) (\(name)) [Warte auf Quittung...]")
    }
}
