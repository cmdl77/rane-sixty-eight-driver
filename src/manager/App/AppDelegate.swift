/* SPDX-License-Identifier: MIT */
/* AppDelegate.swift - Application lifecycle, menu bar, status item widget & global dialogs */

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var windowController: MainWindowController?
    var statusItem: NSStatusItem?
    var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let iconImg = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = iconImg
        }
        setupMainMenu()
        setupStatusItem()

        windowController = MainWindowController()
        windowController?.window?.makeKeyAndOrderFront(nil)
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in macOS menu bar status widget
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openControlPanelWindow()
        }
        return true
    }

    // MARK: - Menu Bar Status Item (Paket 3)
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        if let img = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Rane Sixty-Eight") {
            img.isTemplate = true
            button.image = img
            button.imagePosition = .imageLeading
        }
        button.title = " 68"
        button.font = NSFont.systemFont(ofSize: 11, weight: .bold)

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        buildStatusMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildStatusMenu(menu)
    }

    private func buildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Title Item
        let titleItem = NSMenuItem(title: "RANE SIXTY-EIGHT", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "RANE SIXTY-EIGHT",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .heavy)]
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        // 2. Hardware Connection Status
        let isConnected = RaneMidiService.shared.isConnected
        let statText = isConnected
            ? Localization.tr(en: "● Connected (USB Port A, 48 kHz)", de: "● Verbunden (USB Port A, 48 kHz)")
            : Localization.tr(en: "● Disconnected (Offline)", de: "● Getrennt (Offline)")
        let statItem = NSMenuItem(title: statText, action: nil, keyEquivalent: "")
        statItem.attributedTitle = NSAttributedString(
            string: statText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: isConnected ? NSColor.systemGreen : NSColor.systemRed
            ]
        )
        statItem.isEnabled = false
        menu.addItem(statItem)

        // 2b. System CPU Load
        let cpuUsage = RaneCpuService.shared.systemCpuUsage
        let cpuText = Localization.tr(
            en: "⚡ System CPU: \(String(format: "%.1f%%", cpuUsage))",
            de: "⚡ System CPU: \(String(format: "%.1f%%", cpuUsage))"
        )
        let cpuItem = NSMenuItem(title: cpuText, action: nil, keyEquivalent: "")
        cpuItem.attributedTitle = NSAttributedString(
            string: cpuText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: cpuUsage > 80.0 ? NSColor.systemRed : (cpuUsage > 50.0 ? NSColor.systemOrange : NSColor.systemGreen)
            ]
        )
        cpuItem.isEnabled = false
        menu.addItem(cpuItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Current Latency / Buffer Submenu
        let currentFrames = readCurrentBufferFrames()
        let latSubmenu = NSMenu(title: Localization.tr(en: "Buffer Latency", de: "Puffergröße / Latenz"))
        let bufferOptions: [(Int, String, String)] = [
            (128,  "1 ms (128 Frames)",  "1 ms (128 Frames - Ultra Low)"),
            (256,  "2 ms (256 Frames)",  "2 ms (256 Frames - Pro DJ)"),
            (512,  "5 ms (512 Frames)",  "5 ms (512 Frames - Standard)"),
            (768,  "8 ms (768 Frames)",  "8 ms (768 Frames - Safe)"),
            (1024, "10 ms (1024 Frames)", "10 ms (1024 Frames)"),
            (1536, "15 ms (1536 Frames)", "15 ms (1536 Frames)"),
            (2048, "20 ms (2048 Frames)", "20 ms (2048 Frames - High Stability)")
        ]

        for (frames, _, longName) in bufferOptions {
            let item = NSMenuItem(
                title: Localization.tr(en: longName, de: longName),
                action: #selector(onStatusBufferSelected(_:)),
                keyEquivalent: ""
            )
            item.tag = frames
            item.target = self
            item.state = (frames == currentFrames) ? .on : .off
            latSubmenu.addItem(item)
        }

        let latTitle = Localization.tr(en: "USB Audio Latency (\(currentFrames)f)", de: "USB Audio Latenz (\(currentFrames)f)")
        let latItem = NSMenuItem(title: latTitle, action: nil, keyEquivalent: "")
        latItem.submenu = latSubmenu
        menu.addItem(latItem)

        // 4. Audio Streams Info
        let ioInfo = NSMenuItem(
            title: Localization.tr(en: "Audio: 22 Channels (12 In / 10 Out)", de: "Audio: 22 Kanäle (12 In / 10 Out)"),
            action: nil,
            keyEquivalent: ""
        )
        ioInfo.isEnabled = false
        menu.addItem(ioInfo)

        menu.addItem(NSMenuItem.separator())

        // 5. Open Control Panel
        let openItem = NSMenuItem(
            title: Localization.tr(en: "Open Control Panel...", de: "Control Panel öffnen..."),
            action: #selector(openControlPanelWindow),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        // 6. Open Audio MIDI Setup
        let amsItem = NSMenuItem(
            title: Localization.tr(en: "Audio MIDI Setup...", de: "Audio-MIDI-Konfiguration..."),
            action: #selector(openAudioMidiSetup),
            keyEquivalent: ""
        )
        amsItem.target = self
        menu.addItem(amsItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Quit
        let quitItem = NSMenuItem(
            title: Localization.tr(en: "Quit", de: "Beenden"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    private func readCurrentBufferFrames() -> Int {
        if let s = try? String(contentsOfFile: "/var/tmp/rane_sixty_eight_buffer_size.txt", encoding: .utf8),
           let val = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)), val >= 64 && val <= 4096 {
            return val
        }
        if let s = try? String(contentsOfFile: "/tmp/rane_sixty_eight_buffer_size.txt", encoding: .utf8),
           let val = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)), val >= 64 && val <= 4096 {
            return val
        }
        return 512
    }

    @objc private func onStatusBufferSelected(_ sender: NSMenuItem) {
        let frames = sender.tag
        let file = "/var/tmp/rane_sixty_eight_buffer_size.txt"
        try? "\(frames)\n".write(toFile: file, atomically: true, encoding: .utf8)
        let alt = "/tmp/rane_sixty_eight_buffer_size.txt"
        try? "\(frames)\n".write(toFile: alt, atomically: true, encoding: .utf8)

        if let mc = windowController ?? MainWindowController.shared {
            let index: Int
            switch frames {
            case 128: index = 0
            case 256: index = 1
            case 512: index = 2
            case 768: index = 3
            case 1024: index = 4
            case 1536: index = 5
            case 2048: index = 6
            default: index = 2
            }
            if index < mc.bufferSizePopup.numberOfItems {
                mc.bufferSizePopup.selectItem(at: index)
            }
            mc.appendSysLog("Latenz im Menüleisten-Widget gewählt: \(sender.title)")
        }

        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let isConnected = RaneMidiService.shared.isConnected
        if isConnected {
            button.title = " 68"
            button.contentTintColor = nil
        } else {
            button.title = " 68"
            button.contentTintColor = NSColor.secondaryLabelColor
        }
    }

    @objc func openControlPanelWindow() {
        if windowController == nil {
            windowController = MainWindowController()
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openAudioMidiSetup() {
        let ws = NSWorkspace.shared
        if let url = ws.urlForApplication(withBundleIdentifier: "com.apple.audio.AudioMIDISetup") {
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            ws.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
        }
    }

    // MARK: - Main Menu
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appName = "Rane Sixty-Eight Control Panel"

        // 1. App-Menü (Rane Sixty-Eight Control Panel)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let versionStr = "v2.0.0"
        let aboutItem = NSMenuItem(title: Localization.tr(en: "About \(appName) (\(versionStr))...", de: "Über \(appName) (\(versionStr))..."), action: #selector(showAboutDialog), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: Localization.tr(en: "Settings...", de: "Einstellungen..."), action: #selector(openSettingsDialog), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: Localization.tr(en: "Services", de: "Dienste"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: Localization.tr(en: "Hide \(appName)", de: "\(appName) ausblenden"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: Localization.tr(en: "Hide Others", de: "Andere ausblenden"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: Localization.tr(en: "Show All", de: "Alle einblenden"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: Localization.tr(en: "Quit \(appName)", de: "\(appName) beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Settings Menu in Menu Bar
        let settingsTopItem = NSMenuItem()
        let settingsTopMenu = NSMenu(title: Localization.tr(en: "Settings", de: "Einstellungen"))

        let langMenuItem = NSMenuItem(title: Localization.tr(en: "Language", de: "Sprache"), action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu(title: Localization.tr(en: "Language", de: "Sprache"))

        let enItem = NSMenuItem(title: "English (Default)", action: #selector(setEnglishLanguage), keyEquivalent: "")
        enItem.target = self
        enItem.state = (Localization.current == .en) ? .on : .off
        langSubmenu.addItem(enItem)

        let deItem = NSMenuItem(title: "Deutsch", action: #selector(setGermanLanguage), keyEquivalent: "")
        deItem.target = self
        deItem.state = (Localization.current == .de) ? .on : .off
        langSubmenu.addItem(deItem)

        langMenuItem.submenu = langSubmenu
        settingsTopMenu.addItem(langMenuItem)
        settingsTopItem.submenu = settingsTopMenu
        mainMenu.addItem(settingsTopItem)

        // 3. Edit / Bearbeiten
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: Localization.tr(en: "Edit", de: "Bearbeiten"))
        editMenu.addItem(withTitle: Localization.tr(en: "Copy", de: "Kopieren"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: Localization.tr(en: "Select All", de: "Alles auswählen"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. Window / Fenster
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: Localization.tr(en: "Window", de: "Fenster"))
        let miniItem = NSMenuItem(title: Localization.tr(en: "Minimize", de: "Im Dock ablegen"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        let zoomItem = NSMenuItem(title: Localization.tr(en: "Zoom", de: "Zoomen"), action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        let closeItem = NSMenuItem(title: Localization.tr(en: "Close", de: "Schließen"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(miniItem)
        windowMenu.addItem(zoomItem)
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 5. Help / Hilfe
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: Localization.tr(en: "Help", de: "Hilfe"))
        let helpAbout = NSMenuItem(title: Localization.tr(en: "About Rane Sixty-Eight (v2.0.0)...", de: "Info zu Rane Sixty-Eight (v2.0.0)..."), action: #selector(showAboutDialog), keyEquivalent: "")
        helpAbout.target = self
        helpMenu.addItem(helpAbout)
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func setEnglishLanguage() {
        Localization.current = .en
        MainWindowController.shared?.rebuildUI()
        setupMainMenu()
    }

    @objc private func setGermanLanguage() {
        Localization.current = .de
        MainWindowController.shared?.rebuildUI()
        setupMainMenu()
    }

    @objc private func openSettingsDialog() {
        let alert = NSAlert()
        alert.messageText = Localization.tr(en: "Language Settings", de: "Spracheinstellungen")
        alert.informativeText = Localization.tr(
            en: "Select interface language for the Control Panel:\n\nCurrent: \(Localization.current == .en ? "English" : "Deutsch")",
            de: "Wählen Sie die Benutzeroberflächen-Sprache für das Control Panel:\n\nAktuell: \(Localization.current == .en ? "English" : "Deutsch")"
        )
        alert.addButton(withTitle: "English")
        alert.addButton(withTitle: "Deutsch")
        alert.addButton(withTitle: Localization.tr(en: "Cancel", de: "Abbrechen"))
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            setEnglishLanguage()
        } else if res == .alertSecondButtonReturn {
            setGermanLanguage()
        }
    }

    @objc private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "Rane Sixty-Eight Control Panel"
        alert.informativeText = Localization.tr(
            en: """
            Version 2.0.0 (macOS Sequoia / Sonoma Edition)
            CoreAudio HAL Driver & CoreMIDI LaunchAgent Subsystem

            Author: Open Source Community (MIT License)
            Custom 64-Bit User-Space Driver & Control Panel for the Rane Sixty-Eight DJ Mixer on Apple Silicon & Intel Macs.
            """,
            de: """
            Version 2.0.0 (macOS Sequoia / Sonoma Edition)
            CoreAudio HAL Driver & CoreMIDI LaunchAgent Subsystem

            Entwickelt von: Open Source Community (MIT-Lizenz)
            Maßgeschneiderter 64-Bit User-Space Treiber & Steuerzentrale für den Rane Sixty-Eight DJ Mixer auf Apple Silicon & Intel Macs.
            """
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let icon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) {
            alert.icon = icon
        }
        alert.runModal()
    }
}
