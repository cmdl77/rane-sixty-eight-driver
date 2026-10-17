import Foundation
import IOKit
import IOKit.hid

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x1CC5]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    let hex = bytes.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
    print("<<< IN REPORT len=\(reportLength) id=\(reportID): \(hex)...")
}

IOHIDManagerRegisterInputReportCallback(manager, reportCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

print("Listening for 5 seconds for mixer HID input reports...")
RunLoop.current.run(until: Date().addingTimeInterval(5.0))
print("Done.")
