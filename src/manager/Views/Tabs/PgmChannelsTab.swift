/* SPDX-License-Identifier: MIT */
/* PgmChannelsTab.swift - Tab 2: PGM Channels 1–4 routing & sensitivity controls */

import Cocoa

extension MainWindowController {
    func buildPgmPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 16
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let secHeader = createSectionHeader(title: Localization.tr(en: "PGM Channels 1–4 Hardware Configuration", de: "Hardware Eingangskanäle (PGM 1–4)"))
        page.addArrangedSubview(secHeader)
        secHeader.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        // Outer Dark Inset Container
        let insetOuter = NSStackView()
        insetOuter.orientation = .vertical
        insetOuter.alignment = .leading
        insetOuter.spacing = 14

        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        let eqIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: nil) {
            eqIcon.image = img.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        }
        eqIcon.contentTintColor = NSColor.systemBlue
        let eqTitle = NSTextField(labelWithString: Localization.tr(en: "Hardware Phono/Line Input Stages & Routing", de: "Hardware Phono/Line Eingangsstufen & Routing"))
        eqTitle.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        topBar.addArrangedSubview(eqIcon)
        topBar.addArrangedSubview(eqTitle)
        insetOuter.addArrangedSubview(topBar)

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

            // 1. Hardware Input Type Badge
            let inTypeTitle = NSTextField(labelWithString: Localization.tr(en: "Hardware Switch:", de: "Hardware Schalter:"))
            inTypeTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            inTypeTitle.textColor = NSColor.secondaryLabelColor
            let inTypeBadge = NSTextField(labelWithString: "  LINE (CD)  ")
            inTypeBadge.font = NSFont.boldSystemFont(ofSize: 11)
            inTypeBadge.textColor = NSColor.systemBlue
            inTypeBadge.wantsLayer = true
            inTypeBadge.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
            inTypeBadge.layer?.cornerRadius = 4

            chStack.addArrangedSubview(inTypeTitle)
            chStack.addArrangedSubview(inTypeBadge)

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

            let chCard = chStack.wrapInCard(cornerRadius: 10, padding: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
            rowOfChannels.addArrangedSubview(chCard)

            channels.append(PgmChannelControls(
                channelNumber: ch,
                container: chCard,
                inputBadge: inTypeBadge,
                phonoPopup: sensPopup,
                resonanceSegment: resSegment,
                recordSegment: recSegment
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

    @objc func onRecordSourceChanged(_ sender: NSSegmentedControl) {
        let ch = sender.tag
        let sel: UInt8 = UInt8(sender.selectedSegment + 1)
        let ccNum: UInt8 = (ch == 1 ? 23 : (ch == 2 ? 26 : (ch == 3 ? 29 : 32)))
        sendUserCC(cc: ccNum, value: sel)
        let name = (sel == 1 ? "PH/CD" : (sel == 2 ? "Post-Fader" : "AUX"))
        appendMidiLog("OUT: PGM \(ch) Record Select -> CC#\(ccNum)=\(sel) (\(name)) [Warte auf Quittung...]")
    }
}
