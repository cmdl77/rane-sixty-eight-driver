/* SPDX-License-Identifier: MIT */
/* FxDetailPopover.swift - Modern, graphical popover for effect modulation and parameter sound design */

import Cocoa

public class FxEffectButton: NSButton {
    public var onRightClick: (() -> Void)?

    public override func rightMouseDown(with event: NSEvent) {
        if let onRightClick = onRightClick {
            onRightClick()
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

public class FxDetailPopoverViewController: NSViewController {
    private let fxType: FlexFxType
    private var sliders: [(slider: NSSlider, badge: NSTextField, update: (Double) -> Void, format: (Double) -> String)] = []

    public init(fxType: FlexFxType) {
        self.fxType = fxType
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 260))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.98).cgColor
        root.layer?.cornerRadius = 10
        root.layer?.borderColor = accentColor.withAlphaComponent(0.6).cgColor
        root.layer?.borderWidth = 1.5

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])

        // Header: Title & Subtitle + Reset Button
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let titleLabel = NSTextField(labelWithString: "\(fxType.displayName) MODULATION")
        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .black)
        titleLabel.textColor = accentColor
        titleStack.addArrangedSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: effectSubtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        subtitleLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        titleStack.addArrangedSubview(subtitleLabel)

        headerRow.addArrangedSubview(titleStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(spacer)

        let resetBtn = NSButton(title: "Reset", target: self, action: #selector(onResetClicked))
        resetBtn.bezelStyle = .inline
        resetBtn.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        resetBtn.wantsLayer = true
        resetBtn.layer?.cornerRadius = 4
        resetBtn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.8).cgColor
        resetBtn.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
        headerRow.addArrangedSubview(resetBtn)

        mainStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        let div = NSBox()
        div.boxType = .separator
        mainStack.addArrangedSubview(div)
        div.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // Sliders Container
        let paramsStack = NSStackView()
        paramsStack.orientation = .vertical
        paramsStack.alignment = .leading
        paramsStack.spacing = 8
        paramsStack.translatesAutoresizingMaskIntoConstraints = false

        buildParameterRows(into: paramsStack)

        mainStack.addArrangedSubview(paramsStack)
        paramsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        self.view = root
    }

    private var accentColor: NSColor {
        switch fxType {
        case .filter:   return NSColor.systemOrange
        case .flanger:  return NSColor.systemPurple
        case .phaser:   return NSColor.systemTeal
        case .echo:     return NSColor.systemBlue
        case .dubDelay: return NSColor(red: 1.0, green: 0.80, blue: 0.20, alpha: 1.0) // Gold
        case .reverb:   return NSColor.systemGreen
        }
    }

    private var effectSubtitle: String {
        switch fxType {
        case .filter:   return "Resonant State-Variable SVF & LFO"
        case .flanger:  return "Stereo BBD Modulation & Delay"
        case .phaser:   return "4-Stage Cascade Phase Shifter"
        case .echo:     return "Digital Ping-Pong & High-Cut Dämpfung"
        case .dubDelay: return "Space Echo Röhren-Sättigung & Wow/Flutter"
        case .reverb:   return "Stereo Freeverb Raum & Dämpfung"
        }
    }

    private func buildParameterRows(into container: NSStackView) {
        let p = RaneFlexFxService.shared.fxParams

        switch fxType {
        case .dubDelay:
            addParamRow(name: "Tape Drive / Sättigung:", min: 0.0, max: 1.0, val: p.dubSaturation, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.dubSaturation = $0 })
            addParamRow(name: "High-Cut / Ton (Filter):", min: 500.0, max: 8000.0, val: p.dubHighCut, container: container,
                        format: { "\(Int($0)) Hz" },
                        update: { RaneFlexFxService.shared.fxParams.dubHighCut = $0 })
            addParamRow(name: "Wow & Flutter (Taumeln):", min: 0.0, max: 1.0, val: p.dubFlutter, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.dubFlutter = $0 })
            addParamRow(name: "Feedback Resonanz:", min: 0.0, max: 1.0, val: p.dubResonance, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.dubResonance = $0 })

        case .echo:
            addParamRow(name: "High-Cut Dämpfung:", min: 1000.0, max: 18000.0, val: p.echoHighCut, container: container,
                        format: { "\(Int($0)) Hz" },
                        update: { RaneFlexFxService.shared.fxParams.echoHighCut = $0 })
            addParamRow(name: "Ping-Pong Stereo:", min: 0.0, max: 1.0, val: p.echoPingPong, container: container,
                        format: { $0 < 0.1 ? "Mono" : "\($0 > 0.9 ? "Full" : "\(Int($0 * 100))%")" },
                        update: { RaneFlexFxService.shared.fxParams.echoPingPong = $0 })
            addParamRow(name: "Stereo Offset:", min: 0.0, max: 40.0, val: p.echoSpread, container: container,
                        format: { "\(Int($0)) ms" },
                        update: { RaneFlexFxService.shared.fxParams.echoSpread = $0 })

        case .reverb:
            addParamRow(name: "Raumgröße (Decay):", min: 0.1, max: 1.0, val: p.reverbRoomSize, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.reverbRoomSize = $0 })
            addParamRow(name: "Höhendämpfung:", min: 0.0, max: 1.0, val: p.reverbDamping, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.reverbDamping = $0 })
            addParamRow(name: "Stereo-Breite:", min: 0.0, max: 1.0, val: p.reverbWidth, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.reverbWidth = $0 })

        case .filter:
            addParamRow(name: "Cutoff Frequenz:", min: 100.0, max: 10000.0, val: p.filterCutoff, container: container,
                        format: { "\(Int($0)) Hz" },
                        update: { RaneFlexFxService.shared.fxParams.filterCutoff = $0 })
            addParamRow(name: "Resonanz (Q):", min: 0.5, max: 8.0, val: p.filterResonance, container: container,
                        format: { String(format: "%.1f Q", $0) },
                        update: { RaneFlexFxService.shared.fxParams.filterResonance = $0 })
            addParamRow(name: "LFO Modulation Rate:", min: 0.1, max: 6.0, val: p.filterLfoRate, container: container,
                        format: { String(format: "%.1f Hz", $0) },
                        update: { RaneFlexFxService.shared.fxParams.filterLfoRate = $0 })
            addParamRow(name: "LFO Tiefe:", min: 0.0, max: 1.0, val: p.filterLfoDepth, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.filterLfoDepth = $0 })

        case .flanger:
            addParamRow(name: "Modulation Speed:", min: 0.05, max: 4.0, val: p.flangerRate, container: container,
                        format: { String(format: "%.2f Hz", $0) },
                        update: { RaneFlexFxService.shared.fxParams.flangerRate = $0 })
            addParamRow(name: "Modulation Tiefe:", min: 0.0, max: 1.0, val: p.flangerDepth, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.flangerDepth = $0 })
            addParamRow(name: "Feedback Resonanz:", min: 0.0, max: 0.95, val: p.flangerFeedback, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.flangerFeedback = $0 })
            addParamRow(name: "Manual Delay Offset:", min: 0.5, max: 8.0, val: p.flangerManual, container: container,
                        format: { String(format: "%.1f ms", $0) },
                        update: { RaneFlexFxService.shared.fxParams.flangerManual = $0 })

        case .phaser:
            addParamRow(name: "Sweep Speed:", min: 0.05, max: 4.0, val: p.phaserRate, container: container,
                        format: { String(format: "%.2f Hz", $0) },
                        update: { RaneFlexFxService.shared.fxParams.phaserRate = $0 })
            addParamRow(name: "Sweep Tiefe:", min: 0.0, max: 1.0, val: p.phaserDepth, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.phaserDepth = $0 })
            addParamRow(name: "Feedback / Color:", min: 0.0, max: 0.90, val: p.phaserFeedback, container: container,
                        format: { "\(Int($0 * 100))%" },
                        update: { RaneFlexFxService.shared.fxParams.phaserFeedback = $0 })
            addParamRow(name: "Mittenfrequenz:", min: 200.0, max: 3000.0, val: p.phaserBaseFreq, container: container,
                        format: { "\(Int($0)) Hz" },
                        update: { RaneFlexFxService.shared.fxParams.phaserBaseFreq = $0 })
        }
    }

    private func addParamRow(name: String, min: Double, max: Double, val: Double, container: NSStackView,
                             format: @escaping (Double) -> String, update: @escaping (Double) -> Void) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let lbl = NSTextField(labelWithString: name)
        lbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = NSColor(white: 0.85, alpha: 1.0)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.widthAnchor.constraint(equalToConstant: 140).isActive = true
        row.addArrangedSubview(lbl)

        let slider = NSSlider(value: val, minValue: min, maxValue: max, target: self, action: #selector(onSliderChanged(_:)))
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 100).isActive = true
        row.addArrangedSubview(slider)

        let badge = NSTextField(labelWithString: format(val))
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        badge.textColor = accentColor
        badge.alignment = .right
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 54).isActive = true
        row.addArrangedSubview(badge)

        slider.tag = sliders.count
        sliders.append((slider, badge, update, format))

        container.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
    }

    @objc private func onSliderChanged(_ sender: NSSlider) {
        let idx = sender.tag
        guard idx < sliders.count else { return }
        let entry = sliders[idx]
        let val = sender.doubleValue
        entry.badge.stringValue = entry.format(val)
        entry.update(val)
    }

    @objc private func onResetClicked() {
        // Reset defaults for this effect
        let def = FxParameters()
        switch fxType {
        case .dubDelay:
            RaneFlexFxService.shared.fxParams.dubSaturation = def.dubSaturation
            RaneFlexFxService.shared.fxParams.dubHighCut = def.dubHighCut
            RaneFlexFxService.shared.fxParams.dubFlutter = def.dubFlutter
            RaneFlexFxService.shared.fxParams.dubResonance = def.dubResonance
        case .echo:
            RaneFlexFxService.shared.fxParams.echoHighCut = def.echoHighCut
            RaneFlexFxService.shared.fxParams.echoPingPong = def.echoPingPong
            RaneFlexFxService.shared.fxParams.echoSpread = def.echoSpread
        case .reverb:
            RaneFlexFxService.shared.fxParams.reverbRoomSize = def.reverbRoomSize
            RaneFlexFxService.shared.fxParams.reverbDamping = def.reverbDamping
            RaneFlexFxService.shared.fxParams.reverbWidth = def.reverbWidth
        case .filter:
            RaneFlexFxService.shared.fxParams.filterCutoff = def.filterCutoff
            RaneFlexFxService.shared.fxParams.filterResonance = def.filterResonance
            RaneFlexFxService.shared.fxParams.filterLfoRate = def.filterLfoRate
            RaneFlexFxService.shared.fxParams.filterLfoDepth = def.filterLfoDepth
        case .flanger:
            RaneFlexFxService.shared.fxParams.flangerRate = def.flangerRate
            RaneFlexFxService.shared.fxParams.flangerDepth = def.flangerDepth
            RaneFlexFxService.shared.fxParams.flangerFeedback = def.flangerFeedback
            RaneFlexFxService.shared.fxParams.flangerManual = def.flangerManual
        case .phaser:
            RaneFlexFxService.shared.fxParams.phaserRate = def.phaserRate
            RaneFlexFxService.shared.fxParams.phaserDepth = def.phaserDepth
            RaneFlexFxService.shared.fxParams.phaserFeedback = def.phaserFeedback
            RaneFlexFxService.shared.fxParams.phaserBaseFreq = def.phaserBaseFreq
        }

        // Reload slider values
        let p = RaneFlexFxService.shared.fxParams
        var vals: [Double] = []
        switch fxType {
        case .dubDelay: vals = [p.dubSaturation, p.dubHighCut, p.dubFlutter, p.dubResonance]
        case .echo:     vals = [p.echoHighCut, p.echoPingPong, p.echoSpread]
        case .reverb:   vals = [p.reverbRoomSize, p.reverbDamping, p.reverbWidth]
        case .filter:   vals = [p.filterCutoff, p.filterResonance, p.filterLfoRate, p.filterLfoDepth]
        case .flanger:  vals = [p.flangerRate, p.flangerDepth, p.flangerFeedback, p.flangerManual]
        case .phaser:   vals = [p.phaserRate, p.phaserDepth, p.phaserFeedback, p.phaserBaseFreq]
        }
        for (i, v) in vals.enumerated() where i < sliders.count {
            sliders[i].slider.doubleValue = v
            sliders[i].badge.stringValue = sliders[i].format(v)
        }
    }
}
