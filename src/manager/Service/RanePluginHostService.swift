/* SPDX-License-Identifier: MIT */
/* RanePluginHostService.swift - Universal VST / AudioUnit Plugin Host Engine for Rane Sixty-Eight FlexFX Slots */

import Foundation
import Cocoa
import AudioToolbox
import AVFoundation
import CoreAudioKit

public enum PluginFormat: String, Codable {
    case audioUnit = "AU"
    case vst2      = "VST"
}

public struct PluginComponentInfo: Identifiable {
    public let id: String
    public let name: String
    public let manufacturer: String
    public let format: PluginFormat
    public let path: String?
    public let desc: AudioComponentDescription?
    public let version: String

    public var displayName: String {
        return "\(name) [\(format.rawValue)] (\(manufacturer))"
    }
}

public class PluginSlot {
    public let slotIndex: Int
    public let defaultType: FlexFxType

    public var isCustomPlugin: Bool = false
    public var pluginName: String = "Internal (DaisySP)"
    public var pluginId: String = ""
    public var pluginFormat: PluginFormat = .audioUnit
    public var componentDesc: AudioComponentDescription? = nil
    public var vstPath: String? = nil

    // AudioUnit Instance
    public var avAudioUnit: AVAudioUnit? = nil
    public var audioUnit: AudioUnit? = nil

    // VST2 Instance
    public var vstEffect: UnsafeMutablePointer<AEffect>? = nil
    public var vstBundle: UnsafeMutableRawPointer? = nil

    public var isLoaded: Bool = false

    // Real-Time Pre-allocated Audio Buffers (No allocations on audio thread)
    public let maxFrames: Int = 8192
    public let inL: UnsafeMutablePointer<Float>
    public let inR: UnsafeMutablePointer<Float>
    public let outL: UnsafeMutablePointer<Float>
    public let outR: UnsafeMutablePointer<Float>

    public let rawCallbackPtr: UnsafeMutableRawPointer
    public var renderCallback: AURenderCallbackStruct
    public var outBufList: UnsafeMutablePointer<AudioBufferList>

    public var windowController: NSWindowController? = nil
    private var sampleTime: Float64 = 0.0

    init(slotIndex: Int, defaultType: FlexFxType) {
        self.slotIndex = slotIndex
        self.defaultType = defaultType
        self.pluginName = "Internal (\(defaultType.displayName))"

        self.inL = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        self.inR = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        self.outL = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        self.outR = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        self.inL.initialize(repeating: 0.0, count: maxFrames)
        self.inR.initialize(repeating: 0.0, count: maxFrames)
        self.outL.initialize(repeating: 0.0, count: maxFrames)
        self.outR.initialize(repeating: 0.0, count: maxFrames)

        self.rawCallbackPtr = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
        let ptrArray = self.rawCallbackPtr.assumingMemoryBound(to: UnsafeMutablePointer<Float>.self)
        ptrArray[0] = self.inL
        ptrArray[1] = self.inR

        self.renderCallback = AURenderCallbackStruct(
            inputProc: { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
                guard let ioData = ioData else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(ioData)
                let inPtr = inRefCon.assumingMemoryBound(to: UnsafeMutablePointer<Float>.self)
                if abl.count >= 2 {
                    memcpy(abl[0].mData, inPtr[0], Int(inNumberFrames * 4))
                    memcpy(abl[1].mData, inPtr[1], Int(inNumberFrames * 4))
                }
                return noErr
            },
            inputProcRefCon: self.rawCallbackPtr
        )

        let ablPtr = AudioBufferList.allocate(maximumBuffers: 2)
        ablPtr[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(maxFrames * 4), mData: self.outL)
        ablPtr[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(maxFrames * 4), mData: self.outR)
        self.outBufList = ablPtr.unsafeMutablePointer
    }

    deinit {
        if let vst = vstEffect {
            rane_vst_close(vst, vstBundle)
            vstEffect = nil
            vstBundle = nil
        }
        inL.deallocate()
        inR.deallocate()
        outL.deallocate()
        outR.deallocate()
        rawCallbackPtr.deallocate()
        free(outBufList)
    }

    // Real-Time Safe Audio Rendering
    @inline(__always)
    func processAudio(inPtrL: UnsafePointer<Float>,
                      inPtrR: UnsafePointer<Float>,
                      outPtrL: UnsafeMutablePointer<Float>,
                      outPtrR: UnsafeMutablePointer<Float>,
                      frames: Int) -> Bool {
        guard isLoaded, frames <= maxFrames else { return false }

        // 1. VST2 Native DSP Processing
        if let vst = vstEffect {
            rane_vst_process(vst, inPtrL, inPtrR, outPtrL, outPtrR, Int32(frames))
            return true
        }

        // 2. AudioUnit DSP Processing
        guard let unit = audioUnit else { return false }

        // Copy input frames to pre-allocated buffer
        memcpy(inL, inPtrL, frames * MemoryLayout<Float>.size)
        memcpy(inR, inPtrR, frames * MemoryLayout<Float>.size)

        // Setup buffer byte sizes
        let byteSize = UInt32(frames * MemoryLayout<Float>.size)
        let abl = UnsafeMutableAudioBufferListPointer(outBufList)
        abl[0].mDataByteSize = byteSize
        abl[1].mDataByteSize = byteSize

        var flags: AudioUnitRenderActionFlags = []
        var ts = AudioTimeStamp()
        ts.mFlags = .sampleTimeValid
        ts.mSampleTime = sampleTime

        let status = AudioUnitRender(unit, &flags, &ts, 0, UInt32(frames), outBufList)
        if status == noErr {
            memcpy(outPtrL, outL, frames * MemoryLayout<Float>.size)
            memcpy(outPtrR, outR, frames * MemoryLayout<Float>.size)
            sampleTime += Float64(frames)
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

    private let userDefaultsPrefix = "RaneSixtyEight_PluginSlot_"

    private init() {
        // Initialize 6 FlexFX Slots
        let defaultTypes: [FlexFxType] = [.filter, .flanger, .phaser, .echo, .dubDelay, .reverb]
        for (i, t) in defaultTypes.enumerated() {
            slots.append(PluginSlot(slotIndex: i, defaultType: t))
        }

        rescanAvailablePlugins()
        restoreConfiguredSlots()
    }

    // MARK: - Scan Installed AudioUnit & VST Effects
    public func rescanAvailablePlugins() {
        var list: [PluginComponentInfo] = []

        // 1. Scan AudioUnits via AVAudioUnitComponentManager
        let manager = AVAudioUnitComponentManager.shared()
        let all: [AVAudioUnitComponent] = manager.components(matching: AudioComponentDescription())

        for c in all {
            let t = c.audioComponentDescription.componentType
            if t == kAudioUnitType_Effect || t == kAudioUnitType_MusicEffect {
                let desc = c.audioComponentDescription
                let idStr = String(format: "%08X-%08X-%08X", desc.componentType, desc.componentSubType, desc.componentManufacturer)
                let info = PluginComponentInfo(
                    id: idStr,
                    name: c.name,
                    manufacturer: c.manufacturerName,
                    format: .audioUnit,
                    path: nil,
                    desc: desc,
                    version: c.versionString
                )
                list.append(info)
            }
        }

        // 2. Scan VST Plug-in folders on disk (/Library/Audio/Plug-Ins/VST and ~/Library/Audio/Plug-Ins/VST)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let vstDirs = [
            "/Library/Audio/Plug-Ins/VST",
            "\(homeDir)/Library/Audio/Plug-Ins/VST"
        ]

        let fm = FileManager.default
        for dir in vstDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }

            for file in files {
                if file.hasSuffix(".vst") && !file.hasSuffix(".vst3") {
                    let fullPath = (dir as NSString).appendingPathComponent(file)
                    var nameBuf = [CChar](repeating: 0, count: 256)
                    var vendorBuf = [CChar](repeating: 0, count: 256)
                    var inCh: Int32 = 0
                    var outCh: Int32 = 0

                    if rane_vst_inspect(fullPath, &nameBuf, 256, &vendorBuf, 256, &inCh, &outCh) {
                        let name = String(cString: nameBuf)
                        let vendor = String(cString: vendorBuf)
                        let idStr = "VST:" + fullPath

                        if !list.contains(where: { $0.id == idStr }) {
                            let info = PluginComponentInfo(
                                id: idStr,
                                name: name,
                                manufacturer: vendor,
                                format: .vst2,
                                path: fullPath,
                                desc: nil,
                                version: "VST 2.4"
                            )
                            list.append(info)
                        }
                    }
                }
            }
        }

        // Sort alphabetically by plugin name
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.availablePlugins = list
    }

    // MARK: - Slot Configuration & Instantiation
    public func loadPlugin(slotIndex: Int, pluginInfo: PluginComponentInfo?, completion: ((Bool) -> Void)? = nil) {
        guard slotIndex >= 0 && slotIndex < slots.count else {
            completion?(false)
            return
        }

        let slot = slots[slotIndex]

        // 1. Unload existing plugin if any
        if let existing = slot.audioUnit {
            AudioUnitUninitialize(existing)
            slot.audioUnit = nil
            slot.avAudioUnit = nil
        }
        if let vst = slot.vstEffect {
            rane_vst_close(vst, slot.vstBundle)
            slot.vstEffect = nil
            slot.vstBundle = nil
        }
        slot.isLoaded = false
        slot.windowController?.close()
        slot.windowController = nil

        // If pluginInfo is nil, user selected "Internal (DaisySP)"
        guard let info = pluginInfo else {
            slot.isCustomPlugin = false
            slot.pluginName = "Internal (\(slot.defaultType.displayName))"
            slot.pluginId = ""
            slot.componentDesc = nil
            slot.vstPath = nil
            saveSlotConfig(slotIndex: slotIndex)
            DispatchQueue.main.async { [weak self] in
                self?.onSlotsChanged?()
                completion?(true)
            }
            return
        }

        // 2A. Instantiate VST2 Plugin
        if info.format == .vst2, let vstPath = info.path {
            var bundleRef: UnsafeMutableRawPointer? = nil
            if let effect = rane_vst_load(vstPath, &bundleRef, 48000.0, 512) {
                slot.vstEffect = effect
                slot.vstBundle = bundleRef
                slot.vstPath = vstPath
                slot.pluginFormat = .vst2
                slot.pluginName = info.name
                slot.pluginId = info.id
                slot.componentDesc = nil
                slot.isCustomPlugin = true
                slot.isLoaded = true
                self.saveSlotConfig(slotIndex: slotIndex)
                print("[RanePluginHostService] Slot \(slotIndex) (\(slot.defaultType.displayName)) -> VST Plugin '\(info.name)' erfolgreich aktiviert!")
                DispatchQueue.main.async { [weak self] in
                    self?.onSlotsChanged?()
                    completion?(true)
                }
            } else {
                print("[RanePluginHostService] Fehler beim Laden von VST: \(vstPath)")
                DispatchQueue.main.async { completion?(false) }
            }
            return
        }

        // 2B. Instantiate AudioUnit
        guard let desc = info.desc else {
            completion?(false)
            return
        }

        AVAudioUnit.instantiate(with: desc, options: []) { [weak self, weak slot] (avUnit, error) in
            guard let self = self, let slot = slot else { return }

            if let error = error {
                print("[RanePluginHostService] Fehler beim Laden von \(info.name): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }

            guard let avUnit = avUnit else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            let unit = avUnit.audioUnit

            // Configure Standard 48kHz Stereo Float Linear PCM Non-Interleaved
            var asbd = AudioStreamBasicDescription(
                mSampleRate: 48000.0,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: 2,
                mBitsPerChannel: 32,
                mReserved: 0
            )
            AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
            AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

            var maxFrames: UInt32 = UInt32(slot.maxFrames)
            AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, UInt32(MemoryLayout<UInt32>.size))

            // Attach Render Callback for Audio Input
            var cb = slot.renderCallback
            AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

            let initStatus = AudioUnitInitialize(unit)
            if initStatus != noErr {
                print("[RanePluginHostService] AudioUnitInitialize Warnung: \(initStatus)")
            }

            slot.avAudioUnit = avUnit
            slot.audioUnit = unit
            slot.componentDesc = desc
            slot.vstPath = nil
            slot.pluginFormat = .audioUnit
            slot.pluginName = info.name
            slot.pluginId = info.id
            slot.isCustomPlugin = true
            slot.isLoaded = true

            self.saveSlotConfig(slotIndex: slotIndex)

            print("[RanePluginHostService] Slot \(slotIndex) (\(slot.defaultType.displayName)) -> AU Plugin '\(info.name)' erfolgreich aktiviert!")

            DispatchQueue.main.async {
                self.onSlotsChanged?()
                completion?(true)
            }
        }
    }

    // MARK: - Open Plugin Native UI Window
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

        let winTitle = "\(slot.pluginName) — FlexFX Slot \(slotIndex + 1) (\(slot.defaultType.displayName))"

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = winTitle
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)

        let wc = PluginWindowController(window: window)
        wc.window?.delegate = wc
        wc.onClose = { [weak slot] in
            if let vst = slot?.vstEffect {
                rane_vst_close_editor(vst)
            }
            slot?.windowController = nil
        }
        slot.windowController = wc

        // 0. Native VST2 Cocoa Editor Window
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

        // AudioUnit Editors
        guard let avUnit = slot.avAudioUnit, let unit = slot.audioUnit else { return }

        // 1. Attempt Native AUv2 Cocoa UI
        if let customView = createPluginView(for: unit) {
            window.contentView = customView
            let size = customView.frame.size
            if size.width > 200 && size.height > 150 {
                window.setContentSize(size)
            }
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 2. Attempt Modern AUv3 View Controller
        avUnit.auAudioUnit.requestViewController { [weak window] (vc: NSViewController?) in
            DispatchQueue.main.async {
                guard let window = window else { return }
                if let vc = vc {
                    window.contentViewController = vc
                    let size = vc.view.fittingSize
                    if size.width > 200 && size.height > 150 {
                        window.setContentSize(size)
                    }
                } else {
                    // 3. Clean AUGenericView with all controls & parameters
                    let genView = AUGenericView(audioUnit: unit)
                    window.contentView = genView
                    let fit = genView.fittingSize
                    if fit.width > 300 && fit.height > 200 {
                        window.setContentSize(NSSize(width: max(500, fit.width), height: max(360, fit.height)))
                    }
                }
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func createPluginView(for audioUnit: AudioUnit) -> NSView? {
        var propSize: UInt32 = 0
        var isWritable: DarwinBoolean = false
        let status = AudioUnitGetPropertyInfo(
            audioUnit,
            kAudioUnitProperty_CocoaUI,
            kAudioUnitScope_Global,
            0,
            &propSize,
            &isWritable
        )
        guard status == noErr, propSize > 0 else { return nil }

        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(propSize), alignment: 8)
        defer { data.deallocate() }

        let getStatus = AudioUnitGetProperty(
            audioUnit,
            kAudioUnitProperty_CocoaUI,
            kAudioUnitScope_Global,
            0,
            data,
            &propSize
        )
        guard getStatus == noErr else { return nil }

        let cocoaData = data.assumingMemoryBound(to: AudioUnitCocoaViewInfo.self).pointee
        let bundleURL = cocoaData.mCocoaAUViewBundleLocation.takeUnretainedValue() as URL
        let className = cocoaData.mCocoaAUViewClass.takeUnretainedValue() as String

        if let bundle = Bundle(url: bundleURL),
           let factoryClass = bundle.classNamed(className) as? NSObject.Type {
            let factory = factoryClass.init()
            let sel = Selector(("uiViewForAudioUnit:withSize:"))
            if factory.responds(to: sel) {
                let imp = factory.method(for: sel)
                typealias FunctionType = @convention(c) (AnyObject, Selector, AudioUnit, NSSize) -> Unmanaged<NSView>?
                let function = unsafeBitCast(imp, to: FunctionType.self)
                if let unmanagedView = function(factory, sel, audioUnit, NSSize(width: 600, height: 400)) {
                    return unmanagedView.takeRetainedValue()
                }
            }
        }
        return nil
    }

    // MARK: - Real-Time Audio Block Processing
    @inline(__always)
    public func processSlot(_ slotIndex: Int,
                            inL: UnsafePointer<Float>,
                            inR: UnsafePointer<Float>,
                            outL: UnsafeMutablePointer<Float>,
                            outR: UnsafeMutablePointer<Float>,
                            frames: Int) -> Bool {
        guard slotIndex >= 0 && slotIndex < slots.count else { return false }
        let slot = slots[slotIndex]
        guard slot.isLoaded else { return false }
        return slot.processAudio(inPtrL: inL, inPtrR: inR, outPtrL: outL, outPtrR: outR, frames: frames)
    }

    // MARK: - Persistence (UserDefaults)
    private func saveSlotConfig(slotIndex: Int) {
        let slot = slots[slotIndex]
        let key = "\(userDefaultsPrefix)\(slotIndex)"
        if slot.isCustomPlugin {
            UserDefaults.standard.set(slot.pluginId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func restoreConfiguredSlots() {
        for (i, _) in slots.enumerated() {
            let key = "\(userDefaultsPrefix)\(i)"
            if let savedId = UserDefaults.standard.string(forKey: key), !savedId.isEmpty {
                if let match = availablePlugins.first(where: { $0.id == savedId }) {
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
