// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Floating full-screen-capable Large Type banner (⌘L in Command Bar),
/// ported from YTools `LargeTypeWindowController`. Press Esc or click close to dismiss.
@MainActor
final class LargeTypeWindowController: NSWindowController {
    static let shared = LargeTypeWindowController()

    private init() {
        let panel = LargeTypeFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let window, !trimmed.isEmpty else {
            NSSound.beep()
            return
        }
        window.contentViewController = NSHostingController(rootView: LargeTypeBannerView(text: trimmed))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class LargeTypeFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

private struct LargeTypeBannerView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.25)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(56)
                .frame(maxWidth: .infinity, minHeight: 380)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
