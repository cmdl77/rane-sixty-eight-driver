/* SPDX-License-Identifier: MIT */
/* UIComponents.swift - Custom views and UI construction helpers */

import Cocoa

// MARK: - Card View Containers
class CardView: NSView {
    init(cornerRadius: CGFloat = 12, borderColor: NSColor = NSColor(white: 0.28, alpha: 0.45), fillColor: NSColor = NSColor(red: 0.176, green: 0.180, blue: 0.200, alpha: 1.0)) {
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.cornerRadius = cornerRadius
        self.layer?.masksToBounds = true
        self.layer?.borderWidth = 1.0
        self.layer?.borderColor = borderColor.cgColor
        self.layer?.backgroundColor = fillColor.cgColor
        self.translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension NSView {
    func wrapInCard(
        cornerRadius: CGFloat = 12,
        borderColor: NSColor = NSColor(white: 0.28, alpha: 0.45),
        fillColor: NSColor = NSColor(red: 0.176, green: 0.180, blue: 0.200, alpha: 1.0),
        padding: NSEdgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
    ) -> NSView {
        let card = CardView(cornerRadius: cornerRadius, borderColor: borderColor, fillColor: fillColor)
        self.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(self)
        NSLayoutConstraint.activate([
            self.topAnchor.constraint(equalTo: card.topAnchor, constant: padding.top),
            self.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding.bottom),
            self.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding.left),
            self.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding.right)
        ])
        return card
    }

    func wrapInInsetCard(
        cornerRadius: CGFloat = 10,
        padding: NSEdgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    ) -> NSView {
        return wrapInCard(
            cornerRadius: cornerRadius,
            borderColor: NSColor(white: 0.20, alpha: 0.50),
            fillColor: NSColor(red: 0.118, green: 0.122, blue: 0.137, alpha: 1.0),
            padding: padding
        )
    }
}

// MARK: - UI Builder Helpers for MainWindowController
extension MainWindowController {
    func createSectionHeader(title: String) -> NSView {
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: title.uppercased())
        lbl.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        lbl.textColor = NSColor(white: 0.55, alpha: 1.0)
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        header.addArrangedSubview(lbl)

        let div = NSBox()
        div.boxType = .separator
        div.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(div)

        return header
    }

    func createSliderRow(
        symbol: String,
        title: String,
        subtitle: String,
        slider: NSSlider,
        badge: NSTextField,
        minSymbol: String? = nil,
        maxSymbol: String? = nil
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        }
        iconView.contentTintColor = NSColor.white
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(iconView)

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = NSColor.white

        let subField = NSTextField(labelWithString: subtitle)
        subField.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subField.textColor = NSColor(white: 0.65, alpha: 1.0)

        labelStack.addArrangedSubview(titleField)
        labelStack.addArrangedSubview(subField)
        labelStack.widthAnchor.constraint(equalToConstant: 300).isActive = true
        row.addArrangedSubview(labelStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        if let ms = minSymbol, let img = NSImage(systemSymbolName: ms, accessibilityDescription: nil) {
            let iv = NSImageView()
            iv.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
            iv.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
            row.addArrangedSubview(iv)
        }

        slider.controlSize = .regular
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        row.addArrangedSubview(slider)

        if let ms = maxSymbol, let img = NSImage(systemSymbolName: ms, accessibilityDescription: nil) {
            let iv = NSImageView()
            iv.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            iv.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
            row.addArrangedSubview(iv)
        }

        badge.widthAnchor.constraint(equalToConstant: 72).isActive = true
        row.addArrangedSubview(badge)

        return row
    }

    func createSwitchRow(
        symbol: String,
        title: String,
        subtitle: String,
        toggle: NSSwitch
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        }
        iconView.contentTintColor = NSColor.white
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(iconView)

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = NSColor.white

        let subField = NSTextField(labelWithString: subtitle)
        subField.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subField.textColor = NSColor(white: 0.65, alpha: 1.0)

        labelStack.addArrangedSubview(titleField)
        labelStack.addArrangedSubview(subField)
        row.addArrangedSubview(labelStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        toggle.controlSize = .regular
        row.addArrangedSubview(toggle)

        return row
    }

    func createControlRow(
        symbol: String,
        title: String,
        subtitle: String,
        control: NSView
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        }
        iconView.contentTintColor = NSColor.white
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(iconView)

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = NSColor.white

        let subField = NSTextField(labelWithString: subtitle)
        subField.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subField.textColor = NSColor(white: 0.65, alpha: 1.0)

        labelStack.addArrangedSubview(titleField)
        labelStack.addArrangedSubview(subField)
        row.addArrangedSubview(labelStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        row.addArrangedSubview(control)
        return row
    }

    func createDivider() -> NSBox {
        let d = NSBox()
        d.boxType = .separator
        return d
    }

    func createBadge(text: String, isConnected: Bool) -> NSTextField {
        let badge = NSTextField(labelWithString: "  \(text)  ")
        badge.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        badge.textColor = isConnected ? NSColor.systemGreen : NSColor.systemRed
        badge.wantsLayer = true
        badge.layer?.backgroundColor = (isConnected ? NSColor.systemGreen : NSColor.systemRed).withAlphaComponent(0.15).cgColor
        badge.layer?.cornerRadius = 5
        return badge
    }

    func createValueBadge(text: String) -> NSTextField {
        let b = NSTextField(labelWithString: " \(text) ")
        b.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        b.textColor = NSColor(white: 0.95, alpha: 1.0)
        b.alignment = .center
        b.wantsLayer = true
        b.layer?.backgroundColor = NSColor(white: 0.24, alpha: 0.70).cgColor
        b.layer?.cornerRadius = 5
        return b
    }

    func createStatusRow(title: String, stack: NSStackView) -> NSTextField {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let valueField = NSTextField(labelWithString: Localization.tr(en: "Checking...", de: "Prüfe..."))
        valueField.font = NSFont.systemFont(ofSize: 12)

        row.addArrangedSubview(titleField)
        row.addArrangedSubview(valueField)
        stack.addArrangedSubview(row)
        return valueField
    }
}
