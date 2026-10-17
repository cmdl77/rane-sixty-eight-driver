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
    print("Device not found")
    exit(1)
}

var callbacks = 0
var capturedInL: Float = 0.0
var capturedInR: Float = 0.0

let ioProc: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData) -> OSStatus in
    callbacks += 1
    
    let inData = inInputData.pointee
    let outData = outOutputData.pointee
    
    let inBuf = inData.mBuffers
    let outBuf = outData.mBuffers
    
    let inChannels = Int(inBuf.mNumberChannels)
    let outChannels = Int(outBuf.mNumberChannels)
    
    let inFrames = inChannels > 0 ? Int(inBuf.mDataByteSize) / (inChannels * MemoryLayout<Float>.size) : 0
    let outFrames = outChannels > 0 ? Int(outBuf.mDataByteSize) / (outChannels * MemoryLayout<Float>.size) : 0
    let frames = min(inFrames, outFrames)
    
    if let inPtr = inBuf.mData?.assumingMemoryBound(to: Float.self),
       let outPtr = outBuf.mData?.assumingMemoryBound(to: Float.self) {
        for f in 0..<frames {
            // Read In 9 & 10 (channels 8 & 9)
            let sL = inPtr[f * inChannels + 8]
            let sR = inPtr[f * inChannels + 9]
            if abs(sL) > capturedInL { capturedInL = abs(sL) }
            if abs(sR) > capturedInR { capturedInR = abs(sR) }
            
            let offset = f * outChannels
            for c in 0..<outChannels {
                outPtr[offset + c] = 0.0
            }
            // DIRECT PASSTHROUGH TO RETURN (Ch 9 & 10 / index 8 & 9)
            outPtr[offset + 8] = sL
            outPtr[offset + 9] = sR
        }
    }
    return noErr
}

var procId: AudioDeviceIOProcID? = nil
let err = AudioDeviceCreateIOProcID(devId, ioProc, nil, &procId)
print("CreateIOProcID: \(err)")
if err == noErr, let pid = procId {
    let sErr = AudioDeviceStart(devId, pid)
    print("AudioDeviceStart: \(sErr)")
    for i in 1...5 {
        Thread.sleep(forTimeInterval: 0.5)
        print("[\(i*500)ms] Callbacks: \(callbacks), In 9: \(capturedInL), In 10: \(capturedInR)")
    }
    AudioDeviceStop(devId, pid)
    AudioDeviceDestroyIOProcID(devId, pid)
}
