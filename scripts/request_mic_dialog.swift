import Cocoa
import AVFoundation

let status = AVCaptureDevice.authorizationStatus(for: .audio)
print("Current status: \(status.rawValue)")

if status == .notDetermined {
    let sema = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        print("Request response: granted=\(granted)")
        sema.signal()
    }
    _ = sema.wait(timeout: .now() + 10.0)
} else {
    print("Status already determined or blocked")
}
