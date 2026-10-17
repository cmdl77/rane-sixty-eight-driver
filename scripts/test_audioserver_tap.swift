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
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &devices) == noErr else { return nil }
    
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

print("Testing AudioDeviceIOProc output tone...")
guard let devId = findRaneAudioDevice() else { exit(1) }

var phase: Float = 0.0
let phaseInc: Float = (2.0 * Float.pi * 440.0) / 48000.0

let ioProc: AudioDeviceIOProc = { (_, _, _, _, outOutputData, _, _) -> OSStatus in
    let outData = outOutputData.pointee
    let buf = outData.mBuffers
    let channels = Int(buf.mNumberChannels)
    let frames = Int(buf.mDataByteSize) / (channels * 4)
    if let ptr = buf.mData?.assumingMemoryBound(to: Float.self) {
        for f in 0..<frames {
            let s = sinf(phase) * 0.5
            phase += phaseInc
            if phase > 2.0 * Float.pi { phase -= 2.0 * Float.pi }
            for c in 0..<channels {
                if c == 8 || c == 9 {
                    ptr[f * channels + c] = s
                } else {
                    ptr[f * channels + c] = 0.0
                }
            }
        }
    }
    return noErr
}

var pid: AudioDeviceIOProcID? = nil
AudioDeviceCreateIOProcID(devId, ioProc, nil, &pid)
AudioDeviceStart(devId, pid!)
Thread.sleep(forTimeInterval: 1.0)

// Check meters bin!
let path = "/var/tmp/rane_audio_meters.bin"
if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
    data.withUnsafeBytes { raw in
        guard let p = raw.baseAddress else { return }
        print("Out Ch 9 (FlexFX Return L): \(p.load(fromByteOffset: 96 + 8 * 4, as: Float.self))")
        print("Out Ch 10 (FlexFX Return R): \(p.load(fromByteOffset: 96 + 9 * 4, as: Float.self))")
    }
}
AudioDeviceStop(devId, pid!)
AudioDeviceDestroyIOProcID(devId, pid!)
