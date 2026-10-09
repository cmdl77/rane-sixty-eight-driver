/* SPDX-License-Identifier: MIT */
/* MainWindowController+Diagnostics.swift - System status query and driver health monitoring */

import Cocoa

extension MainWindowController {
    func refreshStatus() {
        if isRefreshing { return }
        isRefreshing = true
        let driverPath = self.driverPath

        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.isRefreshing = false }
            guard let self = self else { return }

            let isInstalled = FileManager.default.fileExists(atPath: driverPath)

            // 1. Legacy Kext Check
            let hasKext = FileManager.default.fileExists(atPath: "/Library/Extensions/RaneSixtyEight.kext") ||
                          FileManager.default.fileExists(atPath: "/System/Library/Extensions/RaneSixtyEight.kext")

            // 2. LaunchAgent Check
            var agentPid = ""
            let pgrep = Process()
            pgrep.launchPath = "/usr/bin/pgrep"
            pgrep.arguments = ["-x", "RaneMIDIAgent"]
            let pPipe = Pipe()
            pgrep.standardOutput = pPipe
            try? pgrep.run()
            let pData = pPipe.fileHandleForReading.readDataToEndOfFile()
            pgrep.waitUntilExit()
            agentPid = String(data: pData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // 3. USB Sixty-Eight Verbindung via CoreMIDI
            let hasDevice = RaneMidiService.shared.isConnected

            DispatchQueue.main.async {
                if isInstalled {
                    self.statusLabel?.stringValue = "🟢 Installiert (/Library/Audio/Plug-Ins/HAL/RaneHAL.driver)"
                    self.statusLabel?.textColor = NSColor.systemGreen
                } else {
                    self.statusLabel?.stringValue = "🔴 Nicht installiert"
                    self.statusLabel?.textColor = NSColor.systemRed
                }

                if hasKext {
                    self.kextStatusLabel?.stringValue = "⚠️ Aktiv (Blockiert modernen Treiber!)"
                    self.kextStatusLabel?.textColor = NSColor.systemOrange
                } else {
                    self.kextStatusLabel?.stringValue = "🟢 Keine störenden Kexts"
                    self.kextStatusLabel?.textColor = NSColor.systemGreen
                }

                if !agentPid.isEmpty {
                    self.agentStatusLabel?.stringValue = "🟢 Aktiv (PID: \(agentPid))"
                    self.agentStatusLabel?.textColor = NSColor.systemGreen
                } else {
                    self.agentStatusLabel?.stringValue = "🔴 Gestoppt"
                    self.agentStatusLabel?.textColor = NSColor.systemRed
                }

                if hasDevice {
                    self.deviceStatusLabel?.stringValue = "🟢 Rane Sixty-Eight erkannt (USB 2.0)"
                    self.deviceStatusLabel?.textColor = NSColor.systemGreen
                } else {
                    self.deviceStatusLabel?.stringValue = "🔴 Nicht angeschlossen"
                    self.deviceStatusLabel?.textColor = NSColor.systemRed
                }
            }
        }
    }
}
