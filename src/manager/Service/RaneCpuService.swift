/* SPDX-License-Identifier: MIT */
/* RaneCpuService.swift - Lightweight Darwin Mach host CPU load monitor service */

import Foundation
import Darwin

final class RaneCpuService {
    static let shared = RaneCpuService()

    private(set) var systemCpuUsage: Double = 0.0
    private var prevCpuTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var timer: Timer?
    private let lock = NSLock()

    var onCpuUpdate: ((Double) -> Void)?

    private init() {
        start()
    }

    func start() {
        _ = sampleCpu()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let usage = self.sampleCpu()
                self.lock.lock()
                self.systemCpuUsage = usage
                self.lock.unlock()
                self.onCpuUpdate?(usage)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sampleCpu() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }

        let user = cpuLoad.cpu_ticks.0
        let sys = cpuLoad.cpu_ticks.1
        let idle = cpuLoad.cpu_ticks.2
        let nice = cpuLoad.cpu_ticks.3

        guard let prev = prevCpuTicks else {
            prevCpuTicks = (user, sys, idle, nice)
            return 0.0
        }

        let dUser = user >= prev.0 ? user - prev.0 : 0
        let dSys = sys >= prev.1 ? sys - prev.1 : 0
        let dIdle = idle >= prev.2 ? idle - prev.2 : 0
        let dNice = nice >= prev.3 ? nice - prev.3 : 0
        prevCpuTicks = (user, sys, idle, nice)

        let total = dUser + dSys + dIdle + dNice
        guard total > 0 else { return 0.0 }

        let active = dUser + dSys + dNice
        let pct = (Double(active) / Double(total)) * 100.0
        return min(max(pct, 0.0), 100.0)
    }

    /// Returns human-readable CPU model and core count (e.g., "Apple M1 Max (10 Kerne)" or "Intel i9 (16 Kerne)")
    func getCpuModelAndCores() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var model = ""
        if size > 0 {
            var name = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
            model = String(cString: name).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if model.isEmpty {
            #if arch(arm64)
            model = "Apple Silicon"
            #else
            model = "Intel Core"
            #endif
        }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let coresWord = Localization.tr(en: "Cores", de: "Kerne")
        return "\(model) (\(cores) \(coresWord))"
    }
}
