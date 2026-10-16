/* SPDX-License-Identifier: MIT */
/* SystemStatusTab.swift - Tab 4: Subsystem diagnostics, service restart & status */

import Cocoa

extension MainWindowController {
    func buildSystemPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 10
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let diagContainerStack = NSStackView()
        diagContainerStack.orientation = .vertical
        diagContainerStack.alignment = .leading
        diagContainerStack.spacing = 10

        let sec1TopBar = createSectionTopBar(
            icon: "waveform.badge.magnifyingglass",
            title: Localization.tr(en: "macOS Audio & MIDI Subsystem Diagnostics", de: "macOS Audio- & MIDI-Subsystem Diagnose"),
            tintColor: .systemBlue
        )
        diagContainerStack.addArrangedSubview(sec1TopBar)

        let statusStack = NSStackView()
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 10

        statusLabel = createStatusRow(title: Localization.tr(en: "CoreAudio HAL Driver:", de: "CoreAudio HAL Treiber:"), stack: statusStack)
        kextStatusLabel = createStatusRow(title: Localization.tr(en: "Legacy Rane Kext:", de: "Legacy Rane Kext:"), stack: statusStack)
        agentStatusLabel = createStatusRow(title: Localization.tr(en: "CoreMIDI LaunchAgent:", de: "CoreMIDI LaunchAgent:"), stack: statusStack)
        deviceStatusLabel = createStatusRow(title: Localization.tr(en: "Connected Mixer:", de: "Angeschlossener Mixer:"), stack: statusStack)
        firmwareStatusLabel = createStatusRow(title: Localization.tr(en: "Mixer Firmware:", de: "Mixer Firmware:"), stack: statusStack)
        cpuStatusLabel = createStatusRow(title: Localization.tr(en: "System CPU Load:", de: "System CPU-Auslastung:"), stack: statusStack)

        let statusCard = statusStack.wrapInCard(
            cornerRadius: 10,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.176, green: 0.180, blue: 0.200, alpha: 1.0),
            padding: NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        )

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 10
        btnRow.distribution = .fillEqually

        let rstBtn = NSButton(title: Localization.tr(en: "🔄 Restart Services", de: "🔄 Dienst Neu Starten"), target: self, action: #selector(onRestartDriverClicked))
        rstBtn.bezelStyle = .rounded
        rstBtn.controlSize = .regular

        let diagBtn = NSButton(title: Localization.tr(en: "🔍 Refresh", de: "🔍 Aktualisieren"), target: self, action: #selector(onDiagnoseClicked))
        diagBtn.bezelStyle = .rounded
        diagBtn.controlSize = .regular

        let ledTitle = isLedTestRunning ? Localization.tr(en: "⏹ Stop LED", de: "⏹ LED Stop")
                                        : Localization.tr(en: "💡 LED Test", de: "💡 LED-Check")
        let ledBtn = NSButton(title: ledTitle, target: self, action: #selector(onLedTestClicked))
        ledBtn.bezelStyle = .rounded
        ledBtn.controlSize = .regular
        ledBtn.isEnabled = RaneMidiService.shared.isConnected
        self.ledTestButton = ledBtn

        let stressTitle = isStressTestRunning ? Localization.tr(en: "⏹ Stop Stress", de: "⏹ Stress Stop")
                                              : Localization.tr(en: "🔥 Stresstest", de: "🔥 Stresstest")
        let stressBtn = NSButton(title: stressTitle, target: self, action: #selector(onStressTestClicked))
        stressBtn.bezelStyle = .rounded
        stressBtn.controlSize = .regular
        stressBtn.isEnabled = RaneMidiService.shared.isConnected
        self.stressTestButton = stressBtn

        btnRow.addArrangedSubview(rstBtn)
        btnRow.addArrangedSubview(diagBtn)
        btnRow.addArrangedSubview(ledBtn)
        btnRow.addArrangedSubview(stressBtn)

        diagContainerStack.addArrangedSubview(statusCard)
        statusCard.widthAnchor.constraint(equalTo: diagContainerStack.widthAnchor).isActive = true
        diagContainerStack.addArrangedSubview(btnRow)
        btnRow.widthAnchor.constraint(equalTo: diagContainerStack.widthAnchor).isActive = true

        let diagInsetCard = diagContainerStack.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        )
        page.addArrangedSubview(diagInsetCard)
        diagInsetCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        // Section: Hardware OLED Startup Greeting (5s Display)
        let oledOuter = NSStackView()
        oledOuter.orientation = .vertical
        oledOuter.alignment = .leading
        oledOuter.spacing = 8

        let oledTopBar = createSectionTopBar(
            icon: "display",
            title: Localization.tr(en: "Hardware OLED Startup Greeting (5s Display & Preset)", de: "Hardware OLED Begrüßungstext (5 Sek. beim App-Start & im Preset)"),
            tintColor: .systemGreen
        )
        oledOuter.addArrangedSubview(oledTopBar)

        let oledRow = NSStackView()
        oledRow.orientation = .horizontal
        oledRow.alignment = .centerY
        oledRow.spacing = 10

        let line1Lbl = NSTextField(labelWithString: Localization.tr(en: "Line 1 (14 chars):", de: "Zeile 1 (max. 14 Z.):"))
        line1Lbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        line1Lbl.textColor = NSColor(white: 0.78, alpha: 1.0)

        let line1Field = NSTextField(string: RaneMidiService.shared.oledGreetingLine1)
        line1Field.placeholderString = "HENRY'S RANE68"
        line1Field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        line1Field.textColor = NSColor.systemGreen
        line1Field.backgroundColor = NSColor(red: 0.08, green: 0.11, blue: 0.09, alpha: 1.0)
        line1Field.isBezeled = true
        line1Field.bezelStyle = .roundedBezel
        line1Field.target = self
        line1Field.action = #selector(onOledGreetingFieldEdited)
        line1Field.translatesAutoresizingMaskIntoConstraints = false
        line1Field.widthAnchor.constraint(equalToConstant: 155).isActive = true
        self.oledGreetingLine1Field = line1Field

        let line2Lbl = NSTextField(labelWithString: Localization.tr(en: "Line 2 (14 chars):", de: "Zeile 2 (max. 14 Z.):"))
        line2Lbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        line2Lbl.textColor = NSColor(white: 0.78, alpha: 1.0)

        let line2Field = NSTextField(string: RaneMidiService.shared.oledGreetingLine2)
        line2Field.placeholderString = "WELCOME BACK!"
        line2Field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        line2Field.textColor = NSColor.systemGreen
        line2Field.backgroundColor = NSColor(red: 0.08, green: 0.11, blue: 0.09, alpha: 1.0)
        line2Field.isBezeled = true
        line2Field.bezelStyle = .roundedBezel
        line2Field.target = self
        line2Field.action = #selector(onOledGreetingFieldEdited)
        line2Field.translatesAutoresizingMaskIntoConstraints = false
        line2Field.widthAnchor.constraint(equalToConstant: 155).isActive = true
        self.oledGreetingLine2Field = line2Field

        let testOledBtn = NSButton(
            title: Localization.tr(en: "📺 Save & Show 5s on Mixer", de: "📺 Speichern & 5s am Mixer zeigen"),
            target: self,
            action: #selector(onSaveAndTestOledGreetingClicked)
        )
        testOledBtn.bezelStyle = .rounded
        testOledBtn.controlSize = .regular

        oledRow.addArrangedSubview(line1Lbl)
        oledRow.addArrangedSubview(line1Field)
        oledRow.addArrangedSubview(line2Lbl)
        oledRow.addArrangedSubview(line2Field)
        oledRow.addArrangedSubview(testOledBtn)

        let oledInnerCard = oledRow.wrapInCard(
            cornerRadius: 8,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.176, green: 0.180, blue: 0.200, alpha: 1.0),
            padding: NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        )
        oledOuter.addArrangedSubview(oledInnerCard)
        oledInnerCard.widthAnchor.constraint(equalTo: oledOuter.widthAnchor).isActive = true

        let oledInsetCard = oledOuter.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        )
        page.addArrangedSubview(oledInsetCard)
        oledInsetCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let sec2Outer = NSStackView()
        sec2Outer.orientation = .vertical
        sec2Outer.alignment = .leading
        sec2Outer.spacing = 10

        let sec2TopBar = createSectionTopBar(
            icon: "doc.text.magnifyingglass",
            title: Localization.tr(en: "Driver Log & Diagnostics", de: "Treiber Meldungen & Protokoll"),
            tintColor: .systemOrange
        )
        sec2Outer.addArrangedSubview(sec2TopBar)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        sysLogTextView = NSTextView()
        sysLogTextView.isEditable = false
        sysLogTextView.backgroundColor = NSColor(red: 0.10, green: 0.105, blue: 0.12, alpha: 1.0)
        sysLogTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sysLogTextView.textColor = NSColor(white: 0.90, alpha: 1.0)
        scroll.documentView = sysLogTextView

        let innerScrollCard = scroll.wrapInCard(
            cornerRadius: 8,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.10, green: 0.105, blue: 0.12, alpha: 1.0),
            padding: NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        )
        sec2Outer.addArrangedSubview(innerScrollCard)
        innerScrollCard.widthAnchor.constraint(equalTo: sec2Outer.widthAnchor).isActive = true

        let scrollCard = sec2Outer.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        )
        page.addArrangedSubview(scrollCard)
        scrollCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        page.addArrangedSubview(bottomSpacer)

        return page
    }

    // MARK: - Action Handlers (Tab 4)
    @objc func onOledGreetingFieldEdited() {
        let l1 = String((oledGreetingLine1Field?.stringValue ?? "").prefix(14))
        let l2 = String((oledGreetingLine2Field?.stringValue ?? "").prefix(14))
        oledGreetingLine1Field?.stringValue = l1
        oledGreetingLine2Field?.stringValue = l2
        RaneMidiService.shared.oledGreetingLine1 = l1
        RaneMidiService.shared.oledGreetingLine2 = l2
    }

    @objc func onSaveAndTestOledGreetingClicked() {
        onOledGreetingFieldEdited()
        let l1 = RaneMidiService.shared.oledGreetingLine1
        let l2 = RaneMidiService.shared.oledGreetingLine2
        RaneMidiService.shared.showOledGreeting(durationSeconds: 5.0)
        appendSysLog("OLED Begrüßungstext gespeichert & für 5 Sek. gesendet: [\(l1)] / [\(l2)]")
    }

    @objc func onRestartDriverClicked() {
        appendSysLog("Starte CoreAudio & MIDI Dienst neu...")
        DispatchQueue.global().async {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "killall -9 coreaudiod com.apple.audio.Core-Audio-Driver-Service 2>/dev/null; launchctl kickstart -k system/com.apple.audio.coreaudiod 2>/dev/null"]
            try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                self.appendSysLog("Dienste erfolgreich neu gestartet.")
                self.refreshStatus()
            }
        }
    }

    @objc func onDiagnoseClicked() {
        appendSysLog("Aktualisiere System-Diagnose...")
        refreshStatus()
    }
}
