#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>

int main() {
    CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    io_iterator_t iter;
    IOServiceGetMatchingServices(0, matchingDict, &iter);
    io_service_t device;
    while ((device = IOIteratorNext(iter))) {
        IOCFPlugInInterface **plugInInterface = NULL;
        SInt32 score;
        IOCreatePlugInInterfaceForService(device, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
        if (plugInInterface) {
            IOUSBDeviceInterface **dev = NULL;
            (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*)&dev);
            (*plugInInterface)->Release(plugInInterface);
            if (dev) {
                UInt16 vendor, product;
                (*dev)->GetDeviceVendor(dev, &vendor);
                (*dev)->GetDeviceProduct(dev, &product);
                if (vendor == 0x1cc5 && product == 0x0004) {
                    printf("Found Rane 68!\n");
                    IOUSBConfigurationDescriptorPtr conf;
                    (*dev)->GetConfigurationDescriptorPtr(dev, 0, &conf);
                    uint8_t* p = (uint8_t*)conf;
                    uint16_t total = conf->wTotalLength;
                    printf("Total Length: %d\n", total);
                    for (int i=0; i<total; ) {
                        uint8_t len = p[i];
                        uint8_t type = p[i+1];
                        printf("Desc Type %02X Len %d: ", type, len);
                        for(int j=0; j<len; j++) printf("%02X ", p[i+j]);
                        printf("\n");
                        i += len;
                        if (len == 0) break;
                    }
                }
                (*dev)->Release(dev);
            }
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(iter);
    return 0;
}
