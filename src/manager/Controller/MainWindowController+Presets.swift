/* SPDX-License-Identifier: MIT */
/* MainWindowController+Presets.swift - Preset management, serialization and UI dialogs */

import Cocoa

extension MainWindowController {

    // MARK: - Snapshot & Apply
    public func currentPreset(named name: String = "Custom") -> RaneMixerPreset {
        let lowVal = lowToneSlider?.integerValue ?? 64
        let highVal = highToneSlider?.integerValue ?? 64
        let lcdVal = lcdContrastSlider?.integerValue ?? 64
        let backlightState = (backlightSwitch?.state == .on)
        let controlPointIdx = controlPointSegment?.selectedSegment ?? 0
        let usb6Seg = usb6RecordSegment?.selectedSegment ?? 0
        let bufSizeIdx = bufferSizePopup?.indexOfSelectedItem ?? 2

        let pgmSens = channels.map { $0.phonoPopup.indexOfSelectedItem }
        let pgmRes = channels.map { $0.resonanceSegment.selectedSegment }
        let pgmRec = channels.map { $0.recordSegment.selectedSegment }

        let outCh = (midiOutPopup?.indexOfSelectedItem ?? 0) + 1
        let inCh = (midiInPopup?.indexOfSelectedItem ?? 16) + 1

        return RaneMixerPreset(
            name: name,
            buttonBacklight: backlightState,
            lcdContrast: lcdVal,
            lowToneVal: lowVal,
            highToneVal: highVal,
            usb6RecordSource: usb6Seg,
            bufferSizeIndex: bufSizeIdx,
            midiControlPoint: controlPointIdx,
            phonoSensitivities: pgmSens.count == 4 ? pgmSens : [5, 5, 5, 5],
            filterResonances: pgmRes.count == 4 ? pgmRes : [0, 0, 0, 0],
            recordSources: pgmRec.count == 4 ? pgmRec : [1, 1, 1, 1],
            midiOutChannel: outCh,
            midiInChannel: inCh
        )
    }

    public func applyPreset(_ preset: RaneMixerPreset) {
        // 1. Tab 1 - Hardware Controls & Latency
        backlightSwitch?.state = preset.buttonBacklight ? .on : .off
        onBacklightSwitchChanged()

        lcdContrastSlider?.integerValue = preset.lcdContrast
        onLcdContrastChanged()

        lowToneSlider?.integerValue = preset.lowToneVal
        onLowToneChanged()

        highToneSlider?.integerValue = preset.highToneVal
        onHighToneChanged()

        usb6RecordSegment?.selectedSegment = preset.usb6RecordSource
        onUsb6RecordSegmentChanged()

        if let bufPopup = bufferSizePopup, bufPopup.numberOfItems > 0 {
            bufPopup.selectItem(at: min(preset.bufferSizeIndex, bufPopup.numberOfItems - 1))
            onBufferSizePopupChanged()
        }

        controlPointSegment?.selectedSegment = preset.midiControlPoint
        onControlPointChanged()

        // 2. Tab 2 - PGM Channels 1–4
        for i in 0..<min(channels.count, preset.phonoSensitivities.count) {
            channels[i].phonoPopup.selectItem(at: preset.phonoSensitivities[i])
            onPhonoSensPopupChanged(channels[i].phonoPopup)

            channels[i].resonanceSegment.selectedSegment = preset.filterResonances[i]
            onFilterResChanged(channels[i].resonanceSegment)

            channels[i].recordSegment.selectedSegment = preset.recordSources[i]
            onRecordSourceChanged(channels[i].recordSegment)
        }

        // 3. Tab 3 - MIDI Configuration
        if let outPopup = midiOutPopup, outPopup.numberOfItems > 0 {
            let outIdx = min(max(0, preset.midiOutChannel - 1), outPopup.numberOfItems - 1)
            outPopup.selectItem(at: outIdx)
        }
        if let inPopup = midiInPopup, inPopup.numberOfItems > 0 {
            let inIdx = min(max(0, preset.midiInChannel - 1), inPopup.numberOfItems - 1)
            inPopup.selectItem(at: inIdx)
        }
        onMidiChannelChanged()

        appendSysLog("Mixer-Preset aktiviert: \"\(preset.name)\"")

        // Notification alert banner
        showPresetAppliedBanner(name: preset.name)
    }

    private func showPresetAppliedBanner(name: String) {
        guard let window = self.window, let contentView = window.contentView else { return }

        let banner = NSView()
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor(red: 0.12, green: 0.55, blue: 0.35, alpha: 0.95).cgColor
        banner.layer?.cornerRadius = 8
        banner.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: "✓ Preset aktiv: \(name)")
        lbl.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        lbl.textColor = NSColor.white
        lbl.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(lbl)

        contentView.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            banner.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            banner.heightAnchor.constraint(equalToConstant: 28),
            lbl.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            lbl.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            lbl.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])

        banner.alphaValue = 0.0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            banner.animator().alphaValue = 1.0
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    banner.animator().alphaValue = 0.0
                }, completionHandler: {
                    banner.removeFromSuperview()
                })
            }
        })
    }

    // MARK: - Presets Menu Construction
    public func buildPresetsMenu() -> NSMenu {
        let menu = NSMenu(title: Localization.tr(en: "Presets", de: "Presets"))

        // 1. Factory Presets
        let factoryTitle = NSMenuItem(title: Localization.tr(en: "FACTORY PRESETS", de: "WERKSEINSTELLUNGEN"), action: nil, keyEquivalent: "")
        factoryTitle.isEnabled = false
        factoryTitle.attributedTitle = NSAttributedString(
            string: factoryTitle.title,
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .heavy), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(factoryTitle)

        for p in RanePresetService.shared.factoryPresets {
            let item = NSMenuItem(title: p.name, action: #selector(onApplyPresetMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p
            if let desc = p.description {
                item.toolTip = desc
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. User Presets
        let userPresets = RanePresetService.shared.loadUserPresets()
        let userTitle = NSMenuItem(title: Localization.tr(en: "USER PRESETS", de: "BENUTZER-PRESETS"), action: nil, keyEquivalent: "")
        userTitle.isEnabled = false
        userTitle.attributedTitle = NSAttributedString(
            string: userTitle.title,
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .heavy), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(userTitle)

        if userPresets.isEmpty {
            let emptyItem = NSMenuItem(title: Localization.tr(en: "  (No user presets saved)", de: "  (Keine eigenen Presets vorhanden)"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for p in userPresets {
                let item = NSMenuItem(title: p.name, action: #selector(onApplyPresetMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // 3. File Operations
        let saveItem = NSMenuItem(title: Localization.tr(en: "Save Current as Preset...", de: "Aktuelles Preset speichern..."), action: #selector(promptSavePreset), keyEquivalent: "s")
        saveItem.target = self
        menu.addItem(saveItem)

        let openItem = NSMenuItem(title: Localization.tr(en: "Load Preset File...", de: "Preset aus Datei laden..."), action: #selector(openPresetFileDialog), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let exportItem = NSMenuItem(title: Localization.tr(en: "Export Preset File...", de: "Preset als Datei exportieren..."), action: #selector(exportPresetFileDialog), keyEquivalent: "S")
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Reset
        let resetItem = NSMenuItem(title: Localization.tr(en: "Reset to Factory Default", de: "Werkseinstellungen wiederherstellen"), action: #selector(resetToFactoryDefaults), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        return menu
    }

    // MARK: - Actions
    @objc func onApplyPresetMenuItem(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? RaneMixerPreset {
            applyPreset(preset)
        }
    }

    @objc func resetToFactoryDefaults() {
        applyPreset(RanePresetService.factoryClubDefault)
    }

    @objc func promptSavePreset() {
        let alert = NSAlert()
        alert.messageText = Localization.tr(en: "Save Mixer Preset", de: "Mixer-Preset speichern")
        alert.informativeText = Localization.tr(
            en: "Enter a name for the preset. It will be stored in your presets library.",
            de: "Geben Sie einen Namen für das Preset ein. Es wird in Ihrer Presets-Bibliothek gespeichert."
        )
        alert.addButton(withTitle: Localization.tr(en: "Save", de: "Speichern"))
        alert.addButton(withTitle: Localization.tr(en: "Cancel", de: "Abbrechen"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = "Mein Setup"
        alert.accessoryView = input

        if let window = self.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self = self, response == .alertFirstButtonReturn else { return }
                let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }

                let preset = self.currentPreset(named: name)
                do {
                    _ = try RanePresetService.shared.saveUserPreset(preset)
                    self.showPresetAppliedBanner(name: "\(name) (Gespeichert)")
                } catch {
                    let errAlert = NSAlert(error: error)
                    errAlert.runModal()
                }
            }
        }
    }

    @objc func openPresetFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["ranepreset", "json"]
        panel.title = Localization.tr(en: "Load Rane Preset", de: "Rane Preset laden")

        if let window = self.window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self = self, response == .OK, let url = panel.url else { return }
                do {
                    let preset = try RanePresetService.shared.loadPreset(from: url)
                    self.applyPreset(preset)
                } catch {
                    let errAlert = NSAlert(error: error)
                    errAlert.runModal()
                }
            }
        }
    }

    @objc func exportPresetFileDialog() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedFileTypes = ["ranepreset"]
        panel.nameFieldStringValue = "Rane68_Preset.ranepreset"
        panel.title = Localization.tr(en: "Export Rane Preset", de: "Rane Preset exportieren")

        if let window = self.window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self = self, response == .OK, let url = panel.url else { return }
                let preset = self.currentPreset(named: url.deletingPathExtension().lastPathComponent)
                do {
                    try RanePresetService.shared.savePreset(preset, to: url)
                    self.showPresetAppliedBanner(name: "Exportiert")
                } catch {
                    let errAlert = NSAlert(error: error)
                    errAlert.runModal()
                }
            }
        }
    }
}
