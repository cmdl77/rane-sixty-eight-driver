/* SPDX-License-Identifier: MIT */
/* LiveMidiTab.swift - Tab 3: MIDI channel routing and live event monitor */

import Cocoa

extension MainWindowController {
    func buildMidiPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 10
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let secHeader = createSectionHeader(title: Localization.tr(en: "CoreMIDI Channel Configuration", de: "CoreMIDI Kanal-Konfiguration"))
        page.addArrangedSubview(secHeader)
        secHeader.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let configStack = NSStackView()
        configStack.orientation = .horizontal
        configStack.spacing = 32

        let outStack = NSStackView()
        outStack.orientation = .horizontal
        outStack.spacing = 10
        let outLbl = NSTextField(labelWithString: Localization.tr(en: "MIDI Out Channel:", de: "MIDI Out Kanal:"))
        outLbl.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let ch1Title = Localization.tr(en: "Channel 1", de: "Kanal 1")
        midiOutPopup = NSPopUpButton(title: ch1Title, target: self, action: #selector(onMidiChannelChanged))
        var midiChs = (1...16).map { Localization.tr(en: "Channel \($0)", de: "Kanal \($0)") }
        let offTitle = Localization.tr(en: "OFF (Disabled)", de: "OFF (Aus)")
        midiChs.append(offTitle)
        midiOutPopup.addItems(withTitles: midiChs)
        midiOutPopup.selectItem(at: 0)
        outStack.addArrangedSubview(outLbl)
        outStack.addArrangedSubview(midiOutPopup)

        let inStack = NSStackView()
        inStack.orientation = .horizontal
        inStack.spacing = 10
        let inLbl = NSTextField(labelWithString: Localization.tr(en: "MIDI In Channel:", de: "MIDI In Kanal:"))
        inLbl.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        midiInPopup = NSPopUpButton(title: offTitle, target: self, action: #selector(onMidiChannelChanged))
        midiInPopup.addItems(withTitles: midiChs)
        midiInPopup.selectItem(withTitle: offTitle)
        inStack.addArrangedSubview(inLbl)
        inStack.addArrangedSubview(midiInPopup)

        configStack.addArrangedSubview(outStack)
        configStack.addArrangedSubview(inStack)

        let topCard = configStack.wrapInDualTierSectionCard(
            cardCornerRadius: 10,
            cardPadding: NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16),
            insetPadding: NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        )
        page.addArrangedSubview(topCard)
        topCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        // Live Monitor Section
        let monHeader = createSectionHeader(title: Localization.tr(en: "Live MIDI Event Stream (Bidirectional)", de: "Live MIDI Event Stream (Bidirektional)"))
        page.addArrangedSubview(monHeader)
        monHeader.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        midiLogScrollView = scroll

        let contentSize = scroll.contentSize
        midiLogTextView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        midiLogTextView.minSize = NSSize(width: 0.0, height: contentSize.height)
        midiLogTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        midiLogTextView.isVerticallyResizable = true
        midiLogTextView.isHorizontallyResizable = false
        midiLogTextView.autoresizingMask = [.width]
        midiLogTextView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        midiLogTextView.textContainer?.widthTracksTextView = true
        midiLogTextView.isEditable = false
        midiLogTextView.isSelectable = true
        midiLogTextView.backgroundColor = NSColor(red: 0.10, green: 0.105, blue: 0.12, alpha: 1.0)
        midiLogTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        midiLogTextView.textColor = NSColor(white: 0.90, alpha: 1.0)
        scroll.documentView = midiLogTextView

        let innerScrollCard = scroll.wrapInCard(
            cornerRadius: 8,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.10, green: 0.105, blue: 0.12, alpha: 1.0),
            padding: NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        )
        let scrollCard = innerScrollCard.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        )
        page.addArrangedSubview(scrollCard)
        scrollCard.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        page.addArrangedSubview(bottomSpacer)

        return page
    }

    // MARK: - Action Handlers (Tab 3)
    @objc func onMidiChannelChanged() {
        let outCh = midiOutPopup.indexOfSelectedItem + 1
        let inCh = midiInPopup.indexOfSelectedItem + 1
        appendMidiLog("MIDI Kanäle aktualisiert -> Out: \(outCh), In: \(inCh)")
    }
}
