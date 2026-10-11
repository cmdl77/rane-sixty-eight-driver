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
                    let revText = fw.serial.isEmpty ? "" : " (Hardware Rev: \(fw.serial))"
                    self.firmwareStatusLabel?.stringValue = "🟢 \(fw.version)\(revText)"
                    self.firmwareStatusLabel?.textColor = NSColor.systemGreen
                } else {
                    self.firmwareStatusLabel?.stringValue = "⚪️ Nicht ermittelt (Mixer verbinden)"
                    self.firmwareStatusLabel?.textColor = NSColor.secondaryLabelColor
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

    private func queryMixerFirmware() -> (version: String, serial: String)? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOUSBDevice")
        let kr = IOServiceGetMatchingServices(mach_port_t(0), matching, &iterator)
        if kr == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let name = IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                   name.localizedCaseInsensitiveContains("Rane") {
                    let bcd = (IORegistryEntryCreateCFProperty(service, "bcdDevice" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
                    let serial = (IORegistryEntryCreateCFProperty(service, "kUSBSerialNumberString" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? ""
                    IOObjectRelease(service)
                    IOObjectRelease(iterator)
                    let major = bcd >> 8
                    let minor = bcd & 0xFF
                    // Rane Sixty-Eight USB chip reports bcd 0x0100 while internal DSP mixer board runs final v1.40
                    let vStr = (bcd == 256 || serial.contains("RH")) ? "v1.40" : "v\(major).\(String(format: "%02x", minor))"
                    return (vStr, serial)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
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
