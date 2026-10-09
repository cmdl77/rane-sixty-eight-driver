/* SPDX-License-Identifier: MIT */
/* SystemStatusTab.swift - Tab 4: Subsystem diagnostics, service restart & status */

import Cocoa

extension MainWindowController {
    func buildSystemPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 16
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let sHeader = createSectionHeader(title: Localization.tr(en: "macOS Audio & MIDI Subsystem Diagnostics", de: "macOS Audio- & MIDI-Subsystem Diagnose"))
        page.addArrangedSubview(sHeader)
        sHeader.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let statusStack = NSStackView()
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 10

        statusLabel = createStatusRow(title: Localization.tr(en: "CoreAudio HAL Driver:", de: "CoreAudio HAL Treiber:"), stack: statusStack)
        kextStatusLabel = createStatusRow(title: Localization.tr(en: "Legacy Rane Kext:", de: "Legacy Rane Kext:"), stack: statusStack)
        agentStatusLabel = createStatusRow(title: Localization.tr(en: "CoreMIDI LaunchAgent:", de: "CoreMIDI LaunchAgent:"), stack: statusStack)
        deviceStatusLabel = createStatusRow(title: Localization.tr(en: "Connected Mixer:", de: "Angeschlossener Mixer:"), stack: statusStack)

        let statusCard = statusStack.wrapInCard(padding: NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18))
        page.addArrangedSubview(statusCard)
        statusCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 12

        let rstBtn = NSButton(title: Localization.tr(en: "🔄 Restart CoreAudio & MIDI Services", de: "🔄 CoreAudio & MIDI Dienst Neu Starten"), target: self, action: #selector(onRestartDriverClicked))
        rstBtn.bezelStyle = .rounded
        rstBtn.controlSize = .regular

        let diagBtn = NSButton(title: Localization.tr(en: "🔍 Refresh Diagnostics", de: "🔍 Diagnose Aktualisieren"), target: self, action: #selector(onDiagnoseClicked))
        diagBtn.bezelStyle = .rounded
        diagBtn.controlSize = .regular

        let ledTitle = isLedTestRunning ? Localization.tr(en: "⏹ Stop LED Check", de: "⏹ LED-Test Beenden")
                                        : Localization.tr(en: "💡 Mixer LED Light Test", de: "💡 Mixer LED-Lichtcheck")
        let ledBtn = NSButton(title: ledTitle, target: self, action: #selector(onLedTestClicked))
        ledBtn.bezelStyle = .rounded
        ledBtn.controlSize = .regular
        ledBtn.isEnabled = RaneMidiService.shared.isConnected
        self.ledTestButton = ledBtn

        let stressTitle = isStressTestRunning ? Localization.tr(en: "⏹ Stop Stress Test", de: "⏹ Stresstest Beenden")
                                              : Localization.tr(en: "🔥 Hardware Stress Test", de: "🔥 Hardware-Stresstest")
        let stressBtn = NSButton(title: stressTitle, target: self, action: #selector(onStressTestClicked))
        stressBtn.bezelStyle = .rounded
        stressBtn.controlSize = .regular
        stressBtn.isEnabled = RaneMidiService.shared.isConnected
        self.stressTestButton = stressBtn

        btnRow.addArrangedSubview(rstBtn)
        btnRow.addArrangedSubview(diagBtn)
        btnRow.addArrangedSubview(ledBtn)
        btnRow.addArrangedSubview(stressBtn)
        page.addArrangedSubview(btnRow)

        let monHeader = createSectionHeader(title: Localization.tr(en: "Driver Log & Diagnostics", de: "Treiber Meldungen & Protokoll"))
        page.addArrangedSubview(monHeader)
        monHeader.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

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

        let scrollCard = scroll.wrapInInsetCard(padding: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
        page.addArrangedSubview(scrollCard)
        scrollCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        page.addArrangedSubview(bottomSpacer)

        return page
    }

    // MARK: - Action Handlers (Tab 4)
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
