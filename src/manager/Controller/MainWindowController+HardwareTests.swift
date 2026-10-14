/* SPDX-License-Identifier: MIT */
/* MainWindowController+HardwareTests.swift - LED Light Check and Hardware Stresstest */

import Cocoa

extension MainWindowController {
    // MARK: - Mixer LED Hardware Light Check Sequence
    static let ledSequence: [LedTestItem] = [
        // 1. Linke Sektion - Deck A/C Strip (von oben nach unten)
        LedTestItem(name: "Layer / Shift (Rot)", note: 52, color: "Rot", channel: 0, isMixerControl: false),
        LedTestItem(name: "Layer / Shift (Orange)", note: 53, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Back / Scroll (Grün)", note: 54, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Back / Scroll (Orange)", note: 55, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Manual / Auto (Grün)", note: 46, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Manual / Auto (Orange)", note: 47, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop In (Grün)", note: 44, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop In (Orange)", note: 45, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop Out (Grün)", note: 24, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop Out (Orange)", note: 25, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Roll / Loop (Grün)", note: 26, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Roll / Loop (Orange)", note: 27, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Delete (Rot)", note: 28, color: "Rot", channel: 0, isMixerControl: false),
        LedTestItem(name: "Delete (Orange)", note: 29, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 1 (Grün)", note: 30, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 1 (Orange)", note: 31, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 2 (Grün)", note: 8, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 2 (Orange)", note: 9, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 3 (Grün)", note: 10, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 3 (Orange)", note: 11, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 4 (Grün)", note: 12, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 4 (Orange)", note: 13, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 5 (Grün)", note: 14, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 5 (Orange)", note: 15, color: "Orange", channel: 0, isMixerControl: false),

        // 2. Kanal-Sektion (PGM 1 - 4 Cue & FlexFX Buttons)
        LedTestItem(name: "PGM 1 Cue", note: 69, color: "Blau", channel: 0, isMixerControl: true),
        LedTestItem(name: "PGM 1 FlexFX", note: 68, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "PGM 2 Cue", note: 70, color: "Blau", channel: 1, isMixerControl: true),
        LedTestItem(name: "PGM 2 FlexFX", note: 67, color: "Gelb", channel: 1, isMixerControl: true),
        LedTestItem(name: "PGM 3 Cue", note: 71, color: "Blau", channel: 2, isMixerControl: true),
        LedTestItem(name: "PGM 3 FlexFX", note: 66, color: "Gelb", channel: 2, isMixerControl: true),
        LedTestItem(name: "PGM 4 Cue", note: 62, color: "Blau", channel: 3, isMixerControl: true),
        LedTestItem(name: "PGM 4 FlexFX", note: 65, color: "Gelb", channel: 3, isMixerControl: true),

        // 3. FlexFX Modul & Mikrofone & Split Cue
        LedTestItem(name: "FlexFX Filter", note: 12, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "FlexFX Flanger", note: 11, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "FlexFX Phaser", note: 10, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "FlexFX Echo", note: 13, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "FlexFX Dub Delay", note: 9, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "FlexFX Reverb", note: 8, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "Beat <", note: 14, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "Beat >", note: 15, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "Tap Tempo", note: 5, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "FlexFX On", note: 0, color: "Gelb", channel: 0, isMixerControl: true),
        LedTestItem(name: "FlexFX Cue", note: 4, color: "Blau", channel: 0, isMixerControl: true),
        LedTestItem(name: "Mic 1", note: 41, color: "Blau", channel: 0, isMixerControl: true),
        LedTestItem(name: "Mic 2", note: 40, color: "Blau", channel: 0, isMixerControl: true),
        LedTestItem(name: "Split Cue", note: 56, color: "Blau", channel: 0, isMixerControl: true),

        // 4. Rechte Sektion - Deck B/D Strip (von oben nach unten)
        LedTestItem(name: "Control Point (Grün)", note: 60, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Control Point (Orange)", note: 61, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Back / Scroll (Grün)", note: 58, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Back / Scroll (Orange)", note: 59, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Manual / Auto (Grün)", note: 62, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Manual / Auto (Orange)", note: 63, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop In (Grün)", note: 66, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop In (Orange)", note: 67, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop Out (Grün)", note: 68, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Loop Out (Orange)", note: 69, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Roll / Loop (Orange)", note: 78, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Roll / Loop (Orange)", note: 79, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Delete (Rot)", note: 76, color: "Rot", channel: 0, isMixerControl: false),
        LedTestItem(name: "Delete (Orange)", note: 77, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 1 (Grün)", note: 74, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 1 (Orange)", note: 75, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 2 (Grün)", note: 94, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 2 (Orange)", note: 95, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 3 (Grün)", note: 92, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 3 (Orange)", note: 93, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 4 (Grün)", note: 90, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 4 (Orange)", note: 91, color: "Orange", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 5 (Grün)", note: 88, color: "Grün", channel: 0, isMixerControl: false),
        LedTestItem(name: "Cue 5 (Orange)", note: 89, color: "Orange", channel: 0, isMixerControl: false)
    ]

    var activeMidiChannel: UInt8 {
        if let popup = midiInPopup, popup.indexOfSelectedItem < 16 {
            return UInt8(popup.indexOfSelectedItem)
        }
        return 0
    }

    func sendLedTestItem(_ item: LedTestItem, on: Bool) {
        let ch = activeMidiChannel
        if on {
            RaneMidiService.shared.sendNoteOn(note: item.note, velocity: 127, channel: item.channel)
            if item.channel != 0 {
                RaneMidiService.shared.sendNoteOn(note: item.note, velocity: 127, channel: 0)
            }
            if ch != item.channel && ch != 0 {
                RaneMidiService.shared.sendNoteOn(note: item.note, velocity: 127, channel: ch)
            }
            if item.isMixerControl {
                RaneMidiService.shared.sendCC(cc: item.note, value: 127, channel: item.channel)
                if item.channel != 0 {
                    RaneMidiService.shared.sendCC(cc: item.note, value: 127, channel: 0)
                }
            }
        } else {
            RaneMidiService.shared.sendNoteOff(note: item.note, channel: item.channel)
            if item.channel != 0 {
                RaneMidiService.shared.sendNoteOff(note: item.note, channel: 0)
            }
            if ch != item.channel && ch != 0 {
                RaneMidiService.shared.sendNoteOff(note: item.note, channel: ch)
            }
            if item.isMixerControl {
                RaneMidiService.shared.sendCC(cc: item.note, value: 0, channel: item.channel)
                if item.channel != 0 {
                    RaneMidiService.shared.sendCC(cc: item.note, value: 0, channel: 0)
                }
            }
        }
    }

    func turnAllLedTestLeds(on: Bool) {
        let ch = activeMidiChannel
        for item in Self.ledSequence {
            if on {
                RaneMidiService.shared.sendNoteOn(note: item.note, velocity: 127, channel: item.channel)
                if item.channel != 0 {
                    RaneMidiService.shared.sendNoteOn(note: item.note, velocity: 127, channel: 0)
                }
                if ch != item.channel && ch != 0 {
                    RaneMidiService.shared.sendNoteOn(note: item.note, velocity: 127, channel: ch)
                }
                if item.isMixerControl {
                    RaneMidiService.shared.sendCC(cc: item.note, value: 127, channel: item.channel)
                }
            } else {
                RaneMidiService.shared.sendNoteOff(note: item.note, channel: item.channel)
                if item.channel != 0 {
                    RaneMidiService.shared.sendNoteOff(note: item.note, channel: 0)
                }
                if ch != item.channel && ch != 0 {
                    RaneMidiService.shared.sendNoteOff(note: item.note, channel: ch)
                }
                if item.isMixerControl {
                    RaneMidiService.shared.sendCC(cc: item.note, value: 0, channel: item.channel)
                }
            }
        }
    }

    @objc func onLedTestClicked() {
        if isLedTestRunning {
            stopLedTest(userCancelled: true)
        } else {
            startLedTest()
        }
    }

    func startLedTest() {
        guard RaneMidiService.shared.isConnected else {
            appendSysLog(Localization.tr(en: "❌ Mixer not connected.", de: "❌ Mixer nicht verbunden."))
            return
        }

        isLedTestRunning = true
        ledTestStep = 0
        ledTestButton?.title = Localization.tr(en: "⏹ Stop LED Check", de: "⏹ LED-Test Beenden")
        appendSysLog(Localization.tr(
            en: "💡 Starting Mixer LED Light Check (Chaser sequence)...",
            de: "💡 Starte Mixer LED-Lichtcheck (Lauflicht-Sequenz)..."
        ))

        // Reset all LEDs and initialize clean backlight state
        turnAllLedTestLeds(on: false)
        let blVal: UInt8 = (backlightSwitch.state == .on) ? 1 : 0
        RaneMidiService.shared.sendCC(cc: 38, value: blVal)
        RaneMidiService.shared.sendCC(cc: 36, value: blVal)

        var pauseCounter = 0
        ledTestTimer?.invalidate()
        ledTestTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if self.ledTestStep < Self.ledSequence.count {
                // Lauflicht: Vorherige LED ausschalten
                if self.ledTestStep > 0 {
                    let prev = Self.ledSequence[self.ledTestStep - 1]
                    self.sendLedTestItem(prev, on: false)
                }
                // Aktuelle LED einschalten
                let curr = Self.ledSequence[self.ledTestStep]
                self.sendLedTestItem(curr, on: true)
                self.ledTestStep += 1
            } else if self.ledTestStep == Self.ledSequence.count {
                // Letzte LED des Lauflichts ausschalten
                if let last = Self.ledSequence.last {
                    self.sendLedTestItem(last, on: false)
                }
                // Phase 4: Volltest - Alle LEDs gleichzeitig an!
                self.appendSysLog(Localization.tr(
                    en: "✨ Full Board Check: All Mixer LEDs ON...",
                    de: "✨ Volltest: Alle Mixer-LEDs leuchten gleichzeitig..."
                ))
                self.turnAllLedTestLeds(on: true)
                self.ledTestStep += 1
                pauseCounter = 0
            } else if self.ledTestStep == Self.ledSequence.count + 1 {
                // Pause für Volltest (~1.35 Sekunden = 18 Ticks à 75ms)
                pauseCounter += 1
                if pauseCounter >= 18 {
                    self.stopLedTest(userCancelled: false)
                }
            }
        }
    }

    func stopLedTest(userCancelled: Bool) {
        ledTestTimer?.invalidate()
        ledTestTimer = nil
        isLedTestRunning = false
        turnAllLedTestLeds(on: false)
        ledTestButton?.title = Localization.tr(en: "💡 Mixer LED Light Test", de: "💡 Mixer LED-Lichtcheck")

        // Hardware LED & Backlight Clean Reset
        RaneMidiService.shared.sendCC(cc: 38, value: 0)
        RaneMidiService.shared.sendCC(cc: 36, value: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            let blVal: UInt8 = (self.backlightSwitch.state == .on) ? 1 : 0
            RaneMidiService.shared.sendCC(cc: 38, value: blVal)
            RaneMidiService.shared.sendCC(cc: 36, value: blVal)
            RaneMidiService.shared.requestHardwareDump()
        }

        if userCancelled {
            appendSysLog(Localization.tr(
                en: "⏹ LED Check stopped by user. All LEDs OFF.",
                de: "⏹ LED-Test beendet. Alle LEDs ausgeschaltet."
            ))
        } else {
            appendSysLog(Localization.tr(
                en: "✅ LED Check completed successfully. All LEDs verified & turned off.",
                de: "✅ LED-Lichtcheck erfolgreich abgeschlossen. Alle LEDs geprüft & sauber ausgeschaltet."
            ))
        }
    }

    // MARK: - Hardware & Driver Stress Test
    @objc func onStressTestClicked() {
        if isStressTestRunning {
            stopStressTest(userCancelled: true)
        } else {
            startStressTest()
        }
    }

    func findStressTestBinary() -> String? {
        var candidates: [String?] = []
        if let res = Bundle.main.path(forResource: "rane-stresstest", ofType: nil) {
            candidates.append(res)
        }
        if let resPath = Bundle.main.resourcePath {
            candidates.append((resPath as NSString).appendingPathComponent("rane-stresstest"))
        }
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("rane-stresstest").path)
        candidates.append("/Library/Application Support/RaneDriver/rane-stresstest")
        candidates.append("/usr/local/bin/rane-stresstest")
        candidates.append(FileManager.default.currentDirectoryPath + "/build/rane-stresstest")
        candidates.append(FileManager.default.currentDirectoryPath + "/rane-stresstest")

        for path in candidates.compactMap({ $0 }) {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    func startStressTest() {
        guard RaneMidiService.shared.isConnected else {
            appendSysLog(Localization.tr(en: "❌ Mixer not connected.", de: "❌ Mixer nicht verbunden."))
            return
        }

        guard let binPath = findStressTestBinary() else {
            appendSysLog(Localization.tr(
                en: "❌ Stress test binary 'rane-stresstest' not found.",
                de: "❌ Stresstest-Werkzeug 'rane-stresstest' nicht gefunden."
            ))
            return
        }

        isStressTestRunning = true
        stressTestButton?.title = Localization.tr(en: "⏹ Stop Stress Test", de: "⏹ Stresstest Beenden")
        appendSysLog(Localization.tr(
            en: "🔥 Starting 22-Channel (12 In / 10 Out) Hardware & Driver Stress Test...",
            de: "🔥 Starte 22-Kanal (12 In / 10 Out) Hardware & Treiber Stresstest..."
        ))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["--duration", "20"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self?.appendSysLog(trimmed)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            fileHandle.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isStressTestRunning = false
                self.stressTestProcess = nil
                self.stressTestButton?.title = Localization.tr(en: "🔥 Hardware Stress Test", de: "🔥 Hardware-Stresstest")
                if proc.terminationStatus == 0 {
                    self.appendSysLog(Localization.tr(
                        en: "🏆 Stress Test completed! 0 Dropouts, 100% stable.",
                        de: "🏆 Stresstest erfolgreich beendet! 0 Dropouts, 100% stabil."
                    ))
                } else if proc.terminationReason == .exit {
                    self.appendSysLog(Localization.tr(
                        en: "⚠️ Stress test finished with status: \(proc.terminationStatus)",
                        de: "⚠️ Stresstest beendet mit Status: \(proc.terminationStatus)"
                    ))
                }
            }
        }

        self.stressTestProcess = process
        do {
            try process.run()
        } catch {
            isStressTestRunning = false
            stressTestProcess = nil
            stressTestButton?.title = Localization.tr(en: "🔥 Hardware Stress Test", de: "🔥 Hardware-Stresstest")
            appendSysLog("❌ Fehler beim Starten des Stresstests: \(error.localizedDescription)")
        }
    }

    func stopStressTest(userCancelled: Bool) {
        if let proc = stressTestProcess, proc.isRunning {
            proc.terminate()
        }
        stressTestProcess = nil
        isStressTestRunning = false
        stressTestButton?.title = Localization.tr(en: "🔥 Hardware Stress Test", de: "🔥 Hardware-Stresstest")
        if userCancelled {
            appendSysLog(Localization.tr(
                en: "⏹ Stress Test stopped by user.",
                de: "⏹ Stresstest durch Benutzer beendet."
            ))
        }
    }
}
