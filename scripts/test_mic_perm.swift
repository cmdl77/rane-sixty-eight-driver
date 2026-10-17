import Foundation
import AVFoundation

let status = AVCaptureDevice.authorizationStatus(for: .audio)
print("AVCaptureDevice authorizationStatus for audio: \(status.rawValue)")
// 0: notDetermined, 1: restricted, 2: denied, 3: authorized
