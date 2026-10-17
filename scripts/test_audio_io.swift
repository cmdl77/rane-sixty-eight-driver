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
    guard status == noErr else { return nil }
    
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

print("Selected Rane device ID: \(devId)")

var phase: Float = 0.0
let phaseInc: Float = (2.0 * Float.pi * 440.0) / 48000.0

let ioProc: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData) -> OSStatus in
    let outData = outOutputData.pointee
    let outBuf = outData.mBuffers
    let outChannels = Int(outBuf.mNumberChannels)
    let outFrames = Int(outBuf.mDataByteSize) / (outChannels * MemoryLayout<Float>.size)
    if let outPtr = outBuf.mData?.assumingMemoryBound(to: Float.self) {
        for f in 0..<outFrames {
            let s = sinf(phase) * 0.5
            phase += phaseInc
            if phase > 2.0 * Float.pi { phase -= 2.0 * Float.pi }
            
            for c in 0..<outChannels {
                if c == 8 || c == 9 {
                    outPtr[f * outChannels + c] = s // FlexFX Return
                } else {
                    outPtr[f * outChannels + c] = 0.0
                }
            }
        }
    }
    return noErr
}

var procId: AudioDeviceIOProcID? = nil
let err = AudioDeviceCreateIOProcID(devId, ioProc, nil, &procId)
if err == noErr, let pid = procId {
    _ = AudioDeviceStart(devId, pid)
    print("Streaming 440Hz test tone to FlexFX Return (Ch 9/10)...")
    Thread.sleep(forTimeInterval: 2.0)
    _ = AudioDeviceStop(devId, pid)
    AudioDeviceDestroyIOProcID(devId, pid)
    print("Done.")
}
