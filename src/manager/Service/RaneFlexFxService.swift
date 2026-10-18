/* SPDX-License-Identifier: MIT */
/* RaneFlexFxService.swift - Software VST2 Channel Strip & FlexFX Engine with Native Ableton Link & CoreAudio IO Loop */

import Foundation
import CoreAudio
import AudioToolbox
import CoreMIDI

public enum FlexFxType: Int, CaseIterable, Codable {
    case filter   = 0
    case flanger  = 1
    case phaser   = 2
    case echo     = 3
    case dubDelay = 4
    case reverb   = 5

    public var displayName: String {
        switch self {
        case .filter:   return "FILTER"
        case .flanger:  return "FLANGER"
        case .phaser:   return "PHASER"
        case .echo:     return "ECHO"
        case .dubDelay: return "DUB DELAY"
        case .reverb:   return "REVERB"
        }
    }

    public var activeDisplayName: String {
        let slots = RanePluginHostService.shared.slots
        if self.rawValue < slots.count {
            let slot = slots[self.rawValue]
            if slot.isCustomPlugin {
                return slot.pluginName.uppercased()
            }
        }
        return self.displayName
    }
}

public enum FlexFxInputSource: Int, CaseIterable, Codable {
    case flexFxSend = 0 // USB Ch 9-10 (Mixer HW FlexFX Send Bus, default)
    case pgm1       = 1 // USB Ch 1-2  (Deck 1)
    case pgm2       = 2 // USB Ch 3-4  (Deck 2)
    case pgm3       = 3 // USB Ch 5-6  (Deck 3)
    case pgm4       = 4 // USB Ch 7-8  (Deck 4)
    case mainMix    = 5 // USB Ch 11-12 (Main Mix / Mic)

    /// Ordered sequentially by USB Record Channel Pair (Ch 1-2 ... Ch 11-12)
    public static var orderedByChannel: [FlexFxInputSource] {
        return [.pgm1, .pgm2, .pgm3, .pgm4, .flexFxSend, .mainMix]
    }

    public var displayName: String {
        switch self {
        case .pgm1:       return "Ch 1–2 (PGM 1 / Deck 1)"
        case .pgm2:       return "Ch 3–4 (PGM 2 / Deck 2)"
        case .pgm3:       return "Ch 5–6 (PGM 3 / Deck 3)"
        case .pgm4:       return "Ch 7–8 (PGM 4 / Deck 4)"
        case .flexFxSend: return "Ch 9–10 (FlexFX Send)"
        case .mainMix:    return "Ch 11–12 (Main Mix / Mic)"
        }
    }

    public var shortName: String {
        switch self {
        case .pgm1:       return "CH 1-2 (PGM 1)"
        case .pgm2:       return "CH 3-4 (PGM 2)"
        case .pgm3:       return "CH 5-6 (PGM 3)"
        case .pgm4:       return "CH 7-8 (PGM 4)"
        case .flexFxSend: return "CH 9-10 (FLEXFX)"
        case .mainMix:    return "CH 11-12 (MAIN)"
        }
    }

    public var channelOffset: Int {
        switch self {
        case .pgm1:       return 0
        case .pgm2:       return 2
        case .pgm3:       return 4
        case .pgm4:       return 6
        case .flexFxSend: return 8
        case .mainMix:    return 10
        }
    }
}

public enum FlexFxOutputDestination: Int, CaseIterable, Codable {
    case flexFxReturn = 0 // USB Ch 9-10 (Mixer HW FlexFX Return Bus, default)
    case pgm1         = 1 // USB Ch 1-2  (Deck 1)
    case pgm2         = 2 // USB Ch 3-4  (Deck 2)
    case pgm3         = 3 // USB Ch 5-6  (Deck 3)
    case pgm4         = 4 // USB Ch 7-8  (Deck 4)

    /// Ordered sequentially by USB Playback Channel Pair (Ch 1-2 ... Ch 9-10)
    public static var orderedByChannel: [FlexFxOutputDestination] {
        return [.pgm1, .pgm2, .pgm3, .pgm4, .flexFxReturn]
    }

    public var displayName: String {
        switch self {
        case .pgm1:         return "Ch 1–2 (PGM 1 / Deck 1)"
        case .pgm2:         return "Ch 3–4 (PGM 2 / Deck 2)"
        case .pgm3:         return "Ch 5–6 (PGM 3 / Deck 3)"
        case .pgm4:         return "Ch 7–8 (PGM 4 / Deck 4)"
        case .flexFxReturn: return "Ch 9–10 (FlexFX Return)"
        }
    }

    public var shortName: String {
        switch self {
        case .pgm1:         return "CH 1-2 (PGM 1)"
        case .pgm2:         return "CH 3-4 (PGM 2)"
        case .pgm3:         return "CH 5-6 (PGM 3)"
        case .pgm4:         return "CH 7-8 (PGM 4)"
        case .flexFxReturn: return "CH 9-10 (RETURN)"
        }
    }

    public var channelOffset: Int {
        switch self {
        case .pgm1:         return 0
        case .pgm2:         return 2
        case .pgm3:         return 4
        case .pgm4:         return 6
        case .flexFxReturn: return 8
        }
    }
}

public struct FxParameters: Codable {
    public var filterCutoff: Double = 1200.0
    public var filterResonance: Double = 2.0
    public var filterLfoRate: Double = 0.5
    public var filterLfoDepth: Double = 0.4
    public var flangerRate: Double = 0.4
    public var flangerDepth: Double = 0.7
    public var flangerFeedback: Double = 0.6
    public var flangerManual: Double = 3.0
    public var phaserRate: Double = 0.35
    public var phaserDepth: Double = 0.75
    public var phaserFeedback: Double = 0.5
    public var phaserBaseFreq: Double = 800.0
    public var echoHighCut: Double = 5000.0
    public var echoPingPong: Double = 0.5
    public var echoSpread: Double = 20.0
    public var dubSaturation: Double = 0.6
    public var dubHighCut: Double = 2800.0
    public var dubFlutter: Double = 0.35
    public var dubResonance: Double = 0.7
    public var reverbRoomSize: Double = 0.75
    public var reverbDamping: Double = 0.4
    public var reverbPreDelay: Double = 25.0
    public var reverbWidth: Double = 0.85

    public init() {}
}

public enum BeatDivision: Int, CaseIterable {
    case d1_8 = 0
    case d1_4 = 1
    case d1_2 = 2
    case d3_4 = 3
    case d1_1 = 4
    case d2_1 = 5
    case d4_1 = 6

    public var label: String {
        switch self {
        case .d1_8: return "1/8"
        case .d1_4: return "1/4"
        case .d1_2: return "1/2"
        case .d3_4: return "3/4"
        case .d1_1: return "1/1"
        case .d2_1: return "2/1"
        case .d4_1: return "4/1"
        }
    }

    public var multiplier: Double {
        switch self {
        case .d1_8: return 0.125
        case .d1_4: return 0.25
        case .d1_2: return 0.5
        case .d3_4: return 0.75
        case .d1_1: return 1.0
        case .d2_1: return 2.0
        case .d4_1: return 4.0
        }
    }
}

// MARK: - Dedicated Channel Strip State (PGM 1..4 & FlexFX)
public class ChannelStripState {
    public let channelIndex: Int // 0..4
    public let name: String
    public let shortName: String
    public let inOffset: Int
    public let outOffset: Int

    public var isModuleEnabled: Bool = true {
        didSet {
            onGainChanged?()
            onParamChanged?()
        }
    }
    public var isFx1Enabled: Bool = true {
        didSet {
            onGainChanged?()
            onParamChanged?()
        }
    }
    public var isFx2Enabled: Bool = false {
        didSet {
            onGainChanged?()
            onParamChanged?()
        }
    }
    public var fx1PreGain: Double = 1.0 {
        didSet { onGainChanged?() }
    }
    public var fx1PostGain: Double = 1.0 {
        didSet { onParamChanged?() }
    }
    public var fx1DryDuckRatio: Double = 0.5 {
        didSet { onGainChanged?() }
    }
    public var fx2PreGain: Double = 1.0 {
        didSet { onGainChanged?() }
    }
    public var fx2PostGain: Double = 1.0 {
        didSet { onParamChanged?() }
    }
    public var fx2DryDuckRatio: Double = 0.5 {
        didSet { onGainChanged?() }
    }
    public var dryPreGain: Double = 1.0 {
        didSet {
            if !isInternalDryUpdate {
                dryBasePreGain = dryPreGain
                onParamChanged?()
            }
        }
    }
    public var dryBasePreGain: Double = 1.0
    public var dryPostGain: Double = 1.0 {
        didSet { onParamChanged?() }
    }

    public var isInternalDryUpdate: Bool = false
    public var onParamChanged: (() -> Void)?
    public var onGainChanged: (() -> Void)?

    // Live Peak Meters (0.0 .. 1.0)
    public var liveInPeak: Float = 0.0
    public var liveFx1Peak: Float = 0.0
    public var liveFx2Peak: Float = 0.0
    public var liveDryPeak: Float = 0.0
    public var liveOutPeak: Float = 0.0

    public var slotIndex: Int { return channelIndex }
    public var slot1Index: Int { return channelIndex }
    public var slot2Index: Int { return channelIndex }

    public init(channelIndex: Int, name: String, shortName: String, inOffset: Int, outOffset: Int) {
        self.channelIndex = channelIndex
        self.name = name
        self.shortName = shortName
        self.inOffset = inOffset
        self.outOffset = outOffset
    }
}

public class RaneFlexFxService {
    public static let shared = RaneFlexFxService()

    // 5 Dedicated Channel Strips: PGM 1 (Deck 1), PGM 2 (Deck 2), PGM 3 (Deck 3), PGM 4 (Deck 4), FlexFX Return
    public let channels: [ChannelStripState] = [
        ChannelStripState(channelIndex: 0, name: "PGM 1 (Deck 1)", shortName: "PGM 1", inOffset: 0, outOffset: 0),
        ChannelStripState(channelIndex: 1, name: "PGM 2 (Deck 2)", shortName: "PGM 2", inOffset: 2, outOffset: 2),
        ChannelStripState(channelIndex: 2, name: "PGM 3 (Deck 3)", shortName: "PGM 3", inOffset: 4, outOffset: 4),
        ChannelStripState(channelIndex: 3, name: "PGM 4 (Deck 4)", shortName: "PGM 4", inOffset: 6, outOffset: 6),
        ChannelStripState(channelIndex: 4, name: "FlexFX (Send/Return)", shortName: "FLEXFX", inOffset: 8, outOffset: 8)
    ]

    public var selectedChannelIndex: Int = 0 {
        didSet {
            selectedChannelIndex = max(0, min(channels.count - 1, selectedChannelIndex))
            notifyStateChanged()
        }
    }

    public var activeChannel: ChannelStripState {
        return channels[selectedChannelIndex]
    }

    private var lastSentLedValues: [FlexFxMidiTarget: UInt8] = [:]

    // Master Module Power Switch
    public var isModuleEnabled: Bool {
        get { return activeChannel.isModuleEnabled }
        set {
            activeChannel.isModuleEnabled = newValue
            rane_vst_set_tempo(bpm, sampleRate, isModuleEnabled, true)
            if isModuleEnabled {
                updateHardwareLeds()
                startAudioEngine()
                rescheduleHardwareBeatSyncTimer()
                RaneMidiService.shared.sendHardwareBpmSync(bpm: bpm, beatPulse: isLinkEnabled)
                RaneMidiService.shared.sendOledAbletonLinkStatus(enabled: isLinkEnabled)
            } else {
                clearAllHardwareLeds()
                rescheduleHardwareBeatSyncTimer()
                RaneMidiService.shared.sendMute()
                RaneMidiService.shared.sendOledAbletonLinkStatus(enabled: isLinkEnabled)
            }
            notifyStateChanged()
        }
    }

    // Engine Parameters
    public var currentEffect: FlexFxType = .echo {
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var currentDivision: BeatDivision = .d1_2 {
        didSet { notifyStateChanged() }
    }
    public var bpm: Double = 124.0 {
        didSet {
            rane_vst_set_tempo(bpm, sampleRate, isModuleEnabled, true)
            notifyStateChanged()
            if isLinkEnabled || isModuleEnabled {
                RaneMidiService.shared.sendHardwareBpmSync(bpm: bpm, beatPulse: isLinkEnabled)
                if abs(bpm - lastSyncedTimerBpm) >= 0.05 {
                    rescheduleHardwareBeatSyncTimer()
                }
            }
        }
    }
    public var isEnabled: Bool = true {
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var isLinkEnabled: Bool = true {
        didSet {
            rane_link_enable(isLinkEnabled)
            if isLinkEnabled {
                linkPeers = Int(rane_link_get_num_peers())
                let liveTempo = rane_link_get_tempo()
                if liveTempo >= 40.0 && liveTempo <= 250.0 {
                    bpm = round(liveTempo * 10.0) / 10.0
                }
                rescheduleHardwareBeatSyncTimer()
                RaneMidiService.shared.sendHardwareBpmSync(bpm: bpm, beatPulse: true)
                RaneMidiService.shared.sendOledAbletonLinkStatus(enabled: true)
            } else {
                linkPeers = 0
                rescheduleHardwareBeatSyncTimer()
                RaneMidiService.shared.sendHardwareBpmSync(bpm: bpm, beatPulse: false)
                RaneMidiService.shared.sendOledAbletonLinkStatus(enabled: false)
            }
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var linkPeers: Int = 0 {
        didSet { notifyStateChanged() }
    }
    public var dryWet: Double = 0.5 {
        didSet { notifyStateChanged() }
    }
    public var depth: Double = 0.65 {
        didSet { notifyStateChanged() }
    }
    public var isPreFader: Bool = false {
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }

    // Input / Output Selectors
    public var inputSource: FlexFxInputSource = .flexFxSend {
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var outputDestination: FlexFxOutputDestination = .flexFxReturn {
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }

    public func cycleInputSource(forward: Bool = true) {
        let ordered = FlexFxInputSource.orderedByChannel
        let currentIdx = ordered.firstIndex(of: inputSource) ?? 0
        if forward {
            inputSource = ordered[(currentIdx + 1) % ordered.count]
        } else {
            inputSource = ordered[(currentIdx - 1 + ordered.count) % ordered.count]
        }
    }

    public func cycleOutputDestination(forward: Bool = true) {
        let ordered = FlexFxOutputDestination.orderedByChannel
        let currentIdx = ordered.firstIndex(of: outputDestination) ?? 0
        if forward {
            outputDestination = ordered[(currentIdx + 1) % ordered.count]
        } else {
            outputDestination = ordered[(currentIdx - 1 + ordered.count) % ordered.count]
        }
    }

    // Active Channel Strip Gain & Bypass Proxies
    public var fx1PreGain: Double {
        get { return activeChannel.fx1PreGain }
        set {
            activeChannel.fx1PreGain = newValue
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var fx1DryDuckRatio: Double {
        get { return activeChannel.fx1DryDuckRatio }
        set {
            activeChannel.fx1DryDuckRatio = newValue
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var isFx1Enabled: Bool {
        get { return activeChannel.isFx1Enabled }
        set {
            activeChannel.isFx1Enabled = newValue
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var fx1PostGain: Double {
        get { return activeChannel.fx1PostGain }
        set {
            activeChannel.fx1PostGain = newValue
            notifyStateChanged()
        }
    }

    public var fx2PreGain: Double {
        get { return activeChannel.fx2PreGain }
        set {
            activeChannel.fx2PreGain = newValue
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var fx2DryDuckRatio: Double {
        get { return activeChannel.fx2DryDuckRatio }
        set {
            activeChannel.fx2DryDuckRatio = newValue
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var isFx2Enabled: Bool {
        get { return activeChannel.isFx2Enabled }
        set {
            activeChannel.isFx2Enabled = newValue
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var fx2PostGain: Double {
        get { return activeChannel.fx2PostGain }
        set {
            activeChannel.fx2PostGain = newValue
            notifyStateChanged()
        }
    }

    private var isUpdatingLinkedDry: Bool = false
    public var dryBasePreGain: Double {
        get { return activeChannel.dryBasePreGain }
        set {
            activeChannel.dryBasePreGain = newValue
        }
    }
    public var dryPreGain: Double {
        get { return activeChannel.dryPreGain }
        set {
            activeChannel.dryPreGain = newValue
            if !isUpdatingLinkedDry {
                activeChannel.dryBasePreGain = activeChannel.dryPreGain
            }
            notifyStateChanged()
        }
    }
    public var dryPostGain: Double {
        get { return activeChannel.dryPostGain }
        set {
            activeChannel.dryPostGain = newValue
            notifyStateChanged()
        }
    }

    public func recalculateLinkedDryPreGain(channelIndex: Int? = nil) {
        let idx = channelIndex ?? selectedChannelIndex
        guard idx >= 0 && idx < channels.count else { return }
        let ch = channels[idx]
        guard !ch.isInternalDryUpdate else { return }
        let ratio1 = min(1.0, max(0.0, ch.fx1DryDuckRatio))

        let send1 = (ch.isFx1Enabled && ch.isModuleEnabled) ? min(1.0, max(0.0, ch.fx1PreGain)) : 0.0
        let totalDuck = min(1.0, max(0.0, send1 * ratio1))

        let targetDry = max(0.0, ch.dryBasePreGain * (1.0 - totalDuck))
        ch.isInternalDryUpdate = true
        ch.dryPreGain = targetDry
        ch.isInternalDryUpdate = false
    }

    public var inputGain: Double = 1.0 {
        didSet { notifyStateChanged() }
    }

    // Callbacks for UI updates
    public var onStateChanged: (() -> Void)?
    public var onBeatPulse: ((Int) -> Void)?
    public var onAudioStreamingChanged: ((Bool) -> Void)?

    // Peak Meter Proxies for Selected Channel
    public var liveSendPeak: Float { return activeChannel.liveInPeak }
    public var liveReturnPeak: Float { return activeChannel.liveOutPeak }
    public var liveFx1Peak: Float { return activeChannel.liveFx1Peak }
    public var liveFx2Peak: Float { return activeChannel.liveFx2Peak }
    public var liveDryPeak: Float { return activeChannel.liveDryPeak }

    // CoreAudio Real-Time Streaming State
    public private(set) var audioDeviceID: AudioDeviceID = AudioDeviceID(kAudioDeviceUnknown)
    private var ioProcID: AudioDeviceIOProcID? = nil
    public private(set) var isAudioStreaming: Bool = false

    // Shared Memory Audio Exchange with RaneHALPlugin
    private var sharedAudioFd: Int32 = -1
    private var sharedAudio: UnsafeMutablePointer<RaneAudioExchange>? = nil

    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    // Scratch buffers for real-time safe audio rendering
    private let maxFramesPerBlock: Int = 8192
    private let scratchInL: UnsafeMutablePointer<Float>
    private let scratchInR: UnsafeMutablePointer<Float>
    private let scratchOutL: UnsafeMutablePointer<Float>
    private let scratchOutR: UnsafeMutablePointer<Float>

    private let path1InL: UnsafeMutablePointer<Float>
    private let path1InR: UnsafeMutablePointer<Float>
    private let path1OutL: UnsafeMutablePointer<Float>
    private let path1OutR: UnsafeMutablePointer<Float>
    private let path2InL: UnsafeMutablePointer<Float>
    private let path2InR: UnsafeMutablePointer<Float>
    private let path2OutL: UnsafeMutablePointer<Float>
    private let path2OutR: UnsafeMutablePointer<Float>

    private var sampleRate: Double = 48000.0

    // Hardware OLED & Link Sync Timer
    private var linkPollTimer: DispatchSourceTimer?
    private var hwBeatSyncTimer: DispatchSourceTimer?
    private var lastSyncedTimerBpm: Double = 0.0
    private var currentBeatIndex: Int = 0
    private var lastTapTime: TimeInterval = 0
    private var tapTimes: [TimeInterval] = []

    public var fxParams = FxParameters()

    private init() {
        scratchInL = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        scratchInR = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        scratchOutL = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        scratchOutR = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        scratchInL.initialize(repeating: 0.0, count: maxFramesPerBlock)
        scratchInR.initialize(repeating: 0.0, count: maxFramesPerBlock)
        scratchOutL.initialize(repeating: 0.0, count: maxFramesPerBlock)
        scratchOutR.initialize(repeating: 0.0, count: maxFramesPerBlock)

        path1InL  = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        path1InR  = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        path1OutL = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        path1OutR = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        path2InL  = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        path2InR  = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        path2OutL = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)
        path2OutR = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerBlock)

        path1InL.initialize(repeating: 0.0, count: maxFramesPerBlock)
        path1InR.initialize(repeating: 0.0, count: maxFramesPerBlock)
        path1OutL.initialize(repeating: 0.0, count: maxFramesPerBlock)
        path1OutR.initialize(repeating: 0.0, count: maxFramesPerBlock)
        path2InL.initialize(repeating: 0.0, count: maxFramesPerBlock)
        path2InR.initialize(repeating: 0.0, count: maxFramesPerBlock)
        path2OutL.initialize(repeating: 0.0, count: maxFramesPerBlock)
        path2OutR.initialize(repeating: 0.0, count: maxFramesPerBlock)

        for ch in channels {
            ch.onGainChanged = { [weak self, weak ch] in
                guard let self = self, let ch = ch else { return }
                self.recalculateLinkedDryPreGain(channelIndex: ch.channelIndex)
                self.notifyStateChanged()
            }
            ch.onParamChanged = { [weak self, weak ch] in
                guard let self = self, let ch = ch else { return }
                self.recalculateLinkedDryPreGain(channelIndex: ch.channelIndex)
                self.notifyStateChanged()
                self.updateHardwareLeds()
            }
            recalculateLinkedDryPreGain(channelIndex: ch.channelIndex)
        }

        // Ableton Link: session must be created before enable/get_tempo have any effect
        _ = rane_link_init(bpm)
        rane_link_set_callbacks({ peers in
            DispatchQueue.main.async {
                RaneFlexFxService.shared.linkPeers = Int(peers)
            }
        }, { liveTempo in
            DispatchQueue.main.async {
                RaneFlexFxService.shared.updateBpmFromLink(liveTempo)
            }
        })
        rane_link_enable(isLinkEnabled)
        if isLinkEnabled {
            let t = rane_link_get_tempo()
            if t >= 40.0 && t <= 250.0 { bpm = round(t * 10.0) / 10.0 }
            linkPeers = Int(rane_link_get_num_peers())
        }
        setupLinkPolling()
        startAudioEngine()
        registerDeviceListener()
        rescheduleHardwareBeatSyncTimer()
    }

    deinit {
        stopAudioEngine()
        closeSharedAudioExchange()
        linkPollTimer?.cancel()
        hwBeatSyncTimer?.cancel()
        scratchInL.deallocate()
        scratchInR.deallocate()
        scratchOutL.deallocate()
        scratchOutR.deallocate()
        path1InL.deallocate()
        path1InR.deallocate()
        path1OutL.deallocate()
        path1OutR.deallocate()
        path2InL.deallocate()
        path2InR.deallocate()
        path2OutL.deallocate()
        path2OutR.deallocate()
    }

    private func rescheduleHardwareBeatSyncTimer() {
        hwBeatSyncTimer?.cancel()
        hwBeatSyncTimer = nil

        guard isLinkEnabled || isModuleEnabled else { return }
        let activeBpm = max(41.0, min(300.0, bpm))
        lastSyncedTimerBpm = activeBpm

        if isLinkEnabled {
            let microsToNext = rane_link_micros_to_next_beat(4.0)
            let initialDelayMs = max(5, Int(microsToNext / 1000))
            let beatIntervalMs = max(100, Int(round((60.0 / activeBpm) * 1000.0)))

            let bTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            bTimer.schedule(deadline: .now() + .milliseconds(initialDelayMs), repeating: .milliseconds(beatIntervalMs))
            bTimer.setEventHandler { [weak self] in
                guard let self = self else { return }
                guard self.isLinkEnabled else { return }
                let currentBeat = rane_link_get_beat(4.0)
                let beatIndex = ((Int(floor(currentBeat.truncatingRemainder(dividingBy: 4.0)))) + 4) % 4
                self.currentBeatIndex = beatIndex
                self.onBeatPulse?(beatIndex)
                RaneMidiService.shared.sendHardwareBpmSync(bpm: self.bpm, beatPulse: beatIndex == 0)
            }
            bTimer.resume()
            hwBeatSyncTimer = bTimer
        } else {
            let beatIntervalMs = max(100, Int(round((60.0 / activeBpm) * 1000.0)))
            let bTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            bTimer.schedule(deadline: .now() + .milliseconds(beatIntervalMs), repeating: .milliseconds(beatIntervalMs))
            bTimer.setEventHandler { [weak self] in
                guard let self = self else { return }
                if self.isModuleEnabled {
                    self.currentBeatIndex = (self.currentBeatIndex + 1) % 4
                    self.onBeatPulse?(self.currentBeatIndex)
                }
            }
            bTimer.resume()
            hwBeatSyncTimer = bTimer
        }
    }

    // MARK: - Shared Audio Exchange Lifecycle
    private func openSharedAudioExchange() {
        if sharedAudio != nil { return }
        let path = RANE_AUDIO_EXCHANGE_PATH
        let fd = open(path, O_RDWR | O_CREAT, 0o666)
        if fd < 0 { return }
        fchmod(fd, 0o666)
        let size = MemoryLayout<RaneAudioExchange>.stride
        if ftruncate(fd, off_t(size)) != 0 {
            // size established
        }
        let ptr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        if ptr == MAP_FAILED {
            close(fd)
            return
        }
        sharedAudioFd = fd
        sharedAudio = ptr?.assumingMemoryBound(to: RaneAudioExchange.self)
        if let ex = sharedAudio {
            if ex.pointee.magic != UInt32(RANE_AUDIO_EXCHANGE_MAGIC) {
                memset(ptr, 0, size)
                ex.pointee.magic = UInt32(RANE_AUDIO_EXCHANGE_MAGIC)
                ex.pointee.version = 1
                ex.pointee.sampleRate = 48000
                ex.pointee.bufferFrameSize = 512
            }
            ex.pointee.vstActive = 1
        }
    }

    private func closeSharedAudioExchange() {
        if let ex = sharedAudio {
            ex.pointee.vstActive = 0
            munmap(ex, MemoryLayout<RaneAudioExchange>.stride)
            sharedAudio = nil
        }
        if sharedAudioFd >= 0 {
            close(sharedAudioFd)
            sharedAudioFd = -1
        }
    }

    // MARK: - CoreAudio Engine
    func startAudioEngine() {
        guard !isAudioStreaming else { return }
        openSharedAudioExchange()
        sharedAudio?.pointee.vstActive = 1

        guard let devId = findRaneAudioDevice() else { return }

        self.audioDeviceID = devId

        var sRate: Float64 = 48000.0
        var propSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(devId, &rateAddr, 0, nil, &propSize, &sRate) == noErr {
            self.sampleRate = sRate
        }

        rane_vst_set_tempo(bpm, self.sampleRate, isModuleEnabled, true)

        let ioProc: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData) -> OSStatus in
            guard let clientData = clientData else { return noErr }
            let service = Unmanaged<RaneFlexFxService>.fromOpaque(clientData).takeUnretainedValue()
            service.handleAudioIO(inInputData: inInputData, outOutputData: outOutputData)
            return noErr
        }

        var proc: AudioDeviceIOProcID? = nil
        let clientPtr = Unmanaged.passUnretained(self).toOpaque()
        let err = AudioDeviceCreateIOProcID(devId, ioProc, clientPtr, &proc)
        guard err == noErr, let validProc = proc else { return }

        self.ioProcID = validProc
        let startErr = AudioDeviceStart(devId, validProc)
        if startErr == noErr {
            self.isAudioStreaming = true
            DispatchQueue.main.async { [weak self] in
                self?.onAudioStreamingChanged?(true)
                self?.notifyStateChanged()
            }
        }
    }

    func stopAudioEngine() {
        sharedAudio?.pointee.vstActive = 0
        guard isAudioStreaming, let proc = ioProcID else { return }
        _ = AudioDeviceStop(audioDeviceID, proc)
        AudioDeviceDestroyIOProcID(audioDeviceID, proc)
        self.ioProcID = nil
        self.isAudioStreaming = false
        DispatchQueue.main.async { [weak self] in
            self?.onAudioStreamingChanged?(false)
            self?.notifyStateChanged()
        }
    }

    private func findRaneAudioDevice() -> AudioDeviceID? {
        var propSize: UInt32 = 0
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devAddr, 0, nil, &propSize) == noErr else { return nil }

        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var devIds = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devAddr, 0, nil, &propSize, &devIds) == noErr else { return nil }

        for devId in devIds {
            var devName: Unmanaged<CFString>? = nil
            var nameSize: UInt32 = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(devId, &nameAddr, 0, nil, &nameSize, &devName) == noErr,
               let cfStr = devName?.takeRetainedValue() {
                let nameStr = cfStr as String
                if nameStr.localizedCaseInsensitiveContains("Sixty-Eight") || nameStr.localizedCaseInsensitiveContains("Rane 68") {
                    return devId
                }
            }
        }
        return nil
    }

    private func registerDeviceListener() {
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.checkAndUpdateAudioDevice()
        }
    }

    func checkAndUpdateAudioDevice() {
        if let devId = findRaneAudioDevice() {
            if !isAudioStreaming {
                startAudioEngine()
            } else if devId != audioDeviceID {
                stopAudioEngine()
                startAudioEngine()
            }
        } else if isAudioStreaming {
            stopAudioEngine()
        }
    }

    public var isAnyVstActive: Bool {
        let host = RanePluginHostService.shared
        for ch in channels {
            if ch.isModuleEnabled {
                let slotIdx = ch.slotIndex
                if (ch.isFx1Enabled && slotIdx < host.slots.count && host.slots[slotIdx].isLoaded) ||
                   ch.dryPreGain < 0.99 || ch.dryPreGain > 1.01 ||
                   ch.dryPostGain < 0.99 || ch.dryPostGain > 1.01 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Multi-Channel Real-Time Audio Processing (Channels 1..4 & FlexFX)
    private func handleAudioIO(inInputData: UnsafePointer<AudioBufferList>,
                               outOutputData: UnsafeMutablePointer<AudioBufferList>) {
        let inData = inInputData.pointee
        let outData = outOutputData.pointee

        let inBuf = inData.mBuffers
        let outBuf = outData.mBuffers

        let inChannels = Int(inBuf.mNumberChannels)
        let outChannels = Int(outBuf.mNumberChannels)

        let inFrames = inChannels > 0 ? Int(inBuf.mDataByteSize) / (inChannels * MemoryLayout<Float>.size) : 0
        let outFrames = outChannels > 0 ? Int(outBuf.mDataByteSize) / (outChannels * MemoryLayout<Float>.size) : 0

        // If CoreAudio provided an output buffer, zero it out so CoreAudio's mixer does not add a duplicate stream
        if let outPtr = outBuf.mData?.assumingMemoryBound(to: Float.self), outFrames > 0, outChannels > 0 {
            outPtr.initialize(repeating: 0.0, count: outFrames * outChannels)
        }

        if sharedAudio == nil {
            openSharedAudioExchange()
        }

        guard let ex = sharedAudio else { return }

        // Update heartbeat timestamp immediately on every single callback using cached timebase
        let tb = Self.timebase
        let nowNs = (mach_absolute_time() * UInt64(tb.numer)) / UInt64(tb.denom)
        ex.pointee.timestampNs = nowNs
        ex.pointee.managerCycleCount &+= 1
        ex.pointee.vstActive = 1

        let targetIdx = ex.pointee.driverBufferIdx % UInt32(RANE_AUDIO_EXCHANGE_NUM_BUFFERS)
        guard let dawBuf = rane_exchange_get_daw_buffer(ex, targetIdx),
              let processedBuf = rane_exchange_get_processed_buffer(ex, targetIdx) else {
            return
        }

        let bufSize = Int(ex.pointee.bufferFrameSize)
        let framesToProcess = (bufSize > 0 && bufSize <= Int(RANE_AUDIO_EXCHANGE_MAX_FRAMES)) ? bufSize : (outFrames > 0 ? outFrames : (inFrames > 0 ? inFrames : 512))
        let processFrames = min(maxFramesPerBlock, min(framesToProcess, Int(RANE_AUDIO_EXCHANGE_MAX_FRAMES)))
        guard processFrames > 0 else { return }

        // 1. Pre-copy clean incoming DAW audio to processedBuf so inactive channels never have silence or latency
        memcpy(processedBuf, dawBuf, processFrames * 10 * MemoryLayout<Float>.size)

        let inPtr = inBuf.mData?.assumingMemoryBound(to: Float.self)

        // Process only enabled channel strips; bypassed channels already have clean audio in processedBuf
        for ch in channels {
            let inOff = ch.inOffset
            let outOff = ch.outOffset

            guard ch.isModuleEnabled else {
                ch.liveFx1Peak = 0.0
                ch.liveFx2Peak = 0.0
                continue
            }

            var maxIn: Float = 0.0

            if ch.channelIndex < 4 {
                // Channels 1..4 (PGM 1..4): Direct intercept from DAW output
                for f in 0..<processFrames {
                    let sL = dawBuf[f * 10 + inOff]
                    let sR = dawBuf[f * 10 + inOff + 1]
                    scratchInL[f] = sL
                    scratchInR[f] = sR
                    let m = max(abs(sL), abs(sR))
                    if m > maxIn { maxIn = m }
                }
            } else {
                // Channel 5 (FlexFX Return): Mixer hardware FlexFX send (USB In 9-10) + DAW Playback 9-10
                for f in 0..<processFrames {
                    let hwL = (inPtr != nil && inChannels >= 10 && f < inFrames) ? inPtr![f * inChannels + 8] : 0.0
                    let hwR = (inPtr != nil && inChannels >= 10 && f < inFrames) ? inPtr![f * inChannels + 9] : 0.0
                    let dawL = dawBuf[f * 10 + 8]
                    let dawR = dawBuf[f * 10 + 9]
                    let sL = hwL + dawL
                    let sR = hwR + dawR
                    scratchInL[f] = sL
                    scratchInR[f] = sR
                    let m = max(abs(sL), abs(sR))
                    if m > maxIn { maxIn = m }
                }
            }
            ch.liveInPeak = maxIn

            processChannelStripBlock(channel: ch,
                                     inL: scratchInL, inR: scratchInR,
                                     outL: scratchOutL, outR: scratchOutR,
                                     frames: processFrames)

            // Overwrite active channel strip output in processedBuf
            for f in 0..<processFrames {
                let off = f * 10 + outOff
                processedBuf[off] = scratchOutL[f]
                processedBuf[off + 1] = scratchOutR[f]
            }
        }

        // Mark buffer as processed by manager so HAL driver knows it can output it to hardware
        ex.pointee.managerBufferIdx = targetIdx
    }

    private func processChannelStripBlock(channel: ChannelStripState,
                                          inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                                          outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                                          frames: Int) {
        // If module is disabled on this channel, pass 100% clean dry audio through
        guard channel.isModuleEnabled else {
            for i in 0..<frames {
                outL[i] = inL[i]
                outR[i] = inR[i]
            }
            channel.liveFx1Peak = 0.0
            channel.liveFx2Peak = 0.0
            channel.liveDryPeak = channel.liveInPeak
            channel.liveOutPeak = channel.liveInPeak
            return
        }

        let host = RanePluginHostService.shared
        let slotIdx = channel.slotIndex

        // PATH 1: Dedicated Channel VST Slot (Slot 0..4)
        let pre1 = Float(channel.fx1PreGain)
        let post1 = Float(channel.fx1PostGain)
        var maxP1: Float = 0.0

        if channel.isFx1Enabled && slotIdx < host.slots.count && host.slots[slotIdx].isLoaded {
            for i in 0..<frames {
                path1InL[i] = inL[i] * pre1
                path1InR[i] = inR[i] * pre1
            }
            if host.processSlot(slotIdx, inL: path1InL, inR: path1InR, outL: path1OutL, outR: path1OutR, frames: frames, bpm: bpm, sampleRate: sampleRate) {
                for i in 0..<frames {
                    let l = path1OutL[i] * post1
                    let r = path1OutR[i] * post1
                    path1OutL[i] = l
                    path1OutR[i] = r
                    let m = max(abs(l), abs(r))
                    if m > maxP1 { maxP1 = m }
                }
            } else {
                path1OutL.initialize(repeating: 0.0, count: frames)
                path1OutR.initialize(repeating: 0.0, count: frames)
            }
        } else {
            path1OutL.initialize(repeating: 0.0, count: frames)
            path1OutR.initialize(repeating: 0.0, count: frames)
        }
        channel.liveFx1Peak = maxP1
        channel.liveFx2Peak = 0.0

        // DRY & MASTER SUM
        let dryGain = Float(channel.dryPreGain) * Float(channel.dryPostGain)
        var maxDry: Float = 0.0
        var maxOut: Float = 0.0

        for i in 0..<frames {
            let dL = inL[i] * dryGain
            let dR = inR[i] * dryGain
            let mD = max(abs(dL), abs(dR))
            if mD > maxDry { maxDry = mD }

            var outSampleL = path1OutL[i] + dL
            var outSampleR = path1OutR[i] + dR
            if outSampleL.isNaN || outSampleL.isInfinite { outSampleL = dL }
            if outSampleR.isNaN || outSampleR.isInfinite { outSampleR = dR }
            outL[i] = outSampleL
            outR[i] = outSampleR

            let mO = max(abs(outSampleL), abs(outSampleR))
            if mO > maxOut { maxOut = mO }
        }
        channel.liveDryPeak = maxDry
        channel.liveOutPeak = maxOut
    }

    private func setupLinkPolling() {
        let pTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        pTimer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        pTimer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.isLinkEnabled else { return }
            let peers = Int(rane_link_get_num_peers())
            if peers != self.linkPeers { self.linkPeers = peers }
            let liveTempo = rane_link_get_tempo()
            if liveTempo >= 40.0 && liveTempo <= 250.0 {
                self.updateBpmFromLink(liveTempo)
            }
        }
        pTimer.resume()
        linkPollTimer = pTimer
    }

    func updateBpmFromLink(_ newBpm: Double) {
        guard isLinkEnabled else { return }
        let rounded = round(newBpm * 10.0) / 10.0
        if abs(rounded - bpm) >= 0.1 {
            bpm = rounded
        }
    }

    public func setManualBpm(_ val: Double) {
        let clamped = max(40.0, min(300.0, val))
        bpm = clamped
        // Propagate to the Link session so peers follow and polling doesn't revert it
        if isLinkEnabled { rane_link_set_tempo(clamped) }
    }


    public func tapTempo() {
        let now = Date().timeIntervalSince1970
        if lastTapTime > 0 && (now - lastTapTime) < 2.5 {
            tapTimes.append(now)
            if tapTimes.count > 4 { tapTimes.removeFirst() }
            if tapTimes.count >= 2 {
                var diffs: [Double] = []
                for i in 1..<tapTimes.count {
                    diffs.append(tapTimes[i] - tapTimes[i - 1])
                }
                let avg = diffs.reduce(0, +) / Double(diffs.count)
                if avg > 0.15 {
                    let calcBpm = 60.0 / avg
                    setManualBpm(round(calcBpm * 10.0) / 10.0)
                }
            }
        } else {
            tapTimes = [now]
        }
        lastTapTime = now
    }

    public func cycleBeatDivision(forward: Bool) {
        guard isModuleEnabled else { return }
        let all = BeatDivision.allCases
        guard let currentIdx = all.firstIndex(of: currentDivision) else { return }
        if forward {
            if currentIdx + 1 < all.count { currentDivision = all[currentIdx + 1] }
        } else {
            if currentIdx > 0 { currentDivision = all[currentIdx - 1] }
        }
    }

    public func clearAllHardwareLeds() {
        let midi = RaneMidiService.shared
        let learn = RaneMidiLearnService.shared
        for (_, outMap) in learn.allOutMappings {
            let ch = (outMap.channel == 255) ? 0 : outMap.channel
            if outMap.type == .note {
                midi.sendNoteOff(note: outMap.number, channel: ch)
            } else {
                midi.sendCC(cc: outMap.number, value: outMap.offValue, channel: ch)
            }
        }
        lastSentLedValues.removeAll()
    }

    public func updateHardwareLeds() {
        let midi = RaneMidiService.shared
        let learn = RaneMidiLearnService.shared

        // Process Traktor Controller Manager "Add Out..." LED Feedback for all mapped targets
        for (target, outMap) in learn.allOutMappings {
            // Anti-loop safety: do not echo back to the control that is currently executing an action
            if learn.activeExecutingTarget == target {
                continue
            }

            let ch = (outMap.channel == 255) ? 0 : outMap.channel
            let isOn: Bool

            if let (chIdx, control) = target.channelIndexAndControl {
                if chIdx < channels.count {
                    let strip = channels[chIdx]
                    switch control {
                    case .slot1Toggle:
                        isOn = strip.isFx1Enabled && strip.isModuleEnabled
                    case .slot2Toggle:
                        isOn = strip.isFx2Enabled && strip.isModuleEnabled
                    default:
                        isOn = false
                    }
                } else {
                    isOn = false
                }
            } else {
                switch target {
                case .vst1Toggle:
                    isOn = isFx1Enabled && isModuleEnabled
                case .vst2Toggle:
                    isOn = isFx2Enabled && isModuleEnabled
                case .modulePower:
                    isOn = isModuleEnabled
                case .abletonLink:
                    isOn = isLinkEnabled
                case .prePost:
                    isOn = isPreFader
                case .inputPgm1:
                    isOn = (inputSource == .pgm1)
                case .inputPgm2:
                    isOn = (inputSource == .pgm2)
                case .inputPgm3:
                    isOn = (inputSource == .pgm3)
                case .inputPgm4:
                    isOn = (inputSource == .pgm4)
                case .inputFlexFx:
                    isOn = (inputSource == .flexFxSend)
                case .inputMainMix:
                    isOn = (inputSource == .mainMix)
                case .outputPgm1:
                    isOn = (outputDestination == .pgm1)
                case .outputPgm2:
                    isOn = (outputDestination == .pgm2)
                case .outputPgm3:
                    isOn = (outputDestination == .pgm3)
                case .outputPgm4:
                    isOn = (outputDestination == .pgm4)
                case .outputFlexFx:
                    isOn = (outputDestination == .flexFxReturn)
                default:
                    isOn = false
                }
            }

            let val = isOn ? outMap.onValue : outMap.offValue

            // Deduplicate: only send if the state or velocity has changed
            if let last = lastSentLedValues[target], last == val {
                continue
            }
            lastSentLedValues[target] = val

            if outMap.type == .note {
                if isOn {
                    midi.sendNoteOn(note: outMap.number, velocity: val, channel: ch)
                } else {
                    if val > 0 {
                        midi.sendNoteOn(note: outMap.number, velocity: val, channel: ch)
                    } else {
                        midi.sendNoteOff(note: outMap.number, channel: ch)
                    }
                }
            } else {
                midi.sendCC(cc: outMap.number, value: val, channel: ch)
            }
        }
    }

    private var isStateNotificationPending = false
    private func notifyStateChanged() {
        guard !isStateNotificationPending else { return }
        isStateNotificationPending = true
        DispatchQueue.main.async { [weak self] in
            self?.isStateNotificationPending = false
            self?.onStateChanged?()
        }
    }
}
