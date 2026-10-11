/* SPDX-License-Identifier: MIT */
/* RaneMeterService.swift - Shared-memory reader & ballistics processor for Rane 68 audio meters (12 In / 10 Out) */

import Foundation
import Cocoa
import CoreAudio

final class RaneMeterService {
    static let shared = RaneMeterService()

    private let meterFilePath = "/var/tmp/rane_audio_meters.bin"
    private var fileDescriptor: Int32 = -1
    private var mappedMemory: UnsafeMutableRawPointer?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "org.openrane.meterservice", qos: .userInteractive)

    private var monitorIOProcId: AudioDeviceIOProcID?
    private var monitoredDeviceId: AudioDeviceID = 0

    // Public state (updated on main thread for UI: 12 Inputs, 10 Outputs)
    private(set) var inPeaks: [Float] = Array(repeating: 0.0, count: 12)
    private(set) var outPeaks: [Float] = Array(repeating: 0.0, count: 10)
    private(set) var inHold: [Float] = Array(repeating: 0.0, count: 12)
    private(set) var outHold: [Float] = Array(repeating: 0.0, count: 10)
    private(set) var inClips: [Bool] = Array(repeating: false, count: 12)
    private(set) var outClips: [Bool] = Array(repeating: false, count: 10)
    private(set) var isStreamingActive: Bool = false
    private(set) var sampleRate: UInt32 = 48000
    private(set) var bufferFrameSize: UInt32 = 512

    // Peak hold counters (ticks)
    private var inHoldTicks: [Int] = Array(repeating: 0, count: 12)
    private var outHoldTicks: [Int] = Array(repeating: 0, count: 10)
    private var inClipTicks: [Int] = Array(repeating: 0, count: 12)
    private var outClipTicks: [Int] = Array(repeating: 0, count: 10)

    // Ballistic decay parameters (at 30 FPS)
    private let decayFactor: Float = 0.84   // ~20 dB decay per 300 ms
    private let holdDurationTicks: Int = 24 // ~0.8 second hold
    private let clipDurationTicks: Int = 36 // ~1.2 second clip light

    // Listeners
    var onMetersUpdated: ((RaneMeterService) -> Void)?

    private init() {
        openSharedMemory()
        startAudioMonitoring()
        startPolling()
    }

    deinit {
        stopPolling()
        stopAudioMonitoring()
        closeSharedMemory()
    }

    func startAudioMonitoring() {
        guard monitorIOProcId == nil else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devCount: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &devCount)
        let count = Int(devCount) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return }
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &devCount, &devices) == noErr else { return }

        for d in devices {
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString?
            if AudioObjectGetPropertyData(d, &nameAddr, 0, nil, &nameSize, &name) == noErr, let n = name as String? {
                if n.contains("Rane") || n.contains("Sixty-Eight") {
                    monitoredDeviceId = d
                    break
                }
            }
        }

        guard monitoredDeviceId != 0 else { return }

        var procId: AudioDeviceIOProcID?
        let err = AudioDeviceCreateIOProcID(monitoredDeviceId, { (_, _, _, _, _, _, _) -> OSStatus in
            // Passive monitoring tap: keeps CoreAudio active so driver calculates live peak meters!
            return noErr
        }, nil, &procId)

        if err == noErr, let p = procId {
            monitorIOProcId = p
            AudioDeviceStart(monitoredDeviceId, p)
        }
    }

    func stopAudioMonitoring() {
        if let p = monitorIOProcId, monitoredDeviceId != 0 {
            AudioDeviceStop(monitoredDeviceId, p)
            AudioDeviceDestroyIOProcID(monitoredDeviceId, p)
            monitorIOProcId = nil
            monitoredDeviceId = 0
        }
    }

    private func openSharedMemory() {
        fileDescriptor = open(meterFilePath, O_RDONLY)
        if fileDescriptor < 0 {
            return
        }
        let size = 168 // Buffer size for safety
        let ptr = mmap(nil, size, PROT_READ, MAP_SHARED, fileDescriptor, 0)
        if ptr == MAP_FAILED {
            close(fileDescriptor)
            fileDescriptor = -1
            return
        }
        mappedMemory = ptr
    }

    private func closeSharedMemory() {
        if let ptr = mappedMemory {
            munmap(ptr, 168)
            mappedMemory = nil
        }
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    func startPolling() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33)) // ~30 FPS
        t.setEventHandler { [weak self] in
            self?.pollMeters()
        }
        timer = t
        t.resume()
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    private func pollMeters() {
        if mappedMemory == nil {
            openSharedMemory()
            if mappedMemory == nil {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.decayToZero()
                    self.onMetersUpdated?(self)
                }
                return
            }
        }

        guard let ptr = mappedMemory else { return }

        // Validate magic 'RANE' = 0x52414E45
        let magic = ptr.load(fromByteOffset: 0, as: UInt32.self)
        guard magic == 0x52414E45 else {
            return
        }

        let isRunningVal = ptr.load(fromByteOffset: 32, as: UInt32.self)
        let sr = ptr.load(fromByteOffset: 24, as: UInt32.self)
        let buf = ptr.load(fromByteOffset: 28, as: UInt32.self)

        // Read 12 Input peaks starting at offset 48, and 10 Output peaks starting at offset 96
        var rawIn = [Float](repeating: 0, count: 12)
        var rawOut = [Float](repeating: 0, count: 10)

        for i in 0..<12 {
            rawIn[i] = ptr.load(fromByteOffset: 48 + i * 4, as: Float.self)
        }
        for i in 0..<10 {
            rawOut[i] = ptr.load(fromByteOffset: 96 + i * 4, as: Float.self)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isStreamingActive = (isRunningVal != 0)
            self.sampleRate = sr > 0 ? sr : 48000
            self.bufferFrameSize = buf > 0 ? buf : 512

            // Input ballistics (12 channels)
            for i in 0..<12 {
                let targetIn = rawIn[i]
                if targetIn >= self.inPeaks[i] {
                    self.inPeaks[i] = targetIn
                } else {
                    self.inPeaks[i] = max(0.0, self.inPeaks[i] * self.decayFactor)
                }

                if self.inPeaks[i] >= self.inHold[i] {
                    self.inHold[i] = self.inPeaks[i]
                    self.inHoldTicks[i] = self.holdDurationTicks
                } else {
                    if self.inHoldTicks[i] > 0 {
                        self.inHoldTicks[i] -= 1
                    } else {
                        self.inHold[i] = max(0.0, self.inHold[i] * self.decayFactor)
                    }
                }

                if targetIn >= 0.999 {
                    self.inClips[i] = true
                    self.inClipTicks[i] = self.clipDurationTicks
                } else if self.inClipTicks[i] > 0 {
                    self.inClipTicks[i] -= 1
                } else {
                    self.inClips[i] = false
                }
            }

            // Output ballistics (10 channels)
            for i in 0..<10 {
                let targetOut = rawOut[i]
                if targetOut >= self.outPeaks[i] {
                    self.outPeaks[i] = targetOut
                } else {
                    self.outPeaks[i] = max(0.0, self.outPeaks[i] * self.decayFactor)
                }

                if self.outPeaks[i] >= self.outHold[i] {
                    self.outHold[i] = self.outPeaks[i]
                    self.outHoldTicks[i] = self.holdDurationTicks
                } else {
                    if self.outHoldTicks[i] > 0 {
                        self.outHoldTicks[i] -= 1
                    } else {
                        self.outHold[i] = max(0.0, self.outHold[i] * self.decayFactor)
                    }
                }

                if targetOut >= 0.999 {
                    self.outClips[i] = true
                    self.outClipTicks[i] = self.clipDurationTicks
                } else if self.outClipTicks[i] > 0 {
                    self.outClipTicks[i] -= 1
                } else {
                    self.outClips[i] = false
                }
            }

            self.onMetersUpdated?(self)
        }
    }

    private func decayToZero() {
        self.isStreamingActive = false
        for i in 0..<12 {
            self.inPeaks[i] = max(0.0, self.inPeaks[i] * self.decayFactor)
            self.inHold[i] = max(0.0, self.inHold[i] * self.decayFactor)
            if self.inClipTicks[i] > 0 { self.inClipTicks[i] -= 1 } else { self.inClips[i] = false }
        }
        for i in 0..<10 {
            self.outPeaks[i] = max(0.0, self.outPeaks[i] * self.decayFactor)
            self.outHold[i] = max(0.0, self.outHold[i] * self.decayFactor)
            if self.outClipTicks[i] > 0 { self.outClipTicks[i] -= 1 } else { self.outClips[i] = false }
        }
    }
}
