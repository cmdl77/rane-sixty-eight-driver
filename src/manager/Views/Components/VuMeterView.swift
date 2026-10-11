/* SPDX-License-Identifier: MIT */
/* VuMeterView.swift - High-performance horizontal slim VU meters for Rane Sixty-Eight 12 In / 10 Out */

import Cocoa

// MARK: - Single Horizontal LED Bar with Peak Hold & Clip
class HorizontalLedBarView: NSView {
    private let troughLayer = CALayer()
    private let barLayer = CAGradientLayer()
    private let holdLayer = CALayer()

    private var currentLevel: Float = 0.0
    private var currentHold: Float = 0.0
    private var isClipped: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 2

        troughLayer.backgroundColor = NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
        troughLayer.cornerRadius = 2
        layer?.addSublayer(troughLayer)

        // DJ LED gradient: Green (-48 to -6 dB) -> Amber (-6 to -1 dB) -> Red (clip)
        barLayer.colors = [
            NSColor(red: 0.13, green: 0.77, blue: 0.36, alpha: 1.0).cgColor, // Emerald Green
            NSColor(red: 0.13, green: 0.77, blue: 0.36, alpha: 1.0).cgColor,
            NSColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 1.0).cgColor, // Amber
            NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0).cgColor  // Red
        ]
        barLayer.locations = [0.0, 0.70, 0.88, 1.0]
        barLayer.startPoint = CGPoint(x: 0, y: 0.5)
        barLayer.endPoint = CGPoint(x: 1, y: 0.5)
        barLayer.cornerRadius = 2
        layer?.addSublayer(barLayer)

        holdLayer.backgroundColor = NSColor.white.cgColor
        holdLayer.cornerRadius = 0.5
        layer?.addSublayer(holdLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        troughLayer.frame = bounds
        updateBarFrames()
        CATransaction.commit()
    }

    func setLevel(linearPeak: Float, linearHold: Float, clipped: Bool) {
        // Convert linear peak (0.0 .. 1.0) to non-linear dB-like visual scale
        // A logarithmic response curve looks significantly more natural for audio meters
        let normalized = min(1.0, max(0.0, linearPeak))
        let visualLevel: Float = normalized > 0.001 ? pow(normalized, 0.45) : 0.0

        let normHold = min(1.0, max(0.0, linearHold))
        let visualHold: Float = normHold > 0.001 ? pow(normHold, 0.45) : 0.0

        if abs(visualLevel - currentLevel) < 0.005 && abs(visualHold - currentHold) < 0.005 && clipped == isClipped {
            return
        }

        currentLevel = visualLevel
        currentHold = visualHold
        isClipped = clipped

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateBarFrames()
        CATransaction.commit()
    }

    private func updateBarFrames() {
        let totalW = bounds.width
        let totalH = bounds.height
        let barW = totalW * CGFloat(currentLevel)
        barLayer.frame = CGRect(x: 0, y: 0, width: barW, height: totalH)

        if currentHold > 0.05 {
            let holdX = min(totalW - 2, max(0, totalW * CGFloat(currentHold) - 1.5))
            holdLayer.frame = CGRect(x: holdX, y: 0, width: 2, height: totalH)
            holdLayer.isHidden = false
            holdLayer.backgroundColor = isClipped ? NSColor.systemRed.cgColor : NSColor(white: 0.95, alpha: 0.9).cgColor
        } else {
            holdLayer.isHidden = true
        }
    }
}

// MARK: - Stereo Pair View (Horizontal Dual-Bar with Label)
class HorizontalStereoMeterView: NSView {
    let titleLabel: NSTextField
    let dbLabel: NSTextField
    let leftBar: HorizontalLedBarView
    let rightBar: HorizontalLedBarView

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        titleLabel.textColor = NSColor(white: 0.82, alpha: 1.0)
        titleLabel.alignment = .left

        dbLabel = NSTextField(labelWithString: "-∞")
        dbLabel.font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium)
        dbLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
        dbLabel.alignment = .right

        leftBar = HorizontalLedBarView()
        rightBar = HorizontalLedBarView()

        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 0.26, alpha: 0.50).cgColor
        layer?.backgroundColor = NSColor(red: 0.125, green: 0.129, blue: 0.145, alpha: 0.90).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.distribution = .fill
        topRow.spacing = 2
        topRow.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        dbLabel.setContentHuggingPriority(.required, for: .horizontal)
        topRow.addArrangedSubview(titleLabel)
        topRow.addArrangedSubview(dbLabel)

        let barStack = NSStackView()
        barStack.orientation = .vertical
        barStack.alignment = .width
        barStack.spacing = 2
        barStack.translatesAutoresizingMaskIntoConstraints = false

        leftBar.translatesAutoresizingMaskIntoConstraints = false
        leftBar.heightAnchor.constraint(equalToConstant: 4).isActive = true

        rightBar.translatesAutoresizingMaskIntoConstraints = false
        rightBar.heightAnchor.constraint(equalToConstant: 4).isActive = true

        barStack.addArrangedSubview(leftBar)
        barStack.addArrangedSubview(rightBar)

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 3
        mainStack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(topRow)
        mainStack.addArrangedSubview(barStack)
        topRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -16).isActive = true
        barStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -16).isActive = true

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func updateLevels(leftPeak: Float, rightPeak: Float, leftHold: Float, rightHold: Float, leftClip: Bool, rightClip: Bool) {
        leftBar.setLevel(linearPeak: leftPeak, linearHold: leftHold, clipped: leftClip)
        rightBar.setLevel(linearPeak: rightPeak, linearHold: rightHold, clipped: rightClip)

        let targetText: String
        let targetColor: NSColor

        let maxPeak = max(leftPeak, rightPeak)
        if leftClip || rightClip {
            targetText = "CLIP"
            targetColor = NSColor.systemRed
        } else if maxPeak > 0.001 {
            let dB = 20.0 * log10(Double(maxPeak))
            if dB >= -0.5 {
                targetText = "0 dB"
                targetColor = NSColor.systemYellow
            } else {
                targetText = String(format: "%.0f dB", dB)
                targetColor = NSColor(white: 0.55, alpha: 1.0)
            }
        } else {
            targetText = "-∞"
            targetColor = NSColor(white: 0.40, alpha: 1.0)
        }

        if dbLabel.stringValue != targetText {
            dbLabel.stringValue = targetText
            dbLabel.textColor = targetColor
        }
    }
}

// MARK: - Full 22-Channel Horizontal Rack (12 In + 10 Out Grouped)
class RaneIOMonitorBarView: NSView {
    // 6 Stereo Input Meters (Pairs 1-2, 3-4, 5-6, 7-8, 9-10, 11-12)
    let inMeters: [HorizontalStereoMeterView]

    // 5 Stereo Output Meters (Pairs 1-2, 3-4, 5-6, 7-8, 9-10)
    let outMeters: [HorizontalStereoMeterView]

    // Status indicator
    let statusBadge: NSTextField

    override init(frame frameRect: NSRect) {
        // 6 Stereo Record Inputs: PGM 1, PGM 2, PGM 3, PGM 4, FlexFX Send, Main/Mic
        let inNames = [
            "PGM 1", "PGM 2", "PGM 3", "PGM 4",
            "FLEXFX SEND", "MAIN / MIC"
        ]
        inMeters = inNames.map { HorizontalStereoMeterView(title: $0) }

        // 5 Stereo Playback Outputs: Deck 1, Deck 2, Deck 3, Deck 4, FlexFX Return
        let outNames = [
            "DECK 1 (PGM 1/2)", "DECK 2 (PGM 1/2)", "DECK 3 (PGM 3/4)", "DECK 4 (PGM 3/4)",
            "FLEXFX RETURN"
        ]
        outMeters = outNames.map { HorizontalStereoMeterView(title: $0) }

        statusBadge = NSTextField(labelWithString: Localization.tr(en: "● Audio Idle", de: "● Audio Standby"))
        super.init(frame: frameRect)
        setupUI()
        connectService()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 0.28, alpha: 0.45).cgColor
        layer?.backgroundColor = NSColor(red: 0.176, green: 0.180, blue: 0.200, alpha: 1.0).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // 1. Header Bar
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let meterIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil) {
            meterIcon.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        }
        meterIcon.contentTintColor = NSColor.systemTeal
        headerRow.addArrangedSubview(meterIcon)

        let headerTitle = NSTextField(labelWithString: Localization.tr(en: "LIVE AUDIO I/O MONITOR", de: "LIVE AUDIO PEGELANZEIGE"))
        headerTitle.font = NSFont.systemFont(ofSize: 10.5, weight: .black)
        headerTitle.textColor = NSColor(white: 0.90, alpha: 1.0)
        headerRow.addArrangedSubview(headerTitle)

        let headerSub = NSTextField(labelWithString: Localization.tr(en: "22 CHANNELS (10 OUT / 12 IN)", de: "22 KANÄLE (10 OUT / 12 IN)"))
        headerSub.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        headerSub.textColor = NSColor(white: 0.55, alpha: 1.0)
        headerRow.addArrangedSubview(headerSub)

        let gap = NSView()
        gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(gap)

        statusBadge.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        statusBadge.textColor = NSColor(white: 0.55, alpha: 1.0)
        statusBadge.wantsLayer = true
        statusBadge.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.4).cgColor
        statusBadge.layer?.cornerRadius = 4
        headerRow.addArrangedSubview(statusBadge)

        rootStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        // 2. OUTPUTS SECTION (Top Row - 5 Stereo Pairs)
        let outRowHeader = NSStackView()
        outRowHeader.orientation = .horizontal
        outRowHeader.alignment = .centerY
        outRowHeader.spacing = 6
        let outTag = NSTextField(labelWithString: Localization.tr(en: "  OUTPUTS (USB PLAYBACK) – 10 CHANNELS (5 PAIRS)  ", de: "  AUSGÄNGE (PLAYBACK) – 10 KANÄLE (5 STEREO-PAARE)  "))
        outTag.font = NSFont.boldSystemFont(ofSize: 9.0)
        outTag.textColor = NSColor.systemBlue
        outTag.wantsLayer = true
        outTag.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
        outTag.layer?.cornerRadius = 3
        outRowHeader.addArrangedSubview(outTag)
        rootStack.addArrangedSubview(outRowHeader)

        let outGrid = NSStackView()
        outGrid.orientation = .horizontal
        outGrid.distribution = .fillEqually
        outGrid.spacing = 8
        outGrid.translatesAutoresizingMaskIntoConstraints = false
        for m in outMeters {
            outGrid.addArrangedSubview(m)
        }
        rootStack.addArrangedSubview(outGrid)
        outGrid.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        // 3. Thin separator
        let sep = NSBox()
        sep.boxType = .separator
        rootStack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        // 4. INPUTS SECTION (Bottom Row - 6 Stereo Pairs)
        let inRowHeader = NSStackView()
        inRowHeader.orientation = .horizontal
        inRowHeader.alignment = .centerY
        inRowHeader.spacing = 6
        let inTag = NSTextField(labelWithString: Localization.tr(en: "  INPUTS (USB RECORD) – 12 CHANNELS (6 PAIRS)  ", de: "  EINGÄNGE (RECORD) – 12 KANÄLE (6 STEREO-PAARE)  "))
        inTag.font = NSFont.boldSystemFont(ofSize: 9.0)
        inTag.textColor = NSColor.systemGreen
        inTag.wantsLayer = true
        inTag.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
        inTag.layer?.cornerRadius = 3
        inRowHeader.addArrangedSubview(inTag)
        rootStack.addArrangedSubview(inRowHeader)

        let inGrid = NSStackView()
        inGrid.orientation = .horizontal
        inGrid.distribution = .fillEqually
        inGrid.spacing = 8
        inGrid.translatesAutoresizingMaskIntoConstraints = false
        for m in inMeters {
            inGrid.addArrangedSubview(m)
        }
        rootStack.addArrangedSubview(inGrid)
        inGrid.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
    }

    private func connectService() {
        RaneMeterService.shared.onMetersUpdated = { [weak self] svc in
            self?.updateFromService(svc)
        }
    }

    private func updateFromService(_ svc: RaneMeterService) {
        if svc.isStreamingActive {
            let targetText = Localization.tr(
                en: "  ● Active (\(svc.sampleRate / 1000) kHz / \(svc.bufferFrameSize)f)  ",
                de: "  ● Aktiv (\(svc.sampleRate / 1000) kHz / \(svc.bufferFrameSize)f)  "
            )
            if statusBadge.stringValue != targetText {
                statusBadge.stringValue = targetText
                statusBadge.textColor = NSColor.systemGreen
                statusBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
            }
        } else {
            let targetText = Localization.tr(en: "  ● Idle (Standby)  ", de: "  ● Standby  ")
            if statusBadge.stringValue != targetText {
                statusBadge.stringValue = targetText
                statusBadge.textColor = NSColor(white: 0.55, alpha: 1.0)
                statusBadge.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.4).cgColor
            }
        }

        // Update 6 Stereo Input Pairs (12 channels)
        for pair in 0..<6 {
            let leftIdx = pair * 2
            let rightIdx = pair * 2 + 1
            if rightIdx < svc.inPeaks.count {
                inMeters[pair].updateLevels(
                    leftPeak: svc.inPeaks[leftIdx],
                    rightPeak: svc.inPeaks[rightIdx],
                    leftHold: svc.inHold[leftIdx],
                    rightHold: svc.inHold[rightIdx],
                    leftClip: svc.inClips[leftIdx],
                    rightClip: svc.inClips[rightIdx]
                )
            }
        }

        // Update 5 Stereo Output Pairs (10 channels)
        for pair in 0..<5 {
            let leftIdx = pair * 2
            let rightIdx = pair * 2 + 1
            if rightIdx < svc.outPeaks.count {
                outMeters[pair].updateLevels(
                    leftPeak: svc.outPeaks[leftIdx],
                    rightPeak: svc.outPeaks[rightIdx],
                    leftHold: svc.outHold[leftIdx],
                    rightHold: svc.outHold[rightIdx],
                    leftClip: svc.outClips[leftIdx],
                    rightClip: svc.outClips[rightIdx]
                )
            }
        }
    }
}
