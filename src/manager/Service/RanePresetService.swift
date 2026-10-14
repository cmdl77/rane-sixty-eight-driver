/* SPDX-License-Identifier: MIT */
/* RanePresetService.swift - Management, persistence and application of mixer presets */

import Cocoa

public struct RaneMixerPreset: Codable, Equatable {
    public var name: String
    public var description: String?
    public var createdAt: Date?

    // Tab 1: Hardware Controls & Monitor
    public var buttonBacklight: Bool
    public var lcdContrast: Int          // 0..127 (default 64 = 50%)
    public var lowToneVal: Int           // 0..127 (default 64 = 0.0 dB)
    public var highToneVal: Int          // 0..127 (default 64 = 0.0 dB)

    // Tab 1: USB Audio Routing & Latency
    public var usb6RecordSource: Int     // 0: Main Mix, 1: Mic 1, 2: Mic 2
    public var bufferSizeIndex: Int      // 0..6 (default 2 = 5 ms)
    public var midiControlPoint: Int     // 0: USB Port A, 1: USB Port B

    // Tab 2: PGM Channels 1–4
    public var phonoSensitivities: [Int] // 4 values, 0..15 (default [5,5,5,5] = 5.0 mV)
    public var filterResonances: [Int]   // 4 values, 0: Low, 1: High (default [0,0,0,0])
    public var recordSources: [Int]      // 4 values, 0: PH/CD, 1: Post, 2: AUX (default [1,1,1,1])

    // Tab 3: MIDI Configuration
    public var midiOutChannel: Int       // 1..16 or 17 (OFF), default 1
    public var midiInChannel: Int        // 1..16 or 17 (OFF), default 17 (OFF)

    // Controller Manager: In Mappings & Out Mappings
    public var midiMappings: [String: MidiMapping]?
    public var midiOutMappings: [String: MidiOutMapping]?

    public init(
        name: String,
        description: String? = nil,
        createdAt: Date? = Date(),
        buttonBacklight: Bool = true,
        lcdContrast: Int = 64,
        lowToneVal: Int = 64,
        highToneVal: Int = 64,
        usb6RecordSource: Int = 0,
        bufferSizeIndex: Int = 2,
        midiControlPoint: Int = 0,
        phonoSensitivities: [Int] = [5, 5, 5, 5],
        filterResonances: [Int] = [0, 0, 0, 0],
        recordSources: [Int] = [1, 1, 1, 1],
        midiOutChannel: Int = 1,
        midiInChannel: Int = 17,
        midiMappings: [String: MidiMapping]? = nil,
        midiOutMappings: [String: MidiOutMapping]? = nil
    ) {
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.buttonBacklight = buttonBacklight
        self.lcdContrast = lcdContrast
        self.lowToneVal = lowToneVal
        self.highToneVal = highToneVal
        self.usb6RecordSource = usb6RecordSource
        self.bufferSizeIndex = bufferSizeIndex
        self.midiControlPoint = midiControlPoint
        self.phonoSensitivities = phonoSensitivities
        self.filterResonances = filterResonances
        self.recordSources = recordSources
        self.midiOutChannel = midiOutChannel
        self.midiInChannel = midiInChannel
        self.midiMappings = midiMappings
        self.midiOutMappings = midiOutMappings
    }
}

public class RanePresetService {
    public static let shared = RanePresetService()

    private let fileManager = FileManager.default

    public var presetsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RaneDriver/Presets", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    // MARK: - Factory Presets
    public static let factoryClubDefault = RaneMixerPreset(
        name: Localization.tr(en: "Club Standard (Default)", de: "Club Standard (Standard)"),
        description: Localization.tr(en: "Balanced tone, 5ms latency, post-fader USB record", de: "Ausgewogener Klang, 5ms Latenz, Post-Fader USB-Aufnahme"),
        buttonBacklight: true,
        lcdContrast: 64,
        lowToneVal: 64,
        highToneVal: 64,
        usb6RecordSource: 0,
        bufferSizeIndex: 2, // 5 ms
        midiControlPoint: 0, // Port A
        phonoSensitivities: [5, 5, 5, 5], // 5.0 mV
        filterResonances: [0, 0, 0, 0], // Low
        recordSources: [1, 1, 1, 1], // Post Fader
        midiOutChannel: 1,
        midiInChannel: 17
    )

    public static let factoryDvsVinyl = RaneMixerPreset(
        name: Localization.tr(en: "DVS & Timecode (Low Latency)", de: "DVS & Timecode (Geringe Latenz)"),
        description: Localization.tr(en: "2ms buffer, +9dB high phono sensitivity, direct PH/CD routing", de: "2ms Puffer, +9dB Phono-Verstärkung, direktes PH/CD Routing für Timecode"),
        buttonBacklight: true,
        lcdContrast: 64,
        lowToneVal: 64,
        highToneVal: 64,
        usb6RecordSource: 0,
        bufferSizeIndex: 1, // 2 ms
        midiControlPoint: 0,
        phonoSensitivities: [2, 2, 2, 2], // 3.5 mV (+9.1 dB)
        filterResonances: [0, 0, 0, 0],
        recordSources: [0, 0, 0, 0], // Direct PH/CD for software timecode
        midiOutChannel: 1,
        midiInChannel: 17
    )

    public static let factoryRecording = RaneMixerPreset(
        name: Localization.tr(en: "Live Recording & Streaming", de: "Live-Aufnahme & Streaming"),
        description: Localization.tr(en: "8ms safe buffer, Main Mix on USB-6, tone boost", de: "8ms stabiler Puffer, Main Mix auf USB-6, dezenter Tone-Boost"),
        buttonBacklight: true,
        lcdContrast: 75,
        lowToneVal: 74, // +1.0 dB
        highToneVal: 74, // +1.0 dB
        usb6RecordSource: 0, // Main Mix
        bufferSizeIndex: 3, // 8 ms
        midiControlPoint: 0,
        phonoSensitivities: [5, 5, 5, 5],
        filterResonances: [0, 0, 0, 0],
        recordSources: [1, 1, 1, 1], // Post Fader
        midiOutChannel: 1,
        midiInChannel: 17
    )

    public static let factoryScratchBattle = RaneMixerPreset(
        name: Localization.tr(en: "Turntablist & Scratch Battle", de: "Turntablist & Scratch Battle"),
        description: Localization.tr(en: "1ms ultra low latency, high filter resonance for sharp cuts", de: "1ms Ultra-Low Latency, hohe Filter-Resonanz für messerscharfe Cuts"),
        buttonBacklight: true,
        lcdContrast: 64,
        lowToneVal: 64,
        highToneVal: 64,
        usb6RecordSource: 0,
        bufferSizeIndex: 0, // 1 ms
        midiControlPoint: 0,
        phonoSensitivities: [5, 5, 5, 5],
        filterResonances: [1, 1, 1, 1], // High Resonance
        recordSources: [1, 1, 1, 1],
        midiOutChannel: 1,
        midiInChannel: 17
    )

    public var factoryPresets: [RaneMixerPreset] {
        return [
            RanePresetService.factoryClubDefault,
            RanePresetService.factoryDvsVinyl,
            RanePresetService.factoryRecording,
            RanePresetService.factoryScratchBattle
        ]
    }

    // MARK: - User Presets
    public func loadUserPresets() -> [RaneMixerPreset] {
        let dir = presetsDirectory
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var presets: [RaneMixerPreset] = []
        for file in files where file.pathExtension.lowercased() == "ranepreset" || file.pathExtension.lowercased() == "json" {
            if let preset = try? loadPreset(from: file) {
                presets.append(preset)
            }
        }
        return presets.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    public func saveUserPreset(_ preset: RaneMixerPreset) throws -> URL {
        let safeName = preset.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fileUrl = presetsDirectory.appendingPathComponent("\(safeName).ranepreset")
        try savePreset(preset, to: fileUrl)
        return fileUrl
    }

    public func savePreset(_ preset: RaneMixerPreset, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomic)
    }

    public func loadPreset(from url: URL) throws -> RaneMixerPreset {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RaneMixerPreset.self, from: data)
    }
}
