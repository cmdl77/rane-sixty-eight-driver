/* SPDX-License-Identifier: MIT */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>

int main() {
    printf("=== Rane Sixty-Eight USB Pipe Inspector ===\n");

    CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matchingDict) {
        printf("Failed to create matching dictionary.\n");
        return 1;
    }

    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iter) != kIOReturnSuccess) {
        printf("IOServiceGetMatchingServices failed.\n");
        return 1;
    }

    io_service_t deviceService = IO_OBJECT_NULL;
    IOUSBDeviceInterface942** dev = nullptr;

    while ((deviceService = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface** plugIn = nullptr;
        SInt32 score = 0;
        IOReturn kr = IOCreatePlugInInterfaceForService(
            deviceService, kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugIn, &score);

        if (kr == kIOReturnSuccess && plugIn) {
            kr = (*plugIn)->QueryInterface(
                plugIn, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (LPVOID*)&dev);
            (*plugIn)->Release(plugIn);

            if (kr == kIOReturnSuccess && dev) {
                UInt16 vendor = 0, product = 0;
                (*dev)->GetDeviceVendor(dev, &vendor);
                (*dev)->GetDeviceProduct(dev, &product);

                if (vendor == 0x1CC5 || vendor == 0x13E5 || vendor == 0x29E2) {
                    printf("Found Rane Device: VID 0x%04X, PID 0x%04X\n", vendor, product);
                    break;
                }
                (*dev)->Release(dev);
                dev = nullptr;
            }
        }
        IOObjectRelease(deviceService);
    }
    IOObjectRelease(iter);

    if (!dev) {
        printf("No Rane Sixty-Eight device found on USB bus.\n");
        return 1;
    }

    IOReturn kr = (*dev)->USBDeviceOpen(dev);
    if (kr != kIOReturnSuccess) {
        printf("USBDeviceOpen failed: 0x%08x\n", kr);
        (*dev)->Release(dev);
        return 1;
    }

    kr = (*dev)->SetConfiguration(dev, 1);
    printf("SetConfiguration(1) kr: 0x%08x\n", kr);

    IOUSBFindInterfaceRequest request = {
        .bInterfaceClass    = kIOUSBFindInterfaceDontCare,
        .bInterfaceSubClass = kIOUSBFindInterfaceDontCare,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting  = kIOUSBFindInterfaceDontCare
    };

    io_iterator_t intfIter = IO_OBJECT_NULL;
    kr = (*dev)->CreateInterfaceIterator(dev, &request, &intfIter);
    if (kr != kIOReturnSuccess) {
        printf("CreateInterfaceIterator failed: 0x%08x\n", kr);
        (*dev)->USBDeviceClose(dev);
        (*dev)->Release(dev);
        return 1;
    }

    io_service_t intfService = IO_OBJECT_NULL;
    int intfIdx = 0;

    while ((intfService = IOIteratorNext(intfIter)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface** plugIn = nullptr;
        SInt32 score = 0;
        kr = IOCreatePlugInInterfaceForService(
            intfService, kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugIn, &score);
        IOObjectRelease(intfService);

        if (kr == kIOReturnSuccess && plugIn) {
            IOUSBInterfaceInterface942** intf = nullptr;
            kr = (*plugIn)->QueryInterface(
                plugIn, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID942), (LPVOID*)&intf);
            (*plugIn)->Release(plugIn);

            if (kr == kIOReturnSuccess && intf) {
                kr = (*intf)->USBInterfaceOpen(intf);
                printf("\n--- Interface %d (Open kr: 0x%08x) ---\n", intfIdx, kr);

                UInt8 numAlt = 0;
                // Try alternate settings 0, 1, 2...
                for (UInt8 alt = 0; alt <= 2; alt++) {
                    IOReturn altKr = (*intf)->SetAlternateInterface(intf, alt);
                    printf("  AltSetting %d -> SetAlternateInterface kr: 0x%08x\n", alt, altKr);

                    if (altKr == kIOReturnSuccess) {
                        UInt8 numPipes = 0;
                        (*intf)->GetNumEndpoints(intf, &numPipes);
                        printf("  AltSetting %d has %d pipes:\n", alt, numPipes);

                        for (UInt8 ref = 1; ref <= numPipes; ref++) {
                            UInt8 direction = 0, number = 0, transferType = 0, interval = 0;
                            UInt16 maxPkt = 0;
                            (*intf)->GetPipeProperties(intf, ref, &direction, &number, &transferType, &maxPkt, &interval);
                            const char* tTypeStr = "Unknown";
                            if (transferType == 0) tTypeStr = "Control";
                            else if (transferType == 1) tTypeStr = "Isochronous";
                            else if (transferType == 2) tTypeStr = "Bulk";
                            else if (transferType == 3) tTypeStr = "Interrupt";

                            printf("    PipeRef %d: EP 0x%02X (Dir: %s, Type: %s, MaxPkt: %d, Interval: %d)\n",
                                   ref, (direction << 7) | number,
                                   direction == kUSBOut ? "OUT" : "IN",
                                   tTypeStr, maxPkt, interval);
                        }
                    }
                }

                (*intf)->USBInterfaceClose(intf);
                (*intf)->Release(intf);
            }
        }
        intfIdx++;
    }

    IOObjectRelease(intfIter);
    (*dev)->USBDeviceClose(dev);
    (*dev)->Release(dev);
    printf("\nDone inspecting USB interfaces and pipes.\n");
    return 0;
}
