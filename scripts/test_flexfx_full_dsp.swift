import Foundation
import CoreAudio

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

guard let devId = findRaneAudioDevice() else {
    print("Rane device not found!")
    exit(1)
}

print("Selected Rane device: \(devId)")

// Pre-allocated buffers
let maxFrames = 4096
let scratchInL = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
let scratchInR = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
let scratchOutL = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
let scratchOutR = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)

// Delay Line
let maxDelaySamples = 48000 * 4
let delayBufL = UnsafeMutablePointer<Float>.allocate(capacity: maxDelaySamples)
let delayBufR = UnsafeMutablePointer<Float>.allocate(capacity: maxDelaySamples)
delayBufL.initialize(repeating: 0.0, count: maxDelaySamples)
delayBufR.initialize(repeating: 0.0, count: maxDelaySamples)
var delayHead = 0

// DSP Echo test function
func processEcho(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                 outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                 frames: Int, delaySamples: Int, feedback: Float, wet: Float) {
    let dry = 1.0 - wet
    for i in 0..<frames {
        let xL = inL[i]
        let xR = inR[i]
        
        let readIdx = (delayHead - delaySamples + maxDelaySamples) % maxDelaySamples
        let dL = delayBufL[readIdx]
        let dR = delayBufR[readIdx]
        
        delayBufL[delayHead] = xL + (dR * feedback)
        delayBufR[delayHead] = xR + (dL * feedback)
        delayHead = (delayHead + 1) % maxDelaySamples
        
        outL[i] = (xL * dry) + (dL * wet)
        outR[i] = (xR * dry) + (dR * wet)
    }
}

let ioProc: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData) -> OSStatus in
    let inData = inInputData.pointee
    let outData = outOutputData.pointee
    
    let inBuf = inData.mBuffers
    let outBuf = outData.mBuffers
    
    let inChannels = Int(inBuf.mNumberChannels)
    let outChannels = Int(outBuf.mNumberChannels)
    
    let inFrames = inChannels > 0 ? Int(inBuf.mDataByteSize) / (inChannels * MemoryLayout<Float>.size) : 0
    let outFrames = outChannels > 0 ? Int(outBuf.mDataByteSize) / (outChannels * MemoryLayout<Float>.size) : 0
    let frames = min(inFrames, outFrames)
    
    guard frames > 0, frames <= maxFrames,
          let inPtr = inBuf.mData?.assumingMemoryBound(to: Float.self),
          let outPtr = outBuf.mData?.assumingMemoryBound(to: Float.self) else {
        return noErr
    }
    
    if inChannels >= 10 {
        for f in 0..<frames {
            scratchInL[f] = inPtr[f * inChannels + 8]
            scratchInR[f] = inPtr[f * inChannels + 9]
        }
    }
    
    // 500ms delay at 48kHz = 24000 samples
    processEcho(inL: scratchInL, inR: scratchInR, outL: scratchOutL, outR: scratchOutR,
                frames: frames, delaySamples: 24000, feedback: 0.6, wet: 0.5)
    
    for f in 0..<frames {
        let offset = f * outChannels
        for c in 0..<min(8, outChannels) {
            outPtr[offset + c] = 0.0
        }
        if outChannels > 8 {
            outPtr[offset + 8] = scratchOutL[f]
        }
        if outChannels > 9 {
            outPtr[offset + 9] = scratchOutR[f]
        }
    }
    
    return noErr
}

var procId: AudioDeviceIOProcID? = nil
let err = AudioDeviceCreateIOProcID(devId, ioProc, nil, &procId)
if err == noErr, let pid = procId {
    _ = AudioDeviceStart(devId, pid)
    print("Live FlexFX Audio Engine gestartet! Läuft für 3 Sekunden...")
    Thread.sleep(forTimeInterval: 3.0)
    _ = AudioDeviceStop(devId, pid)
    AudioDeviceDestroyIOProcID(devId, pid)
    print("Gestoppt.")
}
