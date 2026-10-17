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

var printed = false

let ioProc: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData) -> OSStatus in
    if !printed {
        let inData = inInputData.pointee
        let buf = inData.mBuffers
        let channels = Int(buf.mNumberChannels)
        let frames = Int(buf.mDataByteSize) / (channels * 4)
        if let ptr = buf.mData?.assumingMemoryBound(to: Float.self) {
            print("First frame of \(frames) frames:")
            for c in 0..<channels {
                print("Ch \(c+1): \(ptr[c])")
            }
            var maxCh = [Float](repeating: 0, count: channels)
            for f in 0..<frames {
                for c in 0..<channels {
                    let v = abs(ptr[f * channels + c])
                    if v > maxCh[c] { maxCh[c] = v }
                }
            }
            print("Max over buffer:")
            for c in 0..<channels {
                print("Ch \(c+1) max: \(maxCh[c])")
            }
            printed = true
        }
    }
    return noErr
}

var procId: AudioDeviceIOProcID? = nil
let err = AudioDeviceCreateIOProcID(devId, ioProc, nil, &procId)
if err == noErr, let pid = procId {
    AudioDeviceStart(devId, pid)
    Thread.sleep(forTimeInterval: 0.5)
    AudioDeviceStop(devId, pid)
    AudioDeviceDestroyIOProcID(devId, pid)
}
