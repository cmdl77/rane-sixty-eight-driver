/* SPDX-License-Identifier: MIT */
/* CpuBadgeView.swift - Compact real-time CPU utilization badge with micro meter bar */

import Cocoa

final class CpuBadgeView: NSView {
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "CPU  0.0%")
    private let barTrack = NSView()
    private let barFill = NSView()
    private var fillWidthConstraint: NSLayoutConstraint?
    private var trackingArea: NSTrackingArea?

    var onClick: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if let img = NSImage(systemSymbolName: "cpu", accessibilityDescription: "CPU") {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        }
        iconView.contentTintColor = NSColor.systemGreen
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        stack.addArrangedSubview(iconView)

        textLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .bold)
        textLabel.textColor = NSColor(white: 0.95, alpha: 1.0)
        textLabel.alignment = .left
        textLabel.isBezeled = false
        textLabel.drawsBackground = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        stack.addArrangedSubview(textLabel)

        barTrack.wantsLayer = true
        barTrack.layer?.cornerRadius = 2
        barTrack.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.85).cgColor
        barTrack.translatesAutoresizingMaskIntoConstraints = false
        barTrack.widthAnchor.constraint(equalToConstant: 24).isActive = true
        barTrack.heightAnchor.constraint(equalToConstant: 4).isActive = true

        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 2
        barFill.layer?.backgroundColor = NSColor.systemGreen.cgColor
        barFill.translatesAutoresizingMaskIntoConstraints = false
        barTrack.addSubview(barFill)

        NSLayoutConstraint.activate([
            barFill.leadingAnchor.constraint(equalTo: barTrack.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: barTrack.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: barTrack.bottomAnchor),
        ])
        fillWidthConstraint = barFill.widthAnchor.constraint(equalToConstant: 2)
        fillWidthConstraint?.isActive = true

        stack.addArrangedSubview(barTrack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22)
        ])

        updateTooltip()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onClick?()
        }
    }

    func updateTooltip() {
        toolTip = Localization.tr(
            en: "System CPU Load. Click to switch to System Status tab.",
            de: "System CPU-Auslastung. Klicken, um zum System Status Tab zu wechseln."
        )
    }

    func update(percent: Double) {
        let clamped = min(max(percent, 0.0), 100.0)
        textLabel.stringValue = String(format: "CPU %4.1f%%", clamped)

        let color: NSColor
        if clamped < 50.0 {
            color = NSColor.systemGreen
        } else if clamped < 80.0 {
            color = NSColor.systemOrange
        } else {
            color = NSColor.systemRed
        }

        iconView.contentTintColor = color
        barFill.layer?.backgroundColor = color.cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor

        let trackWidth: CGFloat = 24.0
        let fillWidth = max(2.0, trackWidth * CGFloat(clamped / 100.0))
        fillWidthConstraint?.constant = fillWidth
    }
}
