/* SPDX-License-Identifier: MIT */
/* RaneFlexFxService.swift - Software FlexFX DSP Engine with DaisySP algorithms, Native Ableton Link & CoreAudio IO Loop */

import Foundation
import CoreAudio
import AudioToolbox
import CoreMIDI

enum FlexFxType: Int, CaseIterable {
    case filter  = 0
    case flanger = 1
    case phaser  = 2
    case echo    = 3
    case robot   = 4
    case reverb  = 5

    var displayName: String {
        switch self {
        case .filter:  return "FILTER"
        case .flanger: return "FLANGER"
        case .phaser:  return "PHASER"
        case .echo:    return "ECHO"
        case .robot:   return "ROBOT"
        case .reverb:  return "REVERB"
        }
    }
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

    // Flag to prevent MIDI loops during incoming MIDI processing
    var isSuppressingHardwareLeds: Bool = false

    // Master Module Power Switch (Turns entire module ON or OFF)
    var isModuleEnabled: Bool = true {
        didSet {
            if isModuleEnabled {
                rane_link_enable(isLinkEnabled)
                if isLinkEnabled {
                    linkPeers = Int(rane_link_get_num_peers())
                    let liveTempo = rane_link_get_tempo()
                    if liveTempo >= 40.0 && liveTempo <= 250.0 {
                        bpm = round(liveTempo * 10.0) / 10.0
                    }
                }
                if !isSuppressingHardwareLeds { updateHardwareLeds() }
                startAudioEngine()
            } else {
                rane_link_enable(false)
                clearAllHardwareLeds()
            }
            notifyStateChanged()
        }
    }

    // Engine Parameters
    var currentEffect: FlexFxType = .echo {
        didSet {
            notifyStateChanged()
            if !isSuppressingHardwareLeds { updateHardwareLeds() }
        }
    }
    var currentDivision: BeatDivision = .d1_2 {
        didSet { notifyStateChanged() }
    }
    var bpm: Double = 124.0 {
        didSet { notifyStateChanged() }
    }
    var isEnabled: Bool = true {
        didSet {
            notifyStateChanged()
            if !isSuppressingHardwareLeds { updateHardwareLeds() }
        }
    }
    var isLinkEnabled: Bool = true {
        didSet {
            if isModuleEnabled {
                rane_link_enable(isLinkEnabled)
                if isLinkEnabled {
                    linkPeers = Int(rane_link_get_num_peers())
                    let liveTempo = rane_link_get_tempo()
                    if liveTempo >= 40.0 && liveTempo <= 250.0 {
                        bpm = round(liveTempo * 10.0) / 10.0
                    }
                } else {
                    linkPeers = 0
                }
            } else {
                rane_link_enable(false)
                linkPeers = 0
            }
            notifyStateChanged()
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
        didSet { notifyStateChanged() }
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

    // Link Polling
    private var linkPollTimer: DispatchSourceTimer?
    private var currentBeatIndex: Int = 0
    private var lastTapTime: TimeInterval = 0
    private var tapTimes: [TimeInterval] = []

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

    // Flanger LFO Phase
    private var lfoPhase: Double = 0.0

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

        // Allocate Delay Line buffers
        delayBufferL = UnsafeMutablePointer<Float>.allocate(capacity: maxDelaySamples)
        delayBufferR = UnsafeMutablePointer<Float>.allocate(capacity: maxDelaySamples)
        delayBufferL.initialize(repeating: 0.0, count: maxDelaySamples)
        delayBufferR.initialize(repeating: 0.0, count: maxDelaySamples)

        initDspBuffers()
        setupNativeAbletonLink()
        startAudioEngine()
        registerDeviceListener()
    }

    deinit {
        stopAudioEngine()
        scratchInL.deallocate()
        scratchInR.deallocate()
        scratchOutL.deallocate()
        scratchOutR.deallocate()
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

        // 1. Capture USB In Channels 9 & 10 (0-indexed 8 & 9: FLEXFX SEND)
        var maxIn: Float = 0.0
        if inChannels >= 10 {
            for f in 0..<frames {
                let sL = inPtr[f * inChannels + 8]
                let sR = inPtr[f * inChannels + 9]
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

        // 2. Process through DaisySP DSP Block (or clean dry bypass when module/effect is inactive)
        processStereoBlock(inL: scratchInL, inR: scratchInR,
                           outL: scratchOutL, outR: scratchOutR,
                           frames: frames)

        // 3. Write to USB Out Channels (10 Channels Total):
        // Channels 0..7 (Decks 1-4): Set to 0.0 so we do not overwrite or interfere with other DJ playback
        // Channels 8 & 9 (FLEXFX RETURN): Output our processed wet/dry audio back into the mixer's return loop!
        var maxOut: Float = 0.0
        for f in 0..<frames {
            let offset = f * outChannels
            for c in 0..<min(8, outChannels) {
                outPtr[offset + c] = 0.0
            }
            if outChannels > 8 {
                let retL = scratchOutL[f]
                outPtr[offset + 8] = retL
                let al = abs(retL)
                if al > maxOut { maxOut = al }
            }
            if outChannels > 9 {
                let retR = scratchOutR[f]
                outPtr[offset + 9] = retR
                let ar = abs(retR)
                if ar > maxOut { maxOut = ar }
            }
            if outChannels > 10 {
                for c in 10..<outChannels {
                    outPtr[offset + c] = 0.0
                }
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
                guard s.isModuleEnabled && s.isLinkEnabled else { return }
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

        if isModuleEnabled && isLinkEnabled {
            rane_link_enable(true)
        }

        let pTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        pTimer.schedule(deadline: .now() + 0.25, repeating: .milliseconds(250))
        pTimer.setEventHandler { [weak self] in
            guard let self = self, self.isModuleEnabled, self.isLinkEnabled else { return }
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
        guard isModuleEnabled && isLinkEnabled else { return }
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

    // MARK: - Hardware LED Synchronization
    func updateHardwareLeds() {
        guard RaneMidiService.shared.isConnected else { return }
        if !isModuleEnabled {
            clearAllHardwareLeds()
            return
        }
        let fxMap: [(FlexFxType, UInt8)] = [
            (.filter, 12),
            (.flanger, 11),
            (.phaser, 10),
            (.echo, 13),
            (.robot, 9),
            (.reverb, 8)
        ]
        for (fx, note) in fxMap {
            if fx == currentEffect {
                RaneMidiService.shared.sendNoteOn(note: note, velocity: 127, channel: 0)
            } else {
                RaneMidiService.shared.sendNoteOff(note: note, channel: 0)
            }
        }
        if isEnabled {
            RaneMidiService.shared.sendNoteOn(note: 0, velocity: 127, channel: 0)
        } else {
            RaneMidiService.shared.sendNoteOff(note: 0, channel: 0)
        }
    }

    func clearAllHardwareLeds() {
        guard RaneMidiService.shared.isConnected else { return }
        let notesToClear: [UInt8] = [12, 11, 10, 13, 9, 8, 14, 15, 0]
        for note in notesToClear {
            RaneMidiService.shared.sendNoteOff(note: note, channel: 0)
        }
    }

    func setBpm(_ newBpm: Double) {
        let clamped = max(60.0, min(220.0, newBpm))
        bpm = clamped
        if isModuleEnabled && isLinkEnabled {
            rane_link_set_tempo(clamped)
        }
    }

    func adjustBpm(delta: Double) {
        let newBpm = round((bpm + delta) * 10.0) / 10.0
        setBpm(newBpm)
    }

    func tapTempo() {
        // Tap tempo is only allowed when Link is OFF (Standalone Mode)
        guard isModuleEnabled && !isLinkEnabled else { return }
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

    // MARK: - DaisySP Audio Processing Block (Stereo In/Out)
    func processStereoBlock(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                            outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                            frames: Int) {
        // If entire module is powered off, pass clean dry signal through
        guard isModuleEnabled else {
            for i in 0..<frames {
                outL[i] = inL[i]
                outR[i] = inR[i]
            }
            return
        }

        // PRE-FADER MODE: Hard bypass when effect is switched off
        if isPreFader && !isEnabled {
            for i in 0..<frames {
                outL[i] = inL[i]
                outR[i] = inR[i]
            }
            return
        }

        // POST-FADER MODE: When isEnabled is true, signal feeds effect normally.
        // When isEnabled is false (in post mode), fxIn becomes 0.0 (muted input),
        // but the internal reverb & echo feedback delay lines continue to decay naturally ("Hallfahne").
        let fxActive = isEnabled
        let wet = Float(dryWet)
        let dry = 1.0 - (fxActive ? wet : 0.0) // Dry is full volume when effect bypassed
        let fb = Float(min(0.92, depth * 0.88))

        let delaySamples = min(maxDelaySamples - 1, max(1, Int((delayTimeMs / 1000.0) * sampleRate)))

        for i in 0..<frames {
            let xL = inL[i]
            let xR = inR[i]

            // Feed input to effect only if effect is actively ON.
            // If OFF (Post mode), feed 0.0 so the tail rings out without new input.
            let fxInL = fxActive ? xL : 0.0
            let fxInR = fxActive ? xR : 0.0

            var yL: Float = 0.0
            var yR: Float = 0.0

            switch currentEffect {
            case .echo:
                // DaisySP DelayLine Ping-Pong Stereo Beat Echo
                let readIdx = (delayHead - delaySamples + maxDelaySamples) % maxDelaySamples
                let dL = delayBufferL[readIdx]
                let dR = delayBufferR[readIdx]

                delayBufferL[delayHead] = fxInL + (dR * fb)
                delayBufferR[delayHead] = fxInR + (dL * fb)
                delayHead = (delayHead + 1) % maxDelaySamples

                yL = dL
                yR = dR

            case .reverb:
                // DaisySP / Freeverb Stereo Reverb Matrix
                let inputMono = (fxInL + fxInR) * 0.015
                var accL: Float = 0.0
                var accR: Float = 0.0
                let room = 0.70 + (fb * 0.28)

                for c in 0..<8 {
                    let pos = reverbCombPos[c]
                    let cL = reverbCombL[c][pos]
                    let cR = reverbCombR[c][pos]
                    reverbCombL[c][pos] = inputMono + (cL * room)
                    reverbCombR[c][pos] = inputMono + (cR * room)
                    reverbCombPos[c] = (pos + 1) % reverbCombL[c].count
                    accL += cL
                    accR += cR
                }
                yL = accL
                yR = accR

            case .filter:
                // DaisySP SVF (State Variable Filter) Resonant Lowpass/Bandpass
                let cutoff = min(0.45, Float(0.02 + pow(depth, 2.0) * 0.40))
                let q = Float(0.5)
                svfLowL += cutoff * svfBandL
                let highL = fxInL - svfLowL - q * svfBandL
                svfBandL += cutoff * highL

                svfLowR += cutoff * svfBandR
                let highR = fxInR - svfLowR - q * svfBandR
                svfBandR += cutoff * highR

                // Anti-blowup clamping
                svfLowL = max(-2.0, min(2.0, svfLowL))
                svfLowR = max(-2.0, min(2.0, svfLowR))

                yL = svfLowL
                yR = svfLowR

            case .flanger, .phaser:
                // LFO Modulated Comb Filter
                let lfoFreq = (bpm / 60.0) / (currentDivision.multiplier * 4.0)
                lfoPhase += lfoFreq / sampleRate
                if lfoPhase >= 1.0 { lfoPhase -= 1.0 }
                let mod = (sin(lfoPhase * 2.0 * .pi) + 1.0) * 0.5
                let modSamples = Int(24.0 + mod * 320.0)
                let readIdx = (delayHead - modSamples + maxDelaySamples) % maxDelaySamples

                let dL = delayBufferL[readIdx]
                let dR = delayBufferR[readIdx]
                delayBufferL[delayHead] = fxInL + dL * fb * 0.7
                delayBufferR[delayHead] = fxInR + dR * fb * 0.7
                delayHead = (delayHead + 1) % maxDelaySamples

                yL = dL
                yR = dR

            case .robot:
                // DaisySP Decimator / Bitcrusher Robotizer
                let steps = Float(max(2.0, 32.0 * (1.0 - depth)))
                yL = round(fxInL * steps) / steps
                yR = round(fxInR * steps) / steps
            }

            outL[i] = (xL * dry) + (yL * wet)
            outR[i] = (xR * dry) + (yR * wet)
        }
    }

    private func notifyStateChanged() {
        syncDriverDspState()
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?()
        }
    }
}
