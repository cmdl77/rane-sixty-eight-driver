/* SPDX-License-Identifier: MIT */
/* MixerAudioTab.swift - Tab 1: Mixer Audio, Tone, LCD & Latency Controls */

import Cocoa

extension MainWindowController {
    func buildPreferencesPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 16
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        // SECTION 1: HARDWARE CONTROLS & MONITOR
        let sec1Header = createSectionHeader(title: Localization.tr(en: "Hardware Controls & Monitor", de: "Hardware Bedienelemente & Monitor"))
        page.addArrangedSubview(sec1Header)
        sec1Header.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let card1Stack = NSStackView()
        card1Stack.orientation = .vertical
        card1Stack.alignment = .leading
        card1Stack.spacing = 10

        // Row 1: Button Backlight Switch
        backlightSwitch = NSSwitch()
        backlightSwitch.state = .on
        backlightSwitch.target = self
        backlightSwitch.action = #selector(onBacklightSwitchChanged)
        let rowBacklight = createSwitchRow(
            symbol: "lightbulb.fill",
            title: Localization.tr(en: "Button Backlight", de: "Tastenbeleuchtung (Button Backlight)"),
            subtitle: Localization.tr(en: "Backlight for all mixer buttons & cue buttons", de: "Hintergrundbeleuchtung aller Mixer-Tasten & Cue-Buttons"),
            toggle: backlightSwitch
        )
        card1Stack.addArrangedSubview(rowBacklight)
        rowBacklight.widthAnchor.constraint(equalTo: card1Stack.widthAnchor).isActive = true

        let div1 = createDivider()
        card1Stack.addArrangedSubview(div1)
        div1.widthAnchor.constraint(equalTo: card1Stack.widthAnchor).isActive = true

        // Row 2: LCD Contrast Slider
        lcdContrastSlider = NSSlider(value: 64, minValue: 0, maxValue: 127, target: self, action: #selector(onLcdContrastChanged))
        lcdContrastSlider.isContinuous = true
        lcdContrastBadge = createValueBadge(text: "50%")
        let rowLcd = createSliderRow(
            symbol: "display",
            title: Localization.tr(en: "LCD Display Contrast & Backlight", de: "LCD Display-Kontrast & Beleuchtung"),
            subtitle: Localization.tr(en: "Ratio of text to backlight intensity", de: "Verhältnis von Text- zu Hintergrundbeleuchtung"),
            slider: lcdContrastSlider,
            badge: lcdContrastBadge,
            minSymbol: "sun.min.fill",
            maxSymbol: "sun.max.fill"
        )
        card1Stack.addArrangedSubview(rowLcd)
        rowLcd.widthAnchor.constraint(equalTo: card1Stack.widthAnchor).isActive = true

        let div2 = createDivider()
        card1Stack.addArrangedSubview(div2)
        div2.widthAnchor.constraint(equalTo: card1Stack.widthAnchor).isActive = true

        // Row 3: Phones Tone Low Slider
        lowToneSlider = NSSlider(value: 64, minValue: 0, maxValue: 127, target: self, action: #selector(onLowToneChanged))
        lowToneSlider.isContinuous = true
        lowToneBadge = createValueBadge(text: "0.0 dB")
        let rowLow = createSliderRow(
            symbol: "headphones",
            title: Localization.tr(en: "Phones Tone Low (Bass)", de: "Phones Tone Low (Bass)"),
            subtitle: Localization.tr(en: "Headphone bass frequency response (-6.0 dB to +6.0 dB)", de: "Kopfhörer Bass-Frequenzgang (-6.0 dB bis +6.0 dB)"),
            slider: lowToneSlider,
            badge: lowToneBadge,
            minSymbol: "speaker.wave.1.fill",
            maxSymbol: "speaker.wave.3.fill"
        )
        card1Stack.addArrangedSubview(rowLow)
        rowLow.widthAnchor.constraint(equalTo: card1Stack.widthAnchor).isActive = true

        let div3 = createDivider()
        card1Stack.addArrangedSubview(div3)
        div3.widthAnchor.constraint(equalTo: card1Stack.widthAnchor).isActive = true

        // Row 4: Phones Tone High Slider
        highToneSlider = NSSlider(value: 64, minValue: 0, maxValue: 127, target: self, action: #selector(onHighToneChanged))
        highToneSlider.isContinuous = true
        highToneBadge = createValueBadge(text: "0.0 dB")
        let rowHigh = createSliderRow(
            symbol: "headphones",
            title: Localization.tr(en: "Phones Tone High (Treble)", de: "Phones Tone High (Höhen)"),
            subtitle: Localization.tr(en: "Headphone treble frequency response (-6.0 dB to +6.0 dB)", de: "Kopfhörer Höhen-Frequenzgang (-6.0 dB bis +6.0 dB)"),
            slider: highToneSlider,
            badge: highToneBadge,
            minSymbol: "speaker.wave.1.fill",
            maxSymbol: "speaker.wave.3.fill"
        )
        card1Stack.addArrangedSubview(rowHigh)
        rowHigh.widthAnchor.constraint(equalTo: card1Stack.widthAnchor).isActive = true

        let card1 = card1Stack.wrapInCard()
        page.addArrangedSubview(card1)
        card1.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        // SECTION 2: USB ROUTING & LATENCY
        let sec2Header = createSectionHeader(title: Localization.tr(en: "USB Audio Routing & Interfaces", de: "USB Audio Routing & Schnittstellen"))
        page.addArrangedSubview(sec2Header)
        sec2Header.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let card2Stack = NSStackView()
        card2Stack.orientation = .vertical
        card2Stack.alignment = .leading
        card2Stack.spacing = 10

        // Row 5: USB-6 Record Source Segmented
        usb6RecordSegment = NSSegmentedControl(labels: ["  Main Mix  ", "  Mic 1  ", "  Mic 2  "], trackingMode: .selectOne, target: self, action: #selector(onUsb6RecordSegmentChanged))
        usb6RecordSegment.selectedSegment = 0
        usb6RecordSegment.controlSize = .regular
        let rowUsb6 = createControlRow(
            symbol: "waveform",
            title: Localization.tr(en: "USB-6 Record Source (Pair 11–12)", de: "USB-6 Record Quelle (Paar 11–12)"),
            subtitle: Localization.tr(en: "Signal assignment for the 6th USB stereo recording pair", de: "Signalzuweisung für das sechste USB-Aufnahme-Stereopaar"),
            control: usb6RecordSegment
        )
        card2Stack.addArrangedSubview(rowUsb6)
        rowUsb6.widthAnchor.constraint(equalTo: card2Stack.widthAnchor).isActive = true

        let div4 = createDivider()
        card2Stack.addArrangedSubview(div4)
        div4.widthAnchor.constraint(equalTo: card2Stack.widthAnchor).isActive = true

        // Row 6: USB Audio Buffer Size
        let defaultBufTitle = Localization.tr(en: "5 ms (Default)", de: "5 ms (Standard)")
        bufferSizePopup = NSPopUpButton(title: defaultBufTitle, target: self, action: #selector(onBufferSizePopupChanged))
        bufferSizePopup.addItems(withTitles: [
            Localization.tr(en: "1 ms (Ultra Low)", de: "1 ms (Extrem niedrig)"),
            Localization.tr(en: "2 ms (Pro DJ / Low Latency)", de: "2 ms (Turniertauglich)"),
            Localization.tr(en: "5 ms (Default)", de: "5 ms (Standard)"),
            Localization.tr(en: "8 ms (Safe)", de: "8 ms (Sicher)"),
            "10 ms",
            "15 ms",
            Localization.tr(en: "20 ms (High Stability)", de: "20 ms (Hohe Stabilität)")
        ])
        bufferSizePopup.selectItem(at: 2)
        let rowBuf = createControlRow(
            symbol: "speedometer",
            title: Localization.tr(en: "USB Audio Buffer Size (Latency)", de: "USB Audio Puffergröße (Latenz)"),
            subtitle: Localization.tr(en: "Buffer latency for live scratching & DVS performance", de: "Latenz für Live-Scratching & DVS-Performance"),
            control: bufferSizePopup
        )
        card2Stack.addArrangedSubview(rowBuf)
        rowBuf.widthAnchor.constraint(equalTo: card2Stack.widthAnchor).isActive = true

        let div5 = createDivider()
        card2Stack.addArrangedSubview(div5)
        div5.widthAnchor.constraint(equalTo: card2Stack.widthAnchor).isActive = true

        // Row 7: USB Status
        usbStatusBadge = NSTextField(labelWithString: Localization.tr(en: "  ● Port A Active (48 kHz Float)  ", de: "  ● Port A Aktiv (48 kHz Float)  "))
        usbStatusBadge.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        usbStatusBadge.textColor = NSColor.systemGreen
        usbStatusBadge.wantsLayer = true
        usbStatusBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        usbStatusBadge.layer?.cornerRadius = 5
        let rowUsbStat = createControlRow(
            symbol: "cable.connector",
            title: Localization.tr(en: "USB Interface Status", de: "USB Schnittstellen-Status"),
            subtitle: Localization.tr(en: "Active computer connection & control strip", de: "Aktive Computer-Verbindung & Bedienebene Computer A"),
            control: usbStatusBadge
        )
        card2Stack.addArrangedSubview(rowUsbStat)
        rowUsbStat.widthAnchor.constraint(equalTo: card2Stack.widthAnchor).isActive = true

        let card2 = card2Stack.wrapInCard()
        page.addArrangedSubview(card2)
        card2.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        page.addArrangedSubview(bottomSpacer)

        return page
    }

    // MARK: - Action Handlers (Tab 1)
    @objc func onLowToneChanged() {
        let lowVal = UInt8(lowToneSlider.integerValue)
        let lowDb = (Double(lowVal) - 64.0) / 64.0 * 6.0
        lowToneBadge.stringValue = String(format: "%+.1f dB", lowDb)

        if lowVal == lastLowVal { return }
        lastLowVal = lowVal

        sendSliderCCThrottled(cc: 35, value: lowVal)
        appendMidiLog("OUT: Headphone Tone Low -> CC#35=\(lowVal) (\(lowToneBadge.stringValue))")
    }

    @objc func onHighToneChanged() {
        let highVal = UInt8(highToneSlider.integerValue)
        let highDb = (Double(highVal) - 64.0) / 64.0 * 6.0
        highToneBadge.stringValue = String(format: "%+.1f dB", highDb)

        if highVal == lastHighVal { return }
        lastHighVal = highVal

        sendSliderCCThrottled(cc: 34, value: highVal)
        appendMidiLog("OUT: Headphone Tone High -> CC#34=\(highVal) (\(highToneBadge.stringValue))")
    }

    @objc func onBacklightSwitchChanged() {
        let isOn = (backlightSwitch.state == .on)
        let val: UInt8 = isOn ? 1 : 0
        sendUserCC(cc: 36, value: val)
        appendMidiLog("OUT: Button Backlight -> CC#36=\(val) (\(isOn ? "Ein" : "Aus")) [Warte auf Quittung...]")
    }

    @objc func onLcdContrastChanged() {
        let val = UInt8(lcdContrastSlider.integerValue)
        let pct = Int(round(Double(val) / 127.0 * 100.0))
        lcdContrastBadge.stringValue = "\(pct)%"

        if val == lastLcdVal { return }
        lastLcdVal = val

        sendSliderCCThrottled(cc: 37, value: val)
        appendMidiLog("OUT: LCD Kontrast -> CC#37=\(val) (\(pct)%)")
    }

    @objc func onUsb6RecordSegmentChanged() {
        let sel: UInt8 = UInt8(usb6RecordSegment.selectedSegment + 1)
        sendUserCC(cc: 33, value: sel)
        let name = (sel == 1 ? "Main Mix" : (sel == 2 ? "Mic 1" : "Mic 2"))
        appendMidiLog("OUT: USB-6 Record -> CC#33=\(sel) (\(name)) [Warte auf Quittung...]")
    }

    @objc func onBufferSizePopupChanged() {
        let title = bufferSizePopup.titleOfSelectedItem ?? ""
        appendSysLog("Buffer Size geändert auf: \(title)")
    }
}
