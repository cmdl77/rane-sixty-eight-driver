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
    print("Rane Sixty-Eight nicht gefunden!")
    exit(1)
}

print("Monitoring Rane Sixty-Eight FlexFX Send (Ch 9 & 10 / In 8 & 9)...")
print("Press Ctrl+C to cancel.")

var peakSendL: Float = 0.0
var peakSendR: Float = 0.0
var passCount = 0

let ioProc: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData) -> OSStatus in
    let inData = inInputData.pointee
    let inBuf = inData.mBuffers
    let inChannels = Int(inBuf.mNumberChannels)
    let inFrames = Int(inBuf.mDataByteSize) / (inChannels * MemoryLayout<Float>.size)
    if let inPtr = inBuf.mData?.assumingMemoryBound(to: Float.self) {
        if inChannels >= 10 {
            for f in 0..<inFrames {
                let l = abs(inPtr[f * inChannels + 8])
                let r = abs(inPtr[f * inChannels + 9])
                if l > peakSendL { peakSendL = l }
                if r > peakSendR { peakSendR = r }
            }
        }
    }
    
    // Passthrough to Return for testing loop
    let outData = outOutputData.pointee
    let outBuf = outData.mBuffers
    let outChannels = Int(outBuf.mNumberChannels)
    let outFrames = Int(outBuf.mDataByteSize) / (outChannels * MemoryLayout<Float>.size)
    if let outPtr = outBuf.mData?.assumingMemoryBound(to: Float.self),
       let inPtr = inBuf.mData?.assumingMemoryBound(to: Float.self) {
        let framesToProcess = min(inFrames, outFrames)
        for f in 0..<framesToProcess {
            for c in 0..<outChannels {
                if c == 8 && inChannels > 8 {
                    outPtr[f * outChannels + c] = inPtr[f * inChannels + 8]
                } else if c == 9 && inChannels > 9 {
                    outPtr[f * outChannels + c] = inPtr[f * inChannels + 9]
                } else {
                    outPtr[f * outChannels + c] = 0.0
                }
            }
        }
    }
    
    passCount += 1
    return noErr
}

var procId: AudioDeviceIOProcID? = nil
let err = AudioDeviceCreateIOProcID(devId, ioProc, nil, &procId)
guard err == noErr, let pid = procId else {
    print("Fehler beim Erstellen des IOProcs: \(err)")
    exit(1)
}

_ = AudioDeviceStart(devId, pid)

for i in 1...6 {
    Thread.sleep(forTimeInterval: 0.5)
    print("[\(i*500)ms] Callbacks: \(passCount), FlexFX Send Peak L: \(String(format: "%.4f", peakSendL)), R: \(String(format: "%.4f", peakSendR))")
    peakSendL = 0.0
    peakSendR = 0.0
}

_ = AudioDeviceStop(devId, pid)
AudioDeviceDestroyIOProcID(devId, pid)
print("Monitoring beendet.")
