/* SPDX-License-Identifier: MIT */
/* AppDelegate.swift - Application lifecycle, menu bar & global dialogs */

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let iconImg = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = iconImg
        }
        setupMainMenu()
        windowController = MainWindowController()
        windowController?.window?.makeKeyAndOrderFront(nil)
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appName = "Rane Sixty-Eight Control Panel"

        // 1. App-Menü (Rane Sixty-Eight Control Panel)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let aboutItem = NSMenuItem(title: Localization.tr(en: "About \(appName)...", de: "Über \(appName)..."), action: #selector(showAboutDialog), keyEquivalent: "")
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
        let helpAbout = NSMenuItem(title: Localization.tr(en: "About Rane Sixty-Eight...", de: "Info zu Rane Sixty-Eight..."), action: #selector(showAboutDialog), keyEquivalent: "")
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
