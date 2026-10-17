/* SPDX-License-Identifier: MIT */
/* RanePluginHostService.swift - Universal VST2 & VST3 Plugin Host Engine for Rane Sixty-Eight FlexFX Slots */

import Foundation
import Cocoa

public enum PluginFormat: String, Codable {
    case vst2 = "VST2"
    case vst3 = "VST3"
}

public struct PluginComponentInfo: Identifiable {
    public let id: String
    public let name: String
    public let manufacturer: String
    public let format: PluginFormat
    public let path: String
    public let version: String

    public var displayName: String {
        return "\(name) [\(format.rawValue)] (\(manufacturer))"
    }
}

public class PluginSlot {
    public let slotIndex: Int
    public var defaultType: FlexFxType

    public var isCustomPlugin: Bool = false
    public var pluginName: String = "Internal (DaisySP)"
    public var pluginId: String = ""
    public var pluginFormat: PluginFormat = .vst3
    public var vstPath: String? = nil

    // MIDI Routing Configuration per VST Slot
    // "OMNI" = All MIDI Controllers, "CLOCK_ONLY" = Only Tempo/MIDI Clock, "OFF" = No MIDI, or specific MidiInputDeviceInfo.id
    public var midiInputSourceId: String = "OMNI"
    public var midiChannelFilter: Int = 0 // 0 = All Channels (1-16), 1..16 = Ch 1..16
    public var sendMidiClock: Bool = true
    public var lastMidiEventTime: TimeInterval = 0
    public var lastMidiEventSummary: String = "Bereit (Clock Sync)"

    // VST2 Instance
    public var vstEffect: UnsafeMutablePointer<AEffect>? = nil
    public var vstBundle: UnsafeMutableRawPointer? = nil

    // VST3 Instance (OpaquePointer to RaneVst3Instance)
    public var vst3Instance: OpaquePointer? = nil

    public var isLoaded: Bool = false
    public let maxFrames: Int = 8192
    public var windowController: NSWindowController? = nil

    init(slotIndex: Int, defaultType: FlexFxType) {
        self.slotIndex = slotIndex
        self.defaultType = defaultType
        self.pluginName = "Internal (\(defaultType.displayName))"
    }

    deinit {
        unloadPluginInstance()
    }

    public func unloadPluginInstance() {
        isLoaded = false
        windowController?.close()
        windowController = nil

        if let vst3 = vst3Instance {
            rane_vst3_close(vst3)
            vst3Instance = nil
        }
        if let vst = vstEffect {
            rane_vst_close(vst, vstBundle)
            vstEffect = nil
            vstBundle = nil
        }
    }

    // Send MIDI message (Note, CC, PitchBend, or 0xF8 MIDI Clock) to loaded VST2 or VST3 plugin
    public func sendMidiEvent(status: UInt8, d1: UInt8, d2: UInt8, deltaFrames: Int32 = 0) {
        guard isLoaded else { return }

        if let vst3 = vst3Instance {
            rane_vst3_send_midi(vst3, status, d1, d2, deltaFrames)
        } else if let vst = vstEffect {
            rane_vst_send_midi(vst, status, d1, d2, deltaFrames)
        }

        if status < 0xF8 {
            lastMidiEventTime = Date().timeIntervalSince1970
            let typeNib = status & 0xF0
            let ch = (status & 0x0F) + 1
            if typeNib == 0x90 && d2 > 0 {
                lastMidiEventSummary = "Ch\(ch) Note \(d1) (\(d2))"
            } else if typeNib == 0xB0 {
                lastMidiEventSummary = "Ch\(ch) CC#\(d1)=\(d2)"
            }
        }
    }

    // Real-Time Safe Audio Rendering (VST3 & VST2)
    @inline(__always)
    func processAudio(inPtrL: UnsafePointer<Float>,
                      inPtrR: UnsafePointer<Float>,
                      outPtrL: UnsafeMutablePointer<Float>,
                      outPtrR: UnsafeMutablePointer<Float>,
                      frames: Int,
                      bpm: Double = 124.0,
                      sampleRate: Double = 48000.0) -> Bool {
        guard isLoaded, frames <= maxFrames else { return false }

        // 1. VST3 Native DSP Processing (includes ProcessContext BPM/PPQ & 24 PPQN Clock + Parameter Changes + MIDI Events)
        if let vst3 = vst3Instance {
            rane_vst3_process(vst3, inPtrL, inPtrR, outPtrL, outPtrR, Int32(frames))
            return true
        }

        // 2. VST2 Native DSP Processing (includes VstTimeInfo & 24 PPQN 0xF8 MIDI Clock via rane_vst_process)
        if let vst = vstEffect {
            rane_vst_process(vst, inPtrL, inPtrR, outPtrL, outPtrR, Int32(frames))
            return true
        }

        return false
    }
}

public class RanePluginHostService {
    public static let shared = RanePluginHostService()

    public private(set) var availablePlugins: [PluginComponentInfo] = []
    public private(set) var slots: [PluginSlot] = []

    public var onSlotsChanged: (() -> Void)?
    public var onSlotMidiActivity: ((Int) -> Void)?

    private let userDefaultsPrefix = "RaneSixtyEight_PluginSlot_"
    private let midiSourcePrefix = "RaneSixtyEight_PluginMidiSource_"
    private let midiChannelPrefix = "RaneSixtyEight_PluginMidiChannel_"
    private let midiClockPrefix = "RaneSixtyEight_PluginMidiClock_"

    private init() {
        // Initialize FlexFX Slots (Slot 0 = VST Effekt 1 [default Echo], Slot 1 = VST Effekt 2 [default Reverb], plus 2..5)
        let defaultTypes: [FlexFxType] = [.echo, .reverb, .phaser, .filter, .flanger, .dubDelay]
        for (i, t) in defaultTypes.enumerated() {
            slots.append(PluginSlot(slotIndex: i, defaultType: t))
        }

        rescanAvailablePlugins()
        restoreConfiguredSlots()
    }

    // MARK: - Scan Installed VST2 (.vst) & VST3 (.vst3) Effects Only (No AudioUnits!)
    public func rescanAvailablePlugins() {
        var list: [PluginComponentInfo] = []
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        // 1. Scan VST3 Plug-in directories (/Library/Audio/Plug-Ins/VST3 and ~/Library/Audio/Plug-Ins/VST3)
        let vst3Dirs = [
            "/Library/Audio/Plug-Ins/VST3",
            "\(homeDir)/Library/Audio/Plug-Ins/VST3"
        ]
        for baseDir in vst3Dirs {
            scanPluginDirectory(baseDir: baseDir, ext: "vst3", format: .vst3, fm: fm, into: &list)
        }

        // 2. Scan VST2 Plug-in directories (/Library/Audio/Plug-Ins/VST and ~/Library/Audio/Plug-Ins/VST)
        let vst2Dirs = [
            "/Library/Audio/Plug-Ins/VST",
            "\(homeDir)/Library/Audio/Plug-Ins/VST"
        ]
        for baseDir in vst2Dirs {
            scanPluginDirectory(baseDir: baseDir, ext: "vst", format: .vst2, fm: fm, into: &list)
        }

        // Sort alphabetically by plugin name (preferring VST3 first if names are identical)
        list.sort {
            let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
            if cmp == .orderedSame {
                return $0.format == .vst3 && $1.format == .vst2
            }
            return cmp == .orderedAscending
        }

        self.availablePlugins = list
    }

    private func scanPluginDirectory(baseDir: String,
                                     ext: String,
                                     format: PluginFormat,
                                     fm: FileManager,
                                     into list: inout [PluginComponentInfo]) {
        guard fm.fileExists(atPath: baseDir) else { return }
        let baseURL = URL(fileURLWithPath: baseDir)

        guard let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let pathExt = fileURL.pathExtension.lowercased()
            if pathExt == ext {
                // Do not descend inside a .vst or .vst3 bundle
                enumerator.skipDescendants()

                let fullPath = fileURL.path
                let idPrefix = (format == .vst3) ? "VST3:" : "VST:"
                let idStr = idPrefix + fullPath

                if list.contains(where: { $0.id == idStr }) {
                    continue
                }

                // Verify executable exists inside bundle
                let macOSDir = (fullPath as NSString).appendingPathComponent("Contents/MacOS")
                guard fm.fileExists(atPath: macOSDir) else { continue }

                let meta = extractBundleMetadata(bundlePath: fullPath, fallbackFormat: format)
                let info = PluginComponentInfo(
                    id: idStr,
                    name: meta.name,
                    manufacturer: meta.vendor,
                    format: format,
                    path: fullPath,
                    version: meta.version
                )
                list.append(info)
            }
        }
    }

    private func extractBundleMetadata(bundlePath: String, fallbackFormat: PluginFormat) -> (name: String, vendor: String, version: String) {
        let url = URL(fileURLWithPath: bundlePath)
        let defaultName = url.deletingPathExtension().lastPathComponent
        let plistPath = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")

        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            return (defaultName, fallbackFormat.rawValue, fallbackFormat.rawValue)
        }

        var name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? (dict["CFBundleExecutable"] as? String)
            ?? defaultName
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = defaultName }

        let version = (dict["CFBundleShortVersionString"] as? String)
            ?? (dict["CFBundleVersion"] as? String)
            ?? fallbackFormat.rawValue

        let bundleId = (dict["CFBundleIdentifier"] as? String)?.lowercased() ?? ""
        let getInfo = (dict["CFBundleGetInfoString"] as? String) ?? ""
        let copyright = (dict["NSHumanReadableCopyright"] as? String) ?? ""

        var vendor = "VST Plug-In"
        if bundleId.contains("valhalladsp") || getInfo.localizedCaseInsensitiveContains("Valhalla") || copyright.localizedCaseInsensitiveContains("Valhalla") {
            vendor = "Valhalla DSP"
        } else if bundleId.contains("fabfilter") || getInfo.localizedCaseInsensitiveContains("FabFilter") || copyright.localizedCaseInsensitiveContains("FabFilter") {
            vendor = "FabFilter"
        } else if bundleId.contains("izotope") || getInfo.localizedCaseInsensitiveContains("iZotope") || copyright.localizedCaseInsensitiveContains("iZotope") {
            vendor = "iZotope"
        } else if bundleId.contains("native-instruments") || getInfo.localizedCaseInsensitiveContains("Native Instruments") || copyright.localizedCaseInsensitiveContains("Native Instruments") {
            vendor = "Native Instruments"
        } else if bundleId.contains("sonarworks") || getInfo.localizedCaseInsensitiveContains("Sonarworks") || copyright.localizedCaseInsensitiveContains("Sonarworks") {
            vendor = "Sonarworks"
        } else if !bundleId.isEmpty {
            let parts = bundleId.split(separator: ".")
            if parts.count >= 2 {
                let rawVendor = String(parts[1])
                vendor = rawVendor.prefix(1).uppercased() + rawVendor.dropFirst()
            }
        }

        return (name, vendor, version)
    }

    // MARK: - Slot Configuration & Instantiation
    public func loadPlugin(slotIndex: Int, pluginInfo: PluginComponentInfo?, completion: ((Bool) -> Void)? = nil) {
        guard slotIndex >= 0 && slotIndex < slots.count else {
            completion?(false)
            return
        }

        let slot = slots[slotIndex]

        // 1. Unload existing plugin if any
        slot.unloadPluginInstance()

        // If pluginInfo is nil, user selected "Internal (DaisySP)"
        guard let info = pluginInfo else {
            slot.isCustomPlugin = false
            slot.pluginName = "Internal (\(slot.defaultType.displayName))"
            slot.pluginId = ""
            slot.vstPath = nil
            saveSlotConfig(slotIndex: slotIndex)
            DispatchQueue.main.async { [weak self] in
                self?.onSlotsChanged?()
                completion?(true)
            }
            return
        }

        // 2A. Instantiate VST3 Plugin (.vst3)
        if info.format == .vst3 {
            let vstPath = info.path
            if let inst = rane_vst3_load(vstPath, 48000.0, 512) {
                slot.vst3Instance = inst
                slot.vstPath = vstPath
                slot.pluginFormat = .vst3
                slot.pluginName = info.name
                slot.pluginId = info.id
                slot.isCustomPlugin = true
                slot.isLoaded = true
                self.saveSlotConfig(slotIndex: slotIndex)
                print("[RanePluginHostService] Slot \(slotIndex) (\(slot.defaultType.displayName)) -> VST3 Plugin '\(info.name)' (\(info.manufacturer)) erfolgreich aktiviert!")
                DispatchQueue.main.async { [weak self] in
                    self?.onSlotsChanged?()
                    completion?(true)
                }
            } else {
                print("[RanePluginHostService] Fehler beim Laden von VST3: \(vstPath)")
                DispatchQueue.main.async { completion?(false) }
            }
            return
        }

        // 2B. Instantiate VST2 Plugin (.vst)
        if info.format == .vst2 {
            let vstPath = info.path
            var bundleRef: UnsafeMutableRawPointer? = nil
            if let effect = rane_vst_load(vstPath, &bundleRef, 48000.0, 512) {
                slot.vstEffect = effect
                slot.vstBundle = bundleRef
                slot.vstPath = vstPath
                slot.pluginFormat = .vst2
                slot.pluginName = info.name
                slot.pluginId = info.id
                slot.isCustomPlugin = true
                slot.isLoaded = true
                self.saveSlotConfig(slotIndex: slotIndex)
                print("[RanePluginHostService] Slot \(slotIndex) (\(slot.defaultType.displayName)) -> VST2 Plugin '\(info.name)' (\(info.manufacturer)) erfolgreich aktiviert!")
                DispatchQueue.main.async { [weak self] in
                    self?.onSlotsChanged?()
                    completion?(true)
                }
            } else {
                print("[RanePluginHostService] Fehler beim Laden von VST2: \(vstPath)")
                DispatchQueue.main.async { completion?(false) }
            }
            return
        }
    }

    // MARK: - Per-Slot Internal Type & MIDI Configuration
    public func setSlotInternalType(slotIndex: Int, fxType: FlexFxType) {
        guard slotIndex >= 0 && slotIndex < slots.count else { return }
        let slot = slots[slotIndex]
        slot.unloadPluginInstance()
        slot.isCustomPlugin = false
        slot.pluginId = ""
        slot.vstPath = nil
        slot.defaultType = fxType
        slot.pluginName = "Internal (\(fxType.displayName))"
        saveSlotConfig(slotIndex: slotIndex)
        DispatchQueue.main.async { [weak self] in
            self?.onSlotsChanged?()
        }
    }

    public func setSlotMidiSource(slotIndex: Int, sourceId: String) {
        guard slotIndex >= 0 && slotIndex < slots.count else { return }
        slots[slotIndex].midiInputSourceId = sourceId
        saveSlotConfig(slotIndex: slotIndex)
        DispatchQueue.main.async { [weak self] in
            self?.onSlotsChanged?()
        }
    }

    public func setSlotMidiChannel(slotIndex: Int, channel: Int) {
        guard slotIndex >= 0 && slotIndex < slots.count else { return }
        slots[slotIndex].midiChannelFilter = max(0, min(16, channel))
        saveSlotConfig(slotIndex: slotIndex)
        DispatchQueue.main.async { [weak self] in
            self?.onSlotsChanged?()
        }
    }

    public func setSlotSendMidiClock(slotIndex: Int, enabled: Bool) {
        guard slotIndex >= 0 && slotIndex < slots.count else { return }
        slots[slotIndex].sendMidiClock = enabled
        saveSlotConfig(slotIndex: slotIndex)
        DispatchQueue.main.async { [weak self] in
            self?.onSlotsChanged?()
        }
    }

    // MARK: - Route Incoming MIDI Events & External MIDI Clock to VST Slots
    public func routeIncomingMidi(fromSourceId sourceId: String, status: UInt8, d1: UInt8, d2: UInt8) {
        // Deliver to Slot 0 (VST Effekt 1) and Slot 1 (VST Effekt 2)
        for slotIdx in 0..<min(2, slots.count) {
            let slot = slots[slotIdx]
            let cfgSource = slot.midiInputSourceId
            if cfgSource == "OFF" { continue }

            if status >= 0xF8 && status <= 0xFC {
                // System Real-Time (MIDI Clock / Start / Stop)
                if slot.sendMidiClock && (cfgSource == "OMNI" || cfgSource == "CLOCK_ONLY" || cfgSource == sourceId) {
                    slot.sendMidiEvent(status: status, d1: 0, d2: 0, deltaFrames: 0)
                }
            } else if status >= 0x80 && status < 0xF0 {
                // Channel Voice Messages (Notes, CCs, PitchBend, Aftertouch, Program Change)
                if cfgSource == "CLOCK_ONLY" { continue }
                if cfgSource != "OMNI" && cfgSource != sourceId { continue }

                if slot.midiChannelFilter > 0 {
                    let msgCh = Int(status & 0x0F) + 1
                    if msgCh != slot.midiChannelFilter { continue }
                }

                slot.sendMidiEvent(status: status, d1: d1, d2: d2, deltaFrames: 0)
                DispatchQueue.main.async { [weak self] in
                    self?.onSlotMidiActivity?(slotIdx)
                }
            }
        }
    }

    // MARK: - Open Plugin Native UI Window (VST3 & VST2)
    public func openPluginUI(for slotIndex: Int) {
        guard slotIndex >= 0 && slotIndex < slots.count else { return }
        let slot = slots[slotIndex]

        guard slot.isCustomPlugin else { return }

        // If window is already open, bring to front
        if let wc = slot.windowController, let win = wc.window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let winTitle = "\(slot.pluginName) [\(slot.pluginFormat.rawValue)] — VST Effekt \(slotIndex + 1)"

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = winTitle
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)

        let wc = PluginWindowController(window: window)
        wc.window?.delegate = wc
        wc.onClose = { [weak slot] in
            if let vst3 = slot?.vst3Instance {
                rane_vst3_close_editor(vst3)
            }
            if let vst = slot?.vstEffect {
                rane_vst_close_editor(vst)
            }
            slot?.windowController = nil
        }
        slot.windowController = wc

        // 1. Native VST3 IPlugView NSView Editor Window
        if let vst3 = slot.vst3Instance {
            var w: Int32 = 720
            var h: Int32 = 480
            if rane_vst3_get_editor_rect(vst3, &w, &h) && w > 100 && h > 100 {
                window.setContentSize(NSSize(width: CGFloat(w), height: CGFloat(h)))
            }
            if let cv = window.contentView {
                _ = rane_vst3_open_editor(vst3, Unmanaged.passUnretained(cv).toOpaque())
            }
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 2. Native VST2 Cocoa Editor Window
        if let vst = slot.vstEffect {
            var w: Int32 = 640
            var h: Int32 = 400
            if rane_vst_get_editor_rect(vst, &w, &h) && w > 100 && h > 100 {
                window.setContentSize(NSSize(width: CGFloat(w), height: CGFloat(h)))
            }
            if let cv = window.contentView {
                rane_vst_open_editor(vst, Unmanaged.passUnretained(cv).toOpaque())
            }
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
    }

    // MARK: - Real-Time Audio Block Processing
    @inline(__always)
    public func processSlot(_ slotIndex: Int,
                            inL: UnsafePointer<Float>,
                            inR: UnsafePointer<Float>,
                            outL: UnsafeMutablePointer<Float>,
                            outR: UnsafeMutablePointer<Float>,
                            frames: Int,
                            bpm: Double = 124.0,
                            sampleRate: Double = 48000.0) -> Bool {
        guard slotIndex >= 0 && slotIndex < slots.count else { return false }
        let slot = slots[slotIndex]
        guard slot.isLoaded else { return false }
        return slot.processAudio(inPtrL: inL, inPtrR: inR, outPtrL: outL, outPtrR: outR, frames: frames, bpm: bpm, sampleRate: sampleRate)
    }

    // MARK: - Persistence (UserDefaults)
    private func saveSlotConfig(slotIndex: Int) {
        let slot = slots[slotIndex]
        let key = "\(userDefaultsPrefix)\(slotIndex)"
        if slot.isCustomPlugin {
            UserDefaults.standard.set(slot.pluginId, forKey: key)
        } else {
            UserDefaults.standard.set("INTERNAL:\(slot.defaultType.rawValue)", forKey: key)
        }
        UserDefaults.standard.set(slot.midiInputSourceId, forKey: "\(midiSourcePrefix)\(slotIndex)")
        UserDefaults.standard.set(slot.midiChannelFilter, forKey: "\(midiChannelPrefix)\(slotIndex)")
        UserDefaults.standard.set(slot.sendMidiClock, forKey: "\(midiClockPrefix)\(slotIndex)")
    }

    private func restoreConfiguredSlots() {
        for (i, slot) in slots.enumerated() {
            if let savedSrc = UserDefaults.standard.string(forKey: "\(midiSourcePrefix)\(i)"), !savedSrc.isEmpty {
                slot.midiInputSourceId = savedSrc
            }
            if UserDefaults.standard.object(forKey: "\(midiChannelPrefix)\(i)") != nil {
                slot.midiChannelFilter = UserDefaults.standard.integer(forKey: "\(midiChannelPrefix)\(i)")
            }
            if UserDefaults.standard.object(forKey: "\(midiClockPrefix)\(i)") != nil {
                slot.sendMidiClock = UserDefaults.standard.bool(forKey: "\(midiClockPrefix)\(i)")
            }

            let key = "\(userDefaultsPrefix)\(i)"
            if let savedId = UserDefaults.standard.string(forKey: key), !savedId.isEmpty {
                if savedId.hasPrefix("INTERNAL:") {
                    let numStr = String(savedId.dropFirst("INTERNAL:".count))
                    if let raw = Int(numStr), let fx = FlexFxType(rawValue: raw) {
                        slot.defaultType = fx
                        slot.pluginName = "Internal (\(fx.displayName))"
                    }
                } else if let match = availablePlugins.first(where: { $0.id == savedId }) {
                    loadPlugin(slotIndex: i, pluginInfo: match)
                }
            }
        }
    }
}

class PluginWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
