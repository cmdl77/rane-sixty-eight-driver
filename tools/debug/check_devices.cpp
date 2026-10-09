#include <CoreAudio/CoreAudio.h>
#include <iostream>
#include <vector>

int main() {
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    OSStatus err = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, nullptr, &size);
    if (err != noErr) {
        std::cout << "Error getting devices size: " << err << std::endl;
        return 1;
    }
    int numDevices = size / sizeof(AudioObjectID);
    std::cout << "Found " << numDevices << " Audio Devices in CoreAudio system graph:" << std::endl;

    std::vector<AudioObjectID> devices(numDevices);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, devices.data());

    for (int i = 0; i < numDevices; i++) {
        AudioObjectPropertyAddress nameAddr = {
            kAudioObjectPropertyName,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        CFStringRef name = nullptr;
        UInt32 nameSize = sizeof(CFStringRef);
        AudioObjectGetPropertyData(devices[i], &nameAddr, 0, nullptr, &nameSize, &name);

        AudioObjectPropertyAddress uidAddr = {
            kAudioDevicePropertyDeviceUID,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        CFStringRef uid = nullptr;
        UInt32 uidSize = sizeof(CFStringRef);
        AudioObjectGetPropertyData(devices[i], &uidAddr, 0, nullptr, &uidSize, &uid);

        char nameBuf[256] = {0};
        char uidBuf[256] = {0};
        if (name) CFStringGetCString(name, nameBuf, sizeof(nameBuf), kCFStringEncodingUTF8);
        if (uid) CFStringGetCString(uid, uidBuf, sizeof(uidBuf), kCFStringEncodingUTF8);

        std::cout << " Device [" << devices[i] << "]: Name=\"" << nameBuf << "\", UID=\"" << uidBuf << "\"" << std::endl;
        if (name) CFRelease(name);
        if (uid) CFRelease(uid);
    }
    return 0;
}
