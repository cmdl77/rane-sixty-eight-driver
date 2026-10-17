import Foundation

let path = "/var/tmp/rane_audio_meters.bin"
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
    print("Cannot read meters bin")
    exit(1)
}

data.withUnsafeBytes { raw in
    guard let ptr = raw.baseAddress else { return }
    print("Magic: 0x\(String(format: "%08X", ptr.load(as: UInt32.self)))")
    print("SampleRate: \(ptr.load(fromByteOffset: 24, as: UInt32.self))")
    print("BufferSize: \(ptr.load(fromByteOffset: 28, as: UInt32.self))")
    print("IsRunning: \(ptr.load(fromByteOffset: 32, as: UInt32.self))")
    
    print("\n--- INPUT PEAKS (12 Ch) ---")
    for i in 0..<12 {
        let v = ptr.load(fromByteOffset: 48 + i * 4, as: Float.self)
        print("In Ch \(i+1): \(v)")
    }
    
    print("\n--- OUTPUT PEAKS (10 Ch) ---")
    for i in 0..<10 {
        let v = ptr.load(fromByteOffset: 96 + i * 4, as: Float.self)
        print("Out Ch \(i+1): \(v)")
    }
}
