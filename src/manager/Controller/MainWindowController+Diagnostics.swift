import Cocoa
import IOKit

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

            // 2. LaunchAgent Check (Native Darwin API - 0 subprocesses/fork overhead)
            let agentPidInt = self.findProcessPid(named: "RaneMIDIAgent")
            let agentPid = (agentPidInt != nil) ? "\(agentPidInt!)" : ""

            // 3. USB Sixty-Eight Verbindung via CoreMIDI
            let hasDevice = RaneMidiService.shared.isConnected

            // 4. Mixer Firmware Version via IOKit USB Registry
            let fwInfo = self.queryMixerFirmware()

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

                if hasDevice || fwInfo != nil {
                    self.deviceStatusLabel?.stringValue = "🟢 Rane Sixty-Eight erkannt (USB 2.0)"
                    self.deviceStatusLabel?.textColor = NSColor.systemGreen
                } else {
                    self.deviceStatusLabel?.stringValue = "🔴 Nicht angeschlossen"
                    self.deviceStatusLabel?.textColor = NSColor.systemRed
                }

                if let fw = fwInfo {
                    self.isCustomFirmwareDetected = fw.isCustom
                    let revText = fw.serial.isEmpty ? "" : " (Rev: \(fw.serial))"
                    if fw.isCustom {
                        self.firmwareStatusLabel?.stringValue = "🟢 \(fw.version)\(revText)"
                        self.firmwareStatusLabel?.textColor = NSColor.systemGreen
                    } else {
                        self.firmwareStatusLabel?.stringValue = "🟡 \(fw.version)\(revText)"
                        self.firmwareStatusLabel?.textColor = NSColor.systemOrange
                    }

                    if hasDevice {
                        let shortFw = fw.isCustom ? "FW v2.00 Custom" : "FW v1.40 Orig."
                        self.headerStatusBadge?.stringValue = Localization.tr(
                            en: "  ● Connected (\(shortFw))  ",
                            de: "  ● Verbunden (\(shortFw))  "
                        )
                    }

                    if let badge = self.pgmFirmwareFeatureBadge {
                        if fw.isCustom {
                            badge.stringValue = Localization.tr(
                                en: "  🟢 FW v2.00 Custom Active — LP/HP/MIDI Filter Modes Ready  ",
                                de: "  🟢 FW v2.00 Custom aktiv — LP/HP/MIDI Filter-Modi bereit  "
                            )
                            badge.textColor = NSColor.systemGreen
                            badge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
                        } else {
                            badge.stringValue = Localization.tr(
                                en: "  🟡 Factory FW v1.40 — Flash v2.00 Custom for Filter Modes  ",
                                de: "  🟡 Werks-FW v1.40 — Für Filter-Modi bitte v2.00 Custom flashen  "
                            )
                            badge.textColor = NSColor.systemOrange
                            badge.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.18).cgColor
                        }
                    }
                } else {
                    self.isCustomFirmwareDetected = false
                    self.firmwareStatusLabel?.stringValue = Localization.tr(
                        en: "⚪️ Not detected (Connect mixer — detects v2.00 Custom / v1.40 Original)",
                        de: "⚪️ Nicht ermittelt (Mixer verbinden — erkennt v2.00 Custom / v1.40 Original)"
                    )
                    self.firmwareStatusLabel?.textColor = NSColor.secondaryLabelColor

                    if let badge = self.pgmFirmwareFeatureBadge {
                        badge.stringValue = Localization.tr(
                            en: "  ⚪️ Filter Modes (SysEx 0x06): Requires FW v2.00 Custom  ",
                            de: "  ⚪️ Filter-Modi (SysEx 0x06): Erfordert FW v2.00 Custom  "
                        )
                        badge.textColor = NSColor.secondaryLabelColor
                        badge.layer?.backgroundColor = NSColor(white: 0.25, alpha: 0.35).cgColor
                    }
                }

                self.updateDiagnosticsCpu(usage: RaneCpuService.shared.systemCpuUsage)
            }
        }
    }

    func updateDiagnosticsCpu(usage: Double) {
        guard let label = self.cpuStatusLabel else { return }
        let cpuModel = RaneCpuService.shared.getCpuModelAndCores()
        let dot = (usage > 80.0) ? "🔴" : ((usage > 50.0) ? "🟡" : "🟢")
        let cpuText = "\(dot) \(String(format: "%.1f%%", usage)) — \(cpuModel)"
        label.stringValue = cpuText
        if usage > 80.0 {
            label.textColor = NSColor.systemRed
        } else if usage > 50.0 {
            label.textColor = NSColor.systemOrange
        } else {
            label.textColor = NSColor.systemGreen
        }
    }

    private func queryMixerFirmware() -> (version: String, serial: String, isCustom: Bool, bcd: Int)? {
        for className in ["IOUSBHostDevice", "IOUSBDevice"] {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(className) else { continue }
            let kr = IOServiceGetMatchingServices(mach_port_t(0), matching, &iterator)
            if kr == KERN_SUCCESS {
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    let vid = (IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
                    let name = (IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? ""
                    if vid == 0x1CC5 || name.localizedCaseInsensitiveContains("Rane") || name.localizedCaseInsensitiveContains("Sixty-Eight") {
                        let bcd = (IORegistryEntryCreateCFProperty(service, "bcdDevice" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
                        let serial = (IORegistryEntryCreateCFProperty(service, "kUSBSerialNumberString" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? ""
                        IOObjectRelease(service)
                        IOObjectRelease(iterator)
                        let major = bcd >> 8
                        let minor = bcd & 0xFF
                        if major == 2 {
                            let vStr = Localization.tr(
                                en: "v\(major).\(String(format: "%02x", minor)) Custom (OLED + LP/HP/MIDI Filter Modes active)",
                                de: "v\(major).\(String(format: "%02x", minor)) Custom (OLED + LP/HP/MIDI Filter-Modi aktiv)"
                            )
                            return (vStr, serial, true, bcd)
                        } else if bcd == 0x9900 {
                            let vStr = Localization.tr(
                                en: "Bootloader Recovery Mode (0x9900)",
                                de: "Bootloader Recovery-Modus (0x9900)"
                            )
                            return (vStr, serial, false, bcd)
                        } else {
                            let vStr = (bcd == 0x0100 || serial.contains("RH"))
                                ? Localization.tr(
                                    en: "v1.40 Original (Factory Firmware — without Custom Mod)",
                                    de: "v1.40 Original (Werks-Firmware — ohne Custom-Mod)"
                                )
                                : "v\(major).\(String(format: "%02x", minor))"
                            return (vStr, serial, false, bcd)
                        }
                    }
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                IOObjectRelease(iterator)
            }
        }
        return nil
    }

    private func findProcessPid(named: String) -> pid_t? {
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        if bytes <= 0 { return nil }
        let count = Int(bytes) / MemoryLayout<pid_t>.size
        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 { continue }
            var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            if pathLen > 0 {
                let path = String(cString: pathBuffer)
                if path.hasSuffix("/" + named) || path == named {
                    return pid
                }
            }
        }
        return nil
    }
}
