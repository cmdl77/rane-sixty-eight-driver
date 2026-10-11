/* SPDX-License-Identifier: MIT */
/* MainWindowController+MIDI.swift - CoreMIDI listener, throttling & dispatching */

import Cocoa

extension MainWindowController {
    // MARK: - MIDI Handling & Callbacks
    func setupMidiListener() {
        RaneMidiService.shared.onConnectionStateChanged = { [weak self] connected in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setControlsEnabled(connected)
                if connected {
                    self.appendMidiLog(Localization.tr(en: "● CoreMIDI & USB connection active. Sixty-Eight is ready.", de: "● CoreMIDI & USB-Verbindung aktiv. Sixty-Eight ist betriebsbereit."))
                    self.refreshStatus()
                    RaneMidiService.shared.requestHardwareDump()
                } else {
                    self.appendMidiLog(Localization.tr(en: "● Mixer disconnected or switched off.", de: "● Mixer getrennt oder ausgeschaltet."))
                    self.refreshStatus()
                }
            }
        }

        RaneMidiService.shared.onMidiReceived = { [weak self] status, d1, d2 in
            self?.handleMidiEvent(status: status, d1: d1, d2: d2)
        }
    }

    func setControlsEnabled(_ enabled: Bool) {
        // Tab 1: Mixer Audio Controls
        backlightSwitch?.isEnabled = enabled
        lcdContrastSlider?.isEnabled = enabled
        lowToneSlider?.isEnabled = enabled
        highToneSlider?.isEnabled = enabled
        usb6RecordSegment?.isEnabled = enabled
        controlPointSegment?.isEnabled = enabled
        bufferSizePopup?.isEnabled = enabled

        // Tab 2: PGM Channels 1–4 Controls
        for ch in channels {
            ch.phonoPopup.isEnabled = enabled
            ch.resonanceSegment.isEnabled = enabled
            ch.recordSegment.isEnabled = enabled
        }

        // Tab 3: Live MIDI Controls
        midiOutPopup?.isEnabled = enabled
        midiInPopup?.isEnabled = enabled

        // Tab 4: System LED Test & Stress Test
        ledTestButton?.isEnabled = enabled
        if !enabled && isLedTestRunning {
            stopLedTest(userCancelled: true)
        }
        stressTestButton?.isEnabled = enabled
        if !enabled && isStressTestRunning {
            stopStressTest(userCancelled: true)
        }

        // Visual Dimming for Settings Pages
        contentContainer?.alphaValue = enabled ? 1.0 : 0.42

        // Header Status Badge
        if enabled {
            headerStatusBadge?.stringValue = Localization.tr(en: "  ● Connected  ", de: "  ● Verbunden  ")
            headerStatusBadge?.textColor = NSColor.systemGreen
            headerStatusBadge?.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor

            usbStatusBadge?.stringValue = Localization.tr(en: "  ● Port A Active (48 kHz Float)  ", de: "  ● Port A Aktiv (48 kHz Float)  ")
            usbStatusBadge?.textColor = NSColor.systemGreen
            usbStatusBadge?.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor

            // Default USB-6 Record to Main Mix (CC 33 = 1 and CC 35 = 1)
            sendUserCC(cc: 33, value: 1)
            sendUserCC(cc: 35, value: 1)
        } else {
            headerStatusBadge?.stringValue = Localization.tr(en: "  ● Disconnected  ", de: "  ● Getrennt  ")
            headerStatusBadge?.textColor = NSColor.systemRed
            headerStatusBadge?.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor

            usbStatusBadge?.stringValue = Localization.tr(en: "  ● Offline  ", de: "  ● Offline  ")
            usbStatusBadge?.textColor = NSColor.systemRed
            usbStatusBadge?.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        }
    }

    func handleMidiEvent(status: UInt8, d1: UInt8, d2: UInt8) {
        let hex = String(format: "%02X %02X %02X", status, d1, d2)
        let type = (status & 0xF0)

        var desc = ""
        if type == 0xB0 { // Control Change
            pendingChangesLock.lock()
            if let pending = pendingChanges[d1] {
                let elapsed = Date().timeIntervalSince1970 - pending.timestamp
                if elapsed < 1.2 {
                    let isSlider = (d1 == 37 || d1 == 34 || d1 == 35)
                    let matched = isSlider ? (abs(Int(d2) - Int(pending.targetValue)) <= 1) : (d2 == pending.targetValue)
                    if matched {
                        // Hardware hat den Wert erfolgreich quittiert!
                        pendingChanges.removeValue(forKey: d1)
                        pendingChangesLock.unlock()
                        appendMidiLog("IN: [\(hex)]  ✓ Quittung Mixer CC #\(d1)=\(d2)")
                        return
                    } else {
                        // Veralteter Mixer-Status vor Ausführung unseres Befehls: verwerfen
                        pendingChangesLock.unlock()
                        appendMidiLog("IN: [\(hex)]  (Veralteter Wert CC #\(d1)=\(d2) vor Quittierung ignoriert)")
                        return
                    }
                } else {
                    pendingChanges.removeValue(forKey: d1)
                }
            }
            pendingChangesLock.unlock()

            desc = "Control Change #\(d1) = \(d2)"
            updateUiFromMidiCC(cc: d1, value: d2)
        } else if type == 0x90 {
            desc = "Note On #\(d1) Velocity=\(d2)"
        } else if type == 0x80 {
            desc = "Note Off #\(d1) Velocity=\(d2)"
        } else {
            desc = "MIDI Event"
        }

        appendMidiLog("IN: [\(hex)]  \(desc)")
    }

    func updateUiFromMidiCC(cc: UInt8, value: UInt8) {
        // DIP-Schalter Eingangswahl (CC 112..115)
        if cc >= 112 && cc <= 115 {
            let chIdx = Int(cc - 112)
            if chIdx < channels.count {
                let text: String
                let color: NSColor
                switch value {
                case 1:
                    text = "  PHONO  "
                    color = NSColor.systemOrange
                case 2:
                    text = "  S/PDIF  "
                    color = NSColor.systemPurple
                default:
                    text = "  LINE (CD)  "
                    color = NSColor.systemBlue
                }
                if channels[chIdx].inputTypeBadge.stringValue != text {
                    channels[chIdx].inputTypeBadge.stringValue = text
                    channels[chIdx].inputTypeBadge.textColor = color
                    channels[chIdx].inputTypeBadge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
                    appendMidiLog("IN: PGM \(chIdx + 1) Input Select -> \(text.trimmingCharacters(in: .whitespaces)) (CC#\(cc)=\(value))")
                }
            }
        } else if cc == 36 {
            // Button Backlight: CC 36 (1 = On, 0 = Off)
            let desired: NSControl.StateValue = (value != 0) ? .on : .off
            if backlightSwitch.state != desired {
                backlightSwitch.state = desired
            }
        } else if cc == 37 {
            // LCD Contrast: CC 37 (0..127)
            if lcdContrastSlider.integerValue != Int(value) {
                lcdContrastSlider.integerValue = Int(value)
                let pct = Int(round(Double(value) / 127.0 * 100.0))
                lcdContrastBadge.stringValue = "\(pct)%"
            }
        } else if cc == 34 {
            // Phones Tone High: CC 34
            if highToneSlider.integerValue != Int(value) {
                highToneSlider.integerValue = Int(value)
                let highDb = (Double(value) - 64.0) / 64.0 * 6.0
                highToneBadge.stringValue = String(format: "%+.1f dB", highDb)
            }
        } else if cc == 35 {
            // Phones Tone Low: CC 35
            if lowToneSlider.integerValue != Int(value) {
                lowToneSlider.integerValue = Int(value)
                let lowDb = (Double(value) - 64.0) / 64.0 * 6.0
                lowToneBadge.stringValue = String(format: "%+.1f dB", lowDb)
            }
        } else if cc == 33 {
            // USB-6 Record Select: CC 33 (1: Main Mix, 2: Mic 1, 3: Mic 2)
            if value >= 1 && value <= 3 {
                let seg = Int(value - 1)
                if usb6RecordSegment.selectedSegment != seg {
                    usb6RecordSegment.selectedSegment = seg
                }
            }
        } else if cc == 21 || cc == 24 || cc == 27 || cc == 30 {
            // Phono Gain Sensitivity (PGM 1..4)
            let chIdx = (cc == 21 ? 0 : (cc == 24 ? 1 : (cc == 27 ? 2 : 3)))
            let idx = Int(value)
            if chIdx < channels.count && idx < channels[chIdx].phonoPopup.numberOfItems {
                if channels[chIdx].phonoPopup.indexOfSelectedItem != idx {
                    channels[chIdx].phonoPopup.selectItem(at: idx)
                }
            }
        } else if cc == 22 || cc == 25 || cc == 28 || cc == 31 {
            // Filter Resonance (PGM 1..4): 0=Low, 127=High
            let chIdx = (cc == 22 ? 0 : (cc == 25 ? 1 : (cc == 28 ? 2 : 3)))
            if chIdx < channels.count {
                let seg = (value >= 64) ? 1 : 0
                if channels[chIdx].resonanceSegment.selectedSegment != seg {
                    channels[chIdx].resonanceSegment.selectedSegment = seg
                }
            }
        } else if cc == 23 || cc == 26 || cc == 29 || cc == 32 {
            // Record Select (PGM 1..4): 1=PH/CD, 2=Post, 3=AUX
            let chIdx = (cc == 23 ? 0 : (cc == 26 ? 1 : (cc == 29 ? 2 : 3)))
            if chIdx < channels.count && value >= 1 && value <= 3 {
                let seg = Int(value - 1)
                if channels[chIdx].recordSegment.selectedSegment != seg {
                    channels[chIdx].recordSegment.selectedSegment = seg
                }
            }
        } else if cc >= 120 && cc <= 123 {
            // Crossfader Select (PGM 1..4): CC 120..123
            // 1: Crossfader A, 2: Crossfader B, 3: Post-Crossfader
            let chIdx = Int(cc - 120)
            if chIdx < channels.count {
                let text: String
                let color: NSColor
                switch value {
                case 1:
                    text = "  CROSSFADER A  "
                    color = NSColor.systemOrange
                case 2:
                    text = "  CROSSFADER B  "
                    color = NSColor.systemBlue
                default:
                    text = "      POST      "
                    color = NSColor(white: 0.88, alpha: 1.0)
                }
                if channels[chIdx].crossfaderBadge.stringValue != text {
                    channels[chIdx].crossfaderBadge.stringValue = text
                    channels[chIdx].crossfaderBadge.textColor = color
                    channels[chIdx].crossfaderBadge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
                    appendMidiLog("IN: PGM \(chIdx + 1) Crossfader -> [\(text.trimmingCharacters(in: .whitespaces))] (CC#\(cc)=\(value))")
                }
            }
        } else if cc >= 116 && cc <= 119 {
            // Hardware Source Rotary Select (PGM 1..4): CC 116..119
            // 1,2: PH/CD | 3,4: USB | 5,6: AUX
            let chIdx = Int(cc - 116)
            if chIdx < channels.count {
                let text: String
                let color: NSColor
                switch value {
                case 1, 2:
                    text = "  PH / CD  "
                    color = NSColor.systemOrange
                case 3, 4:
                    text = "    USB    "
                    color = NSColor.systemTeal
                case 5, 6:
                    text = "    AUX    "
                    color = NSColor.systemGreen
                default:
                    text = "  PH / CD  "
                    color = NSColor.systemOrange
                }
                if channels[chIdx].sourceBadge.stringValue != text {
                    channels[chIdx].sourceBadge.stringValue = text
                    channels[chIdx].sourceBadge.textColor = color
                    channels[chIdx].sourceBadge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
                    appendMidiLog("IN: PGM \(chIdx + 1) Source Rotary -> \(text.trimmingCharacters(in: .whitespaces)) (CC#\(cc)=\(value))")
                }
            }
        }
    }

    func appendMidiLog(_ text: String) {
        let time = dateFormatter.string(from: Date())
        let line = "[\(time)] \(text)\n"

        midiLogLock.lock()
        midiLogBuffer.append(line)
        let shouldSchedule = !isMidiLogFlushScheduled
        if shouldSchedule {
            isMidiLogFlushScheduled = true
        }
        midiLogLock.unlock()

        if shouldSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.flushMidiLogBuffer()
            }
        }
    }

    func flushMidiLogBuffer() {
        midiLogLock.lock()
        let lines = midiLogBuffer.joined()
        midiLogBuffer.removeAll(keepingCapacity: true)
        isMidiLogFlushScheduled = false
        midiLogLock.unlock()

        guard let tv = midiLogTextView, let storage = tv.textStorage, !lines.isEmpty else { return }

        if storage.length > 35000 {
            storage.deleteCharacters(in: NSRange(location: 0, length: 15000))
        }

        let attrStr = NSAttributedString(string: lines, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(white: 0.90, alpha: 1.0)
        ])
        storage.append(attrStr)

        if let scroll = midiLogScrollView {
            let clip = scroll.contentView
            if let doc = scroll.documentView {
                let maxY = max(0, doc.bounds.height - clip.bounds.height)
                clip.scroll(to: NSPoint(x: 0, y: maxY))
                scroll.reflectScrolledClipView(clip)
            }
        }
    }

    func appendSysLog(_ text: String) {
        guard let tv = sysLogTextView else { return }
        let time = dateFormatter.string(from: Date())
        let line = "[\(time)] \(text)\n"
        DispatchQueue.main.async {
            guard let storage = tv.textStorage else { return }
            if storage.length > 40000 {
                storage.deleteCharacters(in: NSRange(location: 0, length: 20000))
            }
            storage.append(NSAttributedString(string: line, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(white: 0.90, alpha: 1.0)
            ]))
            if tv.window != nil && !(self.systemView?.isHidden ?? true) {
                tv.scrollToEndOfDocument(nil)
            }
        }
    }

    // MARK: - Action Handlers (MIDI CC an Mixer senden mit Quittungs-Tracking)
    func sendUserCC(cc: UInt8, value: UInt8) {
        pendingChangesLock.lock()
        pendingChanges[cc] = PendingControlChange(targetValue: value, timestamp: Date().timeIntervalSince1970)
        pendingChangesLock.unlock()

        RaneMidiService.shared.sendCC(cc: cc, value: value)
    }

    func sendSliderCCThrottled(cc: UInt8, value: UInt8) {
        let now = Date().timeIntervalSince1970
        let last = lastSliderSendTime[cc] ?? 0
        if (now - last) < 0.035 { // max ~28 updates/sec zur Vermeidung von USB-Stau
            pendingSliderValues[cc] = value
            if sliderThrottleTimer == nil {
                sliderThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: false) { [weak self] _ in
                    self?.flushPendingSliders()
                }
            }
            return
        }
        lastSliderSendTime[cc] = now
        sendUserCC(cc: cc, value: value)
    }

    func flushPendingSliders() {
        sliderThrottleTimer = nil
        let pending = pendingSliderValues
        pendingSliderValues.removeAll()
        for (cc, val) in pending {
            lastSliderSendTime[cc] = Date().timeIntervalSince1970
            sendUserCC(cc: cc, value: val)
        }
    }
}
