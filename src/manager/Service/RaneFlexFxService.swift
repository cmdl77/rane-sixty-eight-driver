/* SPDX-License-Identifier: MIT */
/* RaneFlexFxService.swift - Software FlexFX DSP Engine with DaisySP algorithms, Native Ableton Link & CoreAudio IO Loop */

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
    // FILTER
    public var filterCutoff: Double = 1200.0   // 100 - 10000 Hz
    public var filterResonance: Double = 2.0    // 0.5 - 8.0 Q
    public var filterLfoRate: Double = 0.5      // 0.1 - 6.0 Hz
    public var filterLfoDepth: Double = 0.4     // 0.0 - 1.0

    // FLANGER
    public var flangerRate: Double = 0.4        // 0.05 - 4.0 Hz
    public var flangerDepth: Double = 0.7       // 0.0 - 1.0
    public var flangerFeedback: Double = 0.6    // 0.0 - 0.95
    public var flangerManual: Double = 3.0      // 0.5 - 8.0 ms

    // PHASER
    public var phaserRate: Double = 0.35        // 0.05 - 4.0 Hz
    public var phaserDepth: Double = 0.75       // 0.0 - 1.0
    public var phaserFeedback: Double = 0.5     // 0.0 - 0.9
    public var phaserBaseFreq: Double = 800.0   // 200 - 3000 Hz

    // ECHO
    public var echoHighCut: Double = 5000.0     // 1000 - 18000 Hz
    public var echoPingPong: Double = 0.5       // 0.0 - 1.0
    public var echoSpread: Double = 20.0        // 0 - 40 ms

    // DUB DELAY (Space Echo)
    public var dubSaturation: Double = 0.6      // 0.0 - 1.0 (Tape Saturation)
    public var dubHighCut: Double = 2800.0      // 500 - 8000 Hz (Dark Tape Tone)
    public var dubFlutter: Double = 0.35        // 0.0 - 1.0 (Tape Wow & Flutter)
    public var dubResonance: Double = 0.7       // 0.0 - 1.0 (Self-Oscillation Feedback)

    // REVERB
    public var reverbRoomSize: Double = 0.75    // 0.1 - 1.0
    public var reverbDamping: Double = 0.4      // 0.0 - 1.0
    public var reverbPreDelay: Double = 25.0    // 0 - 100 ms
    public var reverbWidth: Double = 0.85       // 0.0 - 1.0

    public init() {}
}

enum BeatDivision: Int, CaseIterable {
    case d1_8 = 0
    case d1_4 = 1
    case d1_2 = 2
    case d3_4 = 3
    case d1_1 = 4
    case d2_1 = 5
    case d4_1 = 6

    var label: String {
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

    var multiplier: Double {
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

class RaneFlexFxService {
    static let shared = RaneFlexFxService()

    // Master Module Power Switch (Turns entire module ON or OFF)
    var isModuleEnabled: Bool = true {
        didSet {
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
    var currentEffect: FlexFxType = .echo {
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    var currentDivision: BeatDivision = .d1_2 {
        didSet { notifyStateChanged() }
    }
    var bpm: Double = 124.0 {
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
    var isEnabled: Bool = true {
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    var isLinkEnabled: Bool = true {
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
    var linkPeers: Int = 0 {
        didSet { notifyStateChanged() }
    }
    var dryWet: Double = 0.5 { // 0.0 (Dry) ... 1.0 (Wet)
        didSet { notifyStateChanged() }
    }
    var depth: Double = 0.65 { // 0.0 ... 1.0 (Feedback / Filter Cutoff / Reverb Decay)
        didSet { notifyStateChanged() }
    }
    var isPreFader: Bool = false { // false = POST-FADER (Tail/Hallfahne decays naturally), true = PRE-FADER (hard bypass)
        didSet {
            notifyStateChanged()
            updateHardwareLeds()
        }
    }

    // =========================================================================
    // PARALLEL 3-BUS MATRIX (AUDIO SIGNALFLUSS & MIDI STEUERUNG)
    // =========================================================================
    private let inputSourceKey = "RaneSixtyEight_FlexFxInputSource_v1"
    public var inputSource: FlexFxInputSource = .flexFxSend {
        didSet {
            UserDefaults.standard.set(inputSource.rawValue, forKey: inputSourceKey)
            notifyStateChanged()
            updateHardwareLeds()
        }
    }

    private let outputDestKey = "RaneSixtyEight_FlexFxOutputDest_v1"
    public var outputDestination: FlexFxOutputDestination = .flexFxReturn {
        didSet {
            UserDefaults.standard.set(outputDestination.rawValue, forKey: outputDestKey)
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

    // Path 1: VST Effekt 1 (Pre-Gain -> VST 1 [ON/OFF] -> Post-Gain)
    private let fx1PreGainKey      = "RaneSixtyEight_Fx1PreGain_v1"
    private let fx1PostGainKey     = "RaneSixtyEight_Fx1PostGain_v1"
    private let fx1EnabledKey      = "RaneSixtyEight_Fx1Enabled_v1"
    private let fx1DryDuckRatioKey = "RaneSixtyEight_Fx1DryDuckRatio_v1"

    public var fx1PreGain: Double = 0.0 { // 0.0 (-inf dB closed) ... 1.0 (0 dB) ... 1.5 (+3.5 dB)
        didSet {
            UserDefaults.standard.set(fx1PreGain, forKey: fx1PreGainKey)
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var fx1DryDuckRatio: Double = 0.5 { // 0.0 (0% no ducking) ... 1.0 (100% full dry cut at 0dB pre-gain)
        didSet {
            UserDefaults.standard.set(fx1DryDuckRatio, forKey: fx1DryDuckRatioKey)
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var isFx1Enabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isFx1Enabled, forKey: fx1EnabledKey)
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var fx1PostGain: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(fx1PostGain, forKey: fx1PostGainKey)
            notifyStateChanged()
        }
    }

    // Path 2: VST Effekt 2 (Pre-Gain -> VST 2 [ON/OFF] -> Post-Gain)
    private let fx2PreGainKey      = "RaneSixtyEight_Fx2PreGain_v1"
    private let fx2PostGainKey     = "RaneSixtyEight_Fx2PostGain_v1"
    private let fx2EnabledKey      = "RaneSixtyEight_Fx2Enabled_v1"
    private let fx2DryDuckRatioKey = "RaneSixtyEight_Fx2DryDuckRatio_v1"

    public var fx2PreGain: Double = 0.0 {
        didSet {
            UserDefaults.standard.set(fx2PreGain, forKey: fx2PreGainKey)
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var fx2DryDuckRatio: Double = 0.5 { // 0.0 (0% no ducking) ... 1.0 (100% full dry cut at 0dB pre-gain)
        didSet {
            UserDefaults.standard.set(fx2DryDuckRatio, forKey: fx2DryDuckRatioKey)
            recalculateLinkedDryPreGain()
            notifyStateChanged()
        }
    }
    public var isFx2Enabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isFx2Enabled, forKey: fx2EnabledKey)
            notifyStateChanged()
            updateHardwareLeds()
        }
    }
    public var fx2PostGain: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(fx2PostGain, forKey: fx2PostGainKey)
            notifyStateChanged()
        }
    }

    // Path 3: Dry / Direct Bypass Bus (Pre-Gain -> Direct -> Post-Gain)
    private let dryPreGainKey     = "RaneSixtyEight_DryPreGain_v1"
    private let dryBasePreGainKey = "RaneSixtyEight_DryBasePreGain_v1"
    private let dryPostGainKey    = "RaneSixtyEight_DryPostGain_v1"
    private var isUpdatingLinkedDry: Bool = false

    // Ausgangsstellung (Base level) to which Dry Pre-Gain returns when VST 1 & VST 2 Pre-Gain are turned down
    public var dryBasePreGain: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(dryBasePreGain, forKey: dryBasePreGainKey)
        }
    }

    public var dryPreGain: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(dryPreGain, forKey: dryPreGainKey)
            if !isUpdatingLinkedDry {
                dryBasePreGain = dryPreGain
            }
            notifyStateChanged()
        }
    }
    public var dryPostGain: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(dryPostGain, forKey: dryPostGainKey)
            notifyStateChanged()
        }
    }

    /// Proportionally reduces Dry Pre-Gain when VST 1 Pre-Gain or VST 2 Pre-Gain is turned up,
    /// and restores Dry Pre-Gain to its Ausgangsstellung (`dryBasePreGain`) when turned back down.
    public func recalculateLinkedDryPreGain() {
        let ratio1 = min(1.0, max(0.0, fx1DryDuckRatio))
        let ratio2 = min(1.0, max(0.0, fx2DryDuckRatio))
        guard ratio1 > 0.0001 || ratio2 > 0.0001 else { return }

        // Normalized send amount (0.0 = -inf dB closed, 1.0 = 0.0 dB unity)
        let send1 = min(1.0, max(0.0, fx1PreGain))
        let send2 = min(1.0, max(0.0, fx2PreGain))

        let duck1 = send1 * ratio1
        let duck2 = send2 * ratio2
        let totalDuck = min(1.0, max(0.0, duck1 + duck2))

        let targetDry = max(0.0, dryBasePreGain * (1.0 - totalDuck))
        isUpdatingLinkedDry = true
        self.dryPreGain = targetDry
        isUpdatingLinkedDry = false
    }

    // Legacy compatibility alias
    private let inputGainKey = "RaneSixtyEight_FlexFxInputGain_v1"
    public var inputGain: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(inputGain, forKey: inputGainKey)
            notifyStateChanged()
        }
    }

    // Callbacks for UI updates
    var onStateChanged: (() -> Void)?
    var onBeatPulse: ((Int) -> Void)? // Beat 0, 1, 2, 3
    var onAudioStreamingChanged: ((Bool) -> Void)?

    // Driver Shared State for hardware-level DSP loopback
    private let stateFilePath = "/var/tmp/rane_flexfx_state.bin"
    private var stateFileDescriptor: Int32 = -1
    private var sharedStateMemory: UnsafeMutableRawPointer?

    func syncDriverDspState() {
        if sharedStateMemory == nil {
            stateFileDescriptor = open(stateFilePath, O_RDWR | O_CREAT, 0o666)
            if stateFileDescriptor >= 0 {
                fchmod(stateFileDescriptor, 0o666)
                ftruncate(stateFileDescriptor, 64)
                let ptr = mmap(nil, 64, PROT_READ | PROT_WRITE, MAP_SHARED, stateFileDescriptor, 0)
                if ptr != MAP_FAILED {
                    sharedStateMemory = ptr
                }
            }
        }
        guard let ptr = sharedStateMemory else { return }
        ptr.storeBytes(of: UInt32(0x464C4558), toByteOffset: 0, as: UInt32.self) // 'FLEX'
        ptr.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)          // version 1
        ptr.storeBytes(of: UInt32((isModuleEnabled && isEnabled) ? 1 : 0), toByteOffset: 8, as: UInt32.self)
        ptr.storeBytes(of: UInt32(currentEffect.rawValue), toByteOffset: 12, as: UInt32.self)
        ptr.storeBytes(of: Float(dryWet), toByteOffset: 16, as: Float.self)
        ptr.storeBytes(of: Float(depth), toByteOffset: 20, as: Float.self)
        ptr.storeBytes(of: Float(bpm), toByteOffset: 24, as: Float.self)
        ptr.storeBytes(of: Float(currentDivision.multiplier), toByteOffset: 28, as: Float.self)
        ptr.storeBytes(of: Float(sampleRate), toByteOffset: 32, as: Float.self)
    }

    // Link Polling & Hardware OLED Beat-Sync Timer
    private var linkPollTimer: DispatchSourceTimer?
    private var hwBeatSyncTimer: DispatchSourceTimer?
    private var lastSyncedTimerBpm: Double = 0.0
    private var currentBeatIndex: Int = 0
    private var lastTapTime: TimeInterval = 0
    private var tapTimes: [TimeInterval] = []

    /// Schedules a high-precision beat clock that flashes the Serato asterisk (*) and updates BPM on the Sixty-Eight OLED display
    private func rescheduleHardwareBeatSyncTimer() {
        hwBeatSyncTimer?.cancel()
        hwBeatSyncTimer = nil

        guard isLinkEnabled || isModuleEnabled else { return }
        let activeBpm = max(41.0, min(300.0, bpm))
        lastSyncedTimerBpm = activeBpm
        let beatIntervalMs = max(200, Int(round((60.0 / activeBpm) * 1000.0)))

        let bTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        bTimer.schedule(deadline: .now() + .milliseconds(beatIntervalMs), repeating: .milliseconds(beatIntervalMs))
        bTimer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.isModuleEnabled {
                self.currentBeatIndex = (self.currentBeatIndex + 1) % 4
                self.onBeatPulse?(self.currentBeatIndex)
            }
            if self.isLinkEnabled {
                RaneMidiService.shared.sendHardwareBpmSync(bpm: self.bpm, beatPulse: true)
            }
        }
        bTimer.resume()
        hwBeatSyncTimer = bTimer
    }

    // MARK: - CoreAudio Real-Time Streaming State
    private(set) var audioDeviceID: AudioDeviceID = AudioDeviceID(kAudioDeviceUnknown)
    private var ioProcID: AudioDeviceIOProcID? = nil
    private(set) var isAudioStreaming: Bool = false
    private(set) var liveSendPeak: Float = 0.0
    private(set) var liveReturnPeak: Float = 0.0

    // Pre-allocated scratch buffers for RT-safe CoreAudio IO (no malloc in audio thread)
    private let maxFramesPerBlock: Int = 8192
    private let scratchInL: UnsafeMutablePointer<Float>
    private let scratchInR: UnsafeMutablePointer<Float>
    private let scratchOutL: UnsafeMutablePointer<Float>
    private let scratchOutR: UnsafeMutablePointer<Float>

    // Parallel Path 1 (VST 1) & Path 2 (VST 2) RT buffers
    private let path1InL: UnsafeMutablePointer<Float>
    private let path1InR: UnsafeMutablePointer<Float>
    private let path1OutL: UnsafeMutablePointer<Float>
    private let path1OutR: UnsafeMutablePointer<Float>
    private let path2InL: UnsafeMutablePointer<Float>
    private let path2InR: UnsafeMutablePointer<Float>
    private let path2OutL: UnsafeMutablePointer<Float>
    private let path2OutR: UnsafeMutablePointer<Float>

    // Live per-path peak meters (0.0 .. 1.0)
    public private(set) var liveFx1Peak: Float = 0.0
    public private(set) var liveFx2Peak: Float = 0.0
    public private(set) var liveDryPeak: Float = 0.0

    // DSP Buffers (DaisySP DelayLine & Reverb internal state)
    private var sampleRate: Double = 48000.0
    private let maxDelaySamples: Int = 48000 * 8 // Up to 8 seconds at 48kHz
    private let delayBufferL: UnsafeMutablePointer<Float>
    private let delayBufferR: UnsafeMutablePointer<Float>
    private var delayHead: Int = 0

    // Reverb Comb & Allpass States (Freeverb / DaisySP ReverbSc)
    private var reverbCombL: [[Float]] = []
    private var reverbCombR: [[Float]] = []
    private var reverbCombPos: [Int] = []
    private var reverbAllpassL: [[Float]] = []
    private var reverbAllpassR: [[Float]] = []
    private var reverbAllpassPos: [Int] = []

    // Filter state (State-Variable Filter)
    private var svfLowL: Float = 0
    private var svfBandL: Float = 0
    private var svfLowR: Float = 0
    private var svfBandR: Float = 0

    // Flanger & Phaser LFO Phases & Filters
    private var lfoPhase: Double = 0.0
    private var filterLfoPhase: Double = 0.0
    private var phaserLfoPhase: Double = 0.0
    private var phaserAllpassL: [Float] = [0.0, 0.0, 0.0, 0.0]
    private var phaserAllpassR: [Float] = [0.0, 0.0, 0.0, 0.0]

    // Echo & Dub Delay Filter & Tape Wow/Flutter States
    private var echoFilterL: Float = 0.0
    private var echoFilterR: Float = 0.0
    private var dubFilterL: Float = 0.0
    private var dubFilterR: Float = 0.0
    private var dubFlutterPhase: Double = 0.0

    // FX Modulation Parameters
    private let fxParamsKey = "RaneSixtyEight_FxParameters_v1"
    public var fxParams = FxParameters() {
        didSet {
            saveFxParams()
        }
    }

    private func loadFxParams() {
        guard let data = UserDefaults.standard.data(forKey: fxParamsKey),
              let loaded = try? JSONDecoder().decode(FxParameters.self, from: data) else {
            return
        }
        self.fxParams = loaded
    }

    private func saveFxParams() {
        if let data = try? JSONEncoder().encode(fxParams) {
            UserDefaults.standard.set(data, forKey: fxParamsKey)
        }
    }

    init() {
        // Allocate RT audio scratch buffers
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

        // Allocate Delay Line buffers
        delayBufferL = UnsafeMutablePointer<Float>.allocate(capacity: maxDelaySamples)
        delayBufferR = UnsafeMutablePointer<Float>.allocate(capacity: maxDelaySamples)
        delayBufferL.initialize(repeating: 0.0, count: maxDelaySamples)
        delayBufferR.initialize(repeating: 0.0, count: maxDelaySamples)

        initDspBuffers()
        loadFxParams()

        if let savedSource = UserDefaults.standard.object(forKey: inputSourceKey) as? Int,
           let src = FlexFxInputSource(rawValue: savedSource) {
            self.inputSource = src
        }
        if let savedDest = UserDefaults.standard.object(forKey: outputDestKey) as? Int,
           let dst = FlexFxOutputDestination(rawValue: savedDest) {
            self.outputDestination = dst
        }

        if UserDefaults.standard.object(forKey: dryBasePreGainKey) != nil {
            self.dryBasePreGain = max(0.0, min(2.0, UserDefaults.standard.double(forKey: dryBasePreGainKey)))
        } else {
            self.dryBasePreGain = 1.0
        }
        if UserDefaults.standard.object(forKey: fx1DryDuckRatioKey) != nil {
            self.fx1DryDuckRatio = max(0.0, min(1.0, UserDefaults.standard.double(forKey: fx1DryDuckRatioKey)))
        }
        if UserDefaults.standard.object(forKey: fx2DryDuckRatioKey) != nil {
            self.fx2DryDuckRatio = max(0.0, min(1.0, UserDefaults.standard.double(forKey: fx2DryDuckRatioKey)))
        }

        if UserDefaults.standard.object(forKey: fx1PreGainKey) != nil {
            self.fx1PreGain = max(0.0, min(2.0, UserDefaults.standard.double(forKey: fx1PreGainKey)))
        }
        if UserDefaults.standard.object(forKey: fx1PostGainKey) != nil {
            self.fx1PostGain = max(0.0, min(2.0, UserDefaults.standard.double(forKey: fx1PostGainKey)))
        }
        if UserDefaults.standard.object(forKey: fx1EnabledKey) != nil {
            self.isFx1Enabled = UserDefaults.standard.bool(forKey: fx1EnabledKey)
        }

        if UserDefaults.standard.object(forKey: fx2PreGainKey) != nil {
            self.fx2PreGain = max(0.0, min(2.0, UserDefaults.standard.double(forKey: fx2PreGainKey)))
        }
        if UserDefaults.standard.object(forKey: fx2PostGainKey) != nil {
            self.fx2PostGain = max(0.0, min(2.0, UserDefaults.standard.double(forKey: fx2PostGainKey)))
        }
        if UserDefaults.standard.object(forKey: fx2EnabledKey) != nil {
            self.isFx2Enabled = UserDefaults.standard.bool(forKey: fx2EnabledKey)
        }

        if UserDefaults.standard.object(forKey: dryPostGainKey) != nil {
            self.dryPostGain = max(0.0, min(2.0, UserDefaults.standard.double(forKey: dryPostGainKey)))
        }

        recalculateLinkedDryPreGain()

        rane_vst_set_tempo(bpm, sampleRate, isModuleEnabled, true)
        setupNativeAbletonLink()
        rescheduleHardwareBeatSyncTimer()
        startAudioEngine()
        registerDeviceListener()
    }

    deinit {
        hwBeatSyncTimer?.cancel()
        stopAudioEngine()
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
        delayBufferL.deallocate()
        delayBufferR.deallocate()
    }

    // MARK: - Native CoreAudio Device Discovery & IO Loop
    func findRaneAudioDevice() -> AudioDeviceID? {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)

        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &devices)
        guard err == noErr else { return nil }

        for dev in devices {
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: CFString? = nil
            var nameSize = UInt32(MemoryLayout<CFString?>.size)

            let nErr = withUnsafeMutablePointer(to: &nameRef) { ptr in
                AudioObjectGetPropertyData(dev, &nameAddr, 0, nil, &nameSize, ptr)
            }
            if nErr == noErr, let name = nameRef as String? {
                if name.contains("Sixty-Eight") || name.contains("Rane") {
                    return dev
                }
            }
        }
        return nil
    }

    func startAudioEngine() {
        guard !isAudioStreaming else { return }

        guard let devId = findRaneAudioDevice() else {
            print("[RaneFlexFxService] Rane Sixty-Eight CoreAudio-Gerät noch nicht verfügbar.")
            return
        }

        self.audioDeviceID = devId

        // Query nominal sample rate
        var srAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sr: Float64 = 48000.0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        if AudioObjectGetPropertyData(devId, &srAddr, 0, nil, &srSize, &sr) == noErr && sr > 8000.0 {
            self.sampleRate = sr
            rane_vst_set_tempo(bpm, sampleRate, isModuleEnabled, true)
        }

        // Register CoreAudio IO Callback
        let ioProc: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData) -> OSStatus in
            guard let clientData = clientData else { return noErr }
            let service = Unmanaged<RaneFlexFxService>.fromOpaque(clientData).takeUnretainedValue()
            service.handleAudioIO(inInputData: inInputData, outOutputData: outOutputData)
            return noErr
        }

        var proc: AudioDeviceIOProcID? = nil
        let clientPtr = Unmanaged.passUnretained(self).toOpaque()
        let err = AudioDeviceCreateIOProcID(devId, ioProc, clientPtr, &proc)
        guard err == noErr, let validProc = proc else {
            print("[RaneFlexFxService] Fehler beim Erstellen des AudioDeviceIOProc: \(err)")
            return
        }

        self.ioProcID = validProc
        let startErr = AudioDeviceStart(devId, validProc)
        if startErr == noErr {
            self.isAudioStreaming = true
            print("[RaneFlexFxService] CoreAudio FlexFX Audio Loop erfolgreich gestartet (Device ID: \(devId), \(Int(self.sampleRate)) Hz)!")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onAudioStreamingChanged?(true)
                self.notifyStateChanged()
            }
        } else {
            print("[RaneFlexFxService] AudioDeviceStart Fehler: \(startErr)")
            AudioDeviceDestroyIOProcID(devId, validProc)
            self.ioProcID = nil
        }
    }

    func stopAudioEngine() {
        guard isAudioStreaming, let proc = ioProcID else { return }
        _ = AudioDeviceStop(audioDeviceID, proc)
        AudioDeviceDestroyIOProcID(audioDeviceID, proc)
        self.ioProcID = nil
        self.isAudioStreaming = false
        print("[RaneFlexFxService] CoreAudio FlexFX Audio Loop angehalten.")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onAudioStreamingChanged?(false)
            self.notifyStateChanged()
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
        } else {
            if isAudioStreaming {
                stopAudioEngine()
            }
        }
    }

    private func registerDeviceListener() {
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.checkAndUpdateAudioDevice()
        }
    }

    // MARK: - Real-Time Audio IO Callback Handler (Runs on CoreAudio High-Priority Thread)
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
        let frames = min(inFrames, outFrames)

        guard frames > 0, frames <= maxFramesPerBlock,
              let inPtr = inBuf.mData?.assumingMemoryBound(to: Float.self),
              let outPtr = outBuf.mData?.assumingMemoryBound(to: Float.self) else {
            return
        }

        // 1. Capture USB Record stereo pair from selected input source (Ch 1-12)
        var maxIn: Float = 0.0
        let inOffset = inputSource.channelOffset
        if inChannels >= inOffset + 2 {
            for f in 0..<frames {
                let sL = inPtr[f * inChannels + inOffset]
                let sR = inPtr[f * inChannels + inOffset + 1]
                scratchInL[f] = sL
                scratchInR[f] = sR
                let al = abs(sL)
                let ar = abs(sR)
                if al > maxIn { maxIn = al }
                if ar > maxIn { maxIn = ar }
            }
        } else {
            scratchInL.initialize(repeating: 0.0, count: frames)
            scratchInR.initialize(repeating: 0.0, count: frames)
        }
        liveSendPeak = maxIn

        // 2. Process through Parallel 3-Bus Matrix (VST 1 + VST 2 + Dry Bypass)
        processStereoBlock(inL: scratchInL, inR: scratchInR,
                           outL: scratchOutL, outR: scratchOutR,
                           frames: frames)

        // 3. Write summed output to selected USB Playback stereo pair (Ch 1-10)
        // Other channels of our IOProc are set to 0.0 so we never interfere with DJ software playback
        var maxOut: Float = 0.0
        let outOffset = outputDestination.channelOffset
        for f in 0..<frames {
            let offset = f * outChannels
            for c in 0..<outChannels {
                outPtr[offset + c] = 0.0
            }
            if outChannels > outOffset {
                let retL = scratchOutL[f]
                outPtr[offset + outOffset] = retL
                let al = abs(retL)
                if al > maxOut { maxOut = al }
            }
            if outChannels > outOffset + 1 {
                let retR = scratchOutR[f]
                outPtr[offset + outOffset + 1] = retR
                let ar = abs(retR)
                if ar > maxOut { maxOut = ar }
            }
        }
        liveReturnPeak = maxOut

        // Zero out any remaining trailing frames in output buffer if outFrames > frames
        if outFrames > frames {
            for f in frames..<outFrames {
                let offset = f * outChannels
                for c in 0..<outChannels {
                    outPtr[offset + c] = 0.0
                }
            }
        }
    }

    // MARK: - Native Ableton Link C++ Integration
    private func setupNativeAbletonLink() {
        _ = rane_link_init(bpm)

        rane_link_set_callbacks({ peers in
            DispatchQueue.main.async {
                let s = RaneFlexFxService.shared
                guard s.isLinkEnabled else { return }
                s.linkPeers = Int(peers)
                let liveTempo = rane_link_get_tempo()
                if liveTempo >= 40.0 && liveTempo <= 250.0 {
                    s.updateBpmFromLink(liveTempo)
                }
            }
        }, { newBpm in
            DispatchQueue.main.async {
                RaneFlexFxService.shared.updateBpmFromLink(newBpm)
            }
        })

        if isLinkEnabled {
            rane_link_enable(true)
        }

        let pTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        pTimer.schedule(deadline: .now() + 0.25, repeating: .milliseconds(250))
        pTimer.setEventHandler { [weak self] in
            guard let self = self, self.isLinkEnabled else { return }
            let peers = Int(rane_link_get_num_peers())
            if peers != self.linkPeers {
                self.linkPeers = peers
            }
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

    private func initDspBuffers() {
        // Freeverb tuning constants
        let combTuning = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        reverbCombL = combTuning.map { Array(repeating: 0.0, count: $0) }
        reverbCombR = combTuning.map { Array(repeating: 0.0, count: $0 + 23) }
        reverbCombPos = Array(repeating: 0, count: 8)

        let allpassTuning = [556, 441, 341, 225]
        reverbAllpassL = allpassTuning.map { Array(repeating: 0.0, count: $0) }
        reverbAllpassR = allpassTuning.map { Array(repeating: 0.0, count: $0 + 23) }
        reverbAllpassPos = Array(repeating: 0, count: 4)
    }

    // MARK: - Hardware LED Synchronization (Add Out Mapping Support)
    func updateHardwareLeds() {
        let learn = RaneMidiLearnService.shared
        let midi = RaneMidiService.shared

        // If module is disabled, all effect LEDs are turned off, but modulePower and abletonLink should reflect their states
        if !isModuleEnabled {
            clearAllHardwareLeds()
            if let pwrMap = learn.outMappingFor(target: .modulePower) {
                let ch = (pwrMap.channel == 255) ? 0 : pwrMap.channel
                if pwrMap.type == .note {
                    if pwrMap.offValue > 0 {
                        midi.sendNoteOn(note: pwrMap.number, velocity: pwrMap.offValue, channel: ch)
                    } else {
                        midi.sendNoteOff(note: pwrMap.number, channel: ch)
                    }
                } else {
                    midi.sendCC(cc: pwrMap.number, value: pwrMap.offValue, channel: ch)
                }
            }
            if let linkMap = learn.outMappingFor(target: .abletonLink) {
                let ch = (linkMap.channel == 255) ? 0 : linkMap.channel
                let vel = isLinkEnabled ? linkMap.onValue : linkMap.offValue
                if linkMap.type == .note {
                    if vel > 0 {
                        midi.sendNoteOn(note: linkMap.number, velocity: vel, channel: ch)
                    } else {
                        midi.sendNoteOff(note: linkMap.number, channel: ch)
                    }
                } else {
                    midi.sendCC(cc: linkMap.number, value: vel, channel: ch)
                }
            }
            return
        }

        let isModuleOn = isModuleEnabled
        let isFxOn = isEnabled
        let currentFx = currentEffect
        let isPre = isPreFader
        let isLinkOn = isLinkEnabled

        // Evaluate state for each target
        let targetStates: [FlexFxMidiTarget: Bool] = [
            .modulePower: isModuleOn,
            .vst1Toggle:  isFx1Enabled,
            .vst2Toggle:  isFx2Enabled,
            .fxToggle:    isFxOn,
            .fxFilter:    (currentFx == .filter),
            .fxFlanger:   (currentFx == .flanger),
            .fxPhaser:    (currentFx == .phaser),
            .fxEcho:      (currentFx == .echo),
            .fxDubDelay:  (currentFx == .dubDelay),
            .fxReverb:    (currentFx == .reverb),
            .prePost:     isPre,
            .abletonLink: isLinkOn,
            .inputFlexFx: (inputSource == .flexFxSend),
            .inputPgm1:   (inputSource == .pgm1),
            .inputPgm2:   (inputSource == .pgm2),
            .inputPgm3:   (inputSource == .pgm3),
            .inputPgm4:   (inputSource == .pgm4),
            .inputMainMix:(inputSource == .mainMix)
        ]

        // 1. Process custom Out Mappings
        var handledNotes = Set<UInt8>()
        for (target, state) in targetStates {
            if let outMap = learn.outMappingFor(target: target) {
                let ch = (outMap.channel == 255) ? 0 : outMap.channel
                let vel = state ? outMap.onValue : outMap.offValue
                if outMap.type == .note {
                    handledNotes.insert(outMap.number)
                    if vel > 0 {
                        midi.sendNoteOn(note: outMap.number, velocity: vel, channel: ch)
                    } else {
                        midi.sendNoteOff(note: outMap.number, channel: ch)
                    }
                } else {
                    midi.sendCC(cc: outMap.number, value: vel, channel: ch)
                }
            }
        }

        // 2. Default Sixty-Eight Hardware LED feedback for VST 1 (Note 13) & VST 2 (Note 8) if not overridden
        if !handledNotes.contains(13) && learn.outMappingFor(target: .vst1Toggle) == nil {
            if isFx1Enabled {
                midi.sendNoteOn(note: 13, velocity: 127, channel: 0)
            } else {
                midi.sendNoteOff(note: 13, channel: 0)
            }
        }
        if !handledNotes.contains(8) && learn.outMappingFor(target: .vst2Toggle) == nil {
            if isFx2Enabled {
                midi.sendNoteOn(note: 8, velocity: 127, channel: 0)
            } else {
                midi.sendNoteOff(note: 8, channel: 0)
            }
        }
        if !handledNotes.contains(0) && learn.outMappingFor(target: .fxToggle) == nil {
            if isFx1Enabled || isFx2Enabled {
                midi.sendNoteOn(note: 0, velocity: 127, channel: 0)
            } else {
                midi.sendNoteOff(note: 0, channel: 0)
            }
        }
    }

    func clearAllHardwareLeds() {
        let learn = RaneMidiLearnService.shared
        let midi = RaneMidiService.shared

        // Clear all custom configured out-mapping LEDs
        for (_, outMap) in learn.outMappings {
            let ch = (outMap.channel == 255) ? 0 : outMap.channel
            let offVel = outMap.offValue
            if outMap.type == .note {
                if offVel > 0 {
                    midi.sendNoteOn(note: outMap.number, velocity: offVel, channel: ch)
                } else {
                    midi.sendNoteOff(note: outMap.number, channel: ch)
                }
            } else {
                midi.sendCC(cc: outMap.number, value: offVel, channel: ch)
            }
        }

        // Also clear default hardware LEDs
        let notesToClear: [UInt8] = [12, 11, 10, 13, 9, 8, 14, 15, 0, 19]
        for note in notesToClear {
            midi.sendNoteOff(note: note, channel: 0)
        }
    }

    func setBpm(_ newBpm: Double) {
        let clamped = max(40.0, min(240.0, newBpm))
        bpm = clamped
        if isLinkEnabled {
            rane_link_set_tempo(clamped)
        }
    }

    func setManualBpm(_ newBpm: Double) {
        setBpm(newBpm)
    }

    func adjustBpm(delta: Double) {
        let newBpm = round((bpm + delta) * 10.0) / 10.0
        setBpm(newBpm)
    }

    func tapTempo() {
        let now = Date().timeIntervalSince1970
        if lastTapTime > 0 && (now - lastTapTime) < 2.0 {
            tapTimes.append(now - lastTapTime)
            if tapTimes.count > 4 { tapTimes.removeFirst() }
            let avgDelta = tapTimes.reduce(0.0, +) / Double(tapTimes.count)
            if avgDelta > 0.25 && avgDelta < 1.5 {
                let calculatedBpm = 60.0 / avgDelta
                setBpm(round(calculatedBpm * 10.0) / 10.0)
            }
        } else {
            tapTimes.removeAll()
        }
        lastTapTime = now
    }

    func cycleBeatDivision(forward: Bool) {
        guard isModuleEnabled else { return }
        let all = BeatDivision.allCases
        guard let currentIdx = all.firstIndex(of: currentDivision) else { return }
        if forward {
            if currentIdx + 1 < all.count { currentDivision = all[currentIdx + 1] }
        } else {
            if currentIdx > 0 { currentDivision = all[currentIdx - 1] }
        }
    }

    // Current Delay Time in milliseconds based on BPM and BeatDivision
    var delayTimeMs: Double {
        let beatSec = 60.0 / max(40.0, bpm)
        return beatSec * currentDivision.multiplier * 1000.0
    }

    // MARK: - Parallel 3-Bus Audio Processing Block (Stereo In/Out)
    func processStereoBlock(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                            outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                            frames: Int) {
        // If entire module is powered off, pass clean dry signal through
        guard isModuleEnabled else {
            for i in 0..<frames {
                outL[i] = inL[i]
                outR[i] = inR[i]
            }
            liveFx1Peak = 0.0
            liveFx2Peak = 0.0
            liveDryPeak = liveSendPeak
            return
        }

        let host = RanePluginHostService.shared

        // ---------------------------------------------------------------------
        // PATH 1 (TOP): Input -> Pre-Gain 1 -> VST Effekt 1 (Slot 0) -> Post-Gain 1
        // ---------------------------------------------------------------------
        let pre1  = Float(fx1PreGain)
        let post1 = Float(fx1PostGain)
        var maxP1: Float = 0.0

        if isFx1Enabled {
            for i in 0..<frames {
                path1InL[i] = inL[i] * pre1
                path1InR[i] = inR[i] * pre1
            }
            if !host.processSlot(0, inL: path1InL, inR: path1InR, outL: path1OutL, outR: path1OutR, frames: frames, bpm: bpm, sampleRate: sampleRate) {
                let fxType = host.slots.count > 0 ? host.slots[0].defaultType : .echo
                processInternalDaisySp(fxType: fxType, inL: path1InL, inR: path1InR, outL: path1OutL, outR: path1OutR, frames: frames)
            }
            for i in 0..<frames {
                let l = path1OutL[i] * post1
                let r = path1OutR[i] * post1
                path1OutL[i] = l
                path1OutR[i] = r
                let m = max(abs(l), abs(r))
                if m > maxP1 { maxP1 = m }
            }
        } else {
            for i in 0..<frames {
                path1OutL[i] = 0.0
                path1OutR[i] = 0.0
            }
        }
        liveFx1Peak = maxP1

        // ---------------------------------------------------------------------
        // PATH 2 (MIDDLE): Input -> Pre-Gain 2 -> VST Effekt 2 (Slot 1) -> Post-Gain 2
        // ---------------------------------------------------------------------
        let pre2  = Float(fx2PreGain)
        let post2 = Float(fx2PostGain)
        var maxP2: Float = 0.0

        if isFx2Enabled {
            for i in 0..<frames {
                path2InL[i] = inL[i] * pre2
                path2InR[i] = inR[i] * pre2
            }
            if !host.processSlot(1, inL: path2InL, inR: path2InR, outL: path2OutL, outR: path2OutR, frames: frames, bpm: bpm, sampleRate: sampleRate) {
                let fxType = host.slots.count > 1 ? host.slots[1].defaultType : .reverb
                processInternalDaisySp(fxType: fxType, inL: path2InL, inR: path2InR, outL: path2OutL, outR: path2OutR, frames: frames)
            }
            for i in 0..<frames {
                let l = path2OutL[i] * post2
                let r = path2OutR[i] * post2
                path2OutL[i] = l
                path2OutR[i] = r
                let m = max(abs(l), abs(r))
                if m > maxP2 { maxP2 = m }
            }
        } else {
            for i in 0..<frames {
                path2OutL[i] = 0.0
                path2OutR[i] = 0.0
            }
        }
        liveFx2Peak = maxP2

        // ---------------------------------------------------------------------
        // PATH 3 (BOTTOM - DRY) & MASTER SUM TO OUTPUT
        // Input -> Dry Pre-Gain -> Direct Pass-Through -> Dry Post-Gain
        // ---------------------------------------------------------------------
        let dryGain = Float(dryPreGain) * Float(dryPostGain)
        var maxDry: Float = 0.0

        for i in 0..<frames {
            let dL = inL[i] * dryGain
            let dR = inR[i] * dryGain
            let m = max(abs(dL), abs(dR))
            if m > maxDry { maxDry = m }

            outL[i] = path1OutL[i] + path2OutL[i] + dL
            outR[i] = path1OutR[i] + path2OutR[i] + dR
        }
        liveDryPeak = maxDry
    }

    // Internal fallback DaisySP processing when a slot is configured to an internal algorithm instead of an external VST/AU
    private func processInternalDaisySp(fxType: FlexFxType,
                                        inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                                        outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                                        frames: Int) {
        let fb = Float(min(0.92, depth * 0.88))
        let delaySamples = min(maxDelaySamples - 1, max(1, Int((delayTimeMs / 1000.0) * sampleRate)))

        for i in 0..<frames {
            let fxInL = inL[i]
            let fxInR = inR[i]
            var yL: Float = 0.0
            var yR: Float = 0.0

            switch fxType {
            case .echo:
                let readIdx = (delayHead - delaySamples + maxDelaySamples) % maxDelaySamples
                let dL = delayBufferL[readIdx]
                let dR = delayBufferR[readIdx]

                let echoCut = Float(fxParams.echoHighCut)
                let alpha = min(0.95, max(0.05, (2.0 * .pi * echoCut) / Float(sampleRate)))
                echoFilterL += alpha * (dL - echoFilterL)
                echoFilterR += alpha * (dR - echoFilterR)

                let pp = Float(fxParams.echoPingPong)
                let fbL = (echoFilterR * pp) + (echoFilterL * (1.0 - pp))
                let fbR = (echoFilterL * pp) + (echoFilterR * (1.0 - pp))

                delayBufferL[delayHead] = fxInL + (fbL * fb)
                delayBufferR[delayHead] = fxInR + (fbR * fb)
                delayHead = (delayHead + 1) % maxDelaySamples

                yL = dL
                yR = dR

            case .dubDelay:
                let flutterLfo = Float(sin(dubFlutterPhase * 2.0 * .pi))
                dubFlutterPhase += (0.8 + fxParams.dubFlutter * 2.5) / sampleRate
                if dubFlutterPhase >= 1.0 { dubFlutterPhase -= 1.0 }

                let flutterOffset = Int(flutterLfo * Float(fxParams.dubFlutter * 80.0))
                let readIdx = (delayHead - delaySamples + flutterOffset + maxDelaySamples) % maxDelaySamples
                let dL = delayBufferL[readIdx]
                let dR = delayBufferR[readIdx]

                let toneFreq = Float(fxParams.dubHighCut)
                let alpha = min(0.95, max(0.05, (2.0 * .pi * toneFreq) / Float(sampleRate)))
                dubFilterL += alpha * (dL - dubFilterL)
                dubFilterR += alpha * (dR - dubFilterR)

                let drive = Float(1.0 + fxParams.dubSaturation * 2.5)
                let satL = tanh(dubFilterL * drive) / drive
                let satR = tanh(dubFilterR * drive) / drive

                let dubFb = Float(min(0.98, depth * (0.65 + fxParams.dubResonance * 0.33)))

                delayBufferL[delayHead] = fxInL + (satR * dubFb * 0.75) + (satL * dubFb * 0.25)
                delayBufferR[delayHead] = fxInR + (satL * dubFb * 0.75) + (satR * dubFb * 0.25)
                delayHead = (delayHead + 1) % maxDelaySamples

                yL = satL
                yR = satR

            case .reverb:
                let inputMono = (fxInL + fxInR) * 0.018
                var accL: Float = 0.0
                var accR: Float = 0.0
                let room = Float(0.50 + fxParams.reverbRoomSize * 0.45)
                let damp = Float(fxParams.reverbDamping * 0.4)

                for c in 0..<8 {
                    let pos = reverbCombPos[c]
                    let cL = reverbCombL[c][pos]
                    let cR = reverbCombR[c][pos]
                    reverbCombL[c][pos] = inputMono + (cL * room * (1.0 - damp))
                    reverbCombR[c][pos] = inputMono + (cR * room * (1.0 - damp))
                    reverbCombPos[c] = (pos + 1) % reverbCombL[c].count
                    accL += cL
                    accR += cR
                }
                let width = Float(fxParams.reverbWidth)
                yL = accL * (0.5 + width * 0.5) + accR * (0.5 - width * 0.5)
                yR = accR * (0.5 + width * 0.5) + accL * (0.5 - width * 0.5)

            case .filter:
                let lfoFreq = fxParams.filterLfoRate
                filterLfoPhase += lfoFreq / sampleRate
                if filterLfoPhase >= 1.0 { filterLfoPhase -= 1.0 }
                let lfoMod = Float((sin(filterLfoPhase * 2.0 * .pi) + 1.0) * 0.5 * fxParams.filterLfoDepth)

                let baseCutoff = Float(fxParams.filterCutoff) / Float(sampleRate) * 2.0
                let cutoff = min(0.48, max(0.01, baseCutoff * (Float(0.3 + depth * 1.4)) + lfoMod * 0.15))
                let q = Float(max(0.2, 1.0 / fxParams.filterResonance))

                svfLowL += cutoff * svfBandL
                let highL = fxInL - svfLowL - q * svfBandL
                svfBandL += cutoff * highL

                svfLowR += cutoff * svfBandR
                let highR = fxInR - svfLowR - q * svfBandR
                svfBandR += cutoff * highR

                svfLowL = max(-2.0, min(2.0, svfLowL))
                svfLowR = max(-2.0, min(2.0, svfLowR))

                yL = svfLowL
                yR = svfLowR

            case .flanger:
                let flangerLfoFreq = fxParams.flangerRate
                lfoPhase += flangerLfoFreq / sampleRate
                if lfoPhase >= 1.0 { lfoPhase -= 1.0 }
                let mod = Float((sin(lfoPhase * 2.0 * .pi) + 1.0) * 0.5 * fxParams.flangerDepth)
                let baseSamples = Float(fxParams.flangerManual * 0.001 * sampleRate)
                let modSamples = Int(baseSamples + mod * 280.0)
                let readIdx = (delayHead - modSamples + maxDelaySamples) % maxDelaySamples

                let dL = delayBufferL[readIdx]
                let dR = delayBufferR[readIdx]
                let flangerFb = Float(fxParams.flangerFeedback * 0.9)
                delayBufferL[delayHead] = fxInL + dL * flangerFb
                delayBufferR[delayHead] = fxInR + dR * flangerFb
                delayHead = (delayHead + 1) % maxDelaySamples

                yL = dL
                yR = dR

            case .phaser:
                let phaserLfoFreq = fxParams.phaserRate
                phaserLfoPhase += phaserLfoFreq / sampleRate
                if phaserLfoPhase >= 1.0 { phaserLfoPhase -= 1.0 }
                let pMod = Float((sin(phaserLfoPhase * 2.0 * .pi) + 1.0) * 0.5 * fxParams.phaserDepth)
                let wp = min(0.95, max(0.05, Float(fxParams.phaserBaseFreq) / Float(sampleRate) * 2.0 + pMod * 0.3))
                let apCoef = (1.0 - wp) / (1.0 + wp)

                var sL = fxInL + phaserAllpassL[3] * Float(fxParams.phaserFeedback * 0.8)
                var sR = fxInR + phaserAllpassR[3] * Float(fxParams.phaserFeedback * 0.8)
                for st in 0..<4 {
                    let nextL = apCoef * sL + phaserAllpassL[st]
                    phaserAllpassL[st] = sL - apCoef * nextL
                    sL = nextL

                    let nextR = apCoef * sR + phaserAllpassR[st]
                    phaserAllpassR[st] = sR - apCoef * nextR
                    sR = nextR
                }
                yL = sL
                yR = sR
            }

            outL[i] = yL
            outR[i] = yR
        }
    }

    private func notifyStateChanged() {
        syncDriverDspState()
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?()
        }
    }
}
