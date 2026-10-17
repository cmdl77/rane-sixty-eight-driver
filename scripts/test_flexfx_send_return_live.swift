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

print("Device ID: \(devId)")

// Inspect input stream format
var formatAddr = AudioObjectPropertyAddress(
    mSelector: kAudioStreamPropertyVirtualFormat,
    mScope: kAudioObjectPropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain
)
var asbd = AudioStreamBasicDescription()
var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
if AudioObjectGetPropertyData(devId, &formatAddr, 0, nil, &asbdSize, &asbd) == noErr {
    print("Input ASBD: \(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) ch, bits: \(asbd.mBitsPerChannel)")
}

// Inspect output stream format
var outFormatAddr = AudioObjectPropertyAddress(
    mSelector: kAudioStreamPropertyVirtualFormat,
    mScope: kAudioObjectPropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain
)
if AudioObjectGetPropertyData(devId, &outFormatAddr, 0, nil, &asbdSize, &asbd) == noErr {
    print("Output ASBD: \(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) ch, bits: \(asbd.mBitsPerChannel)")
}
