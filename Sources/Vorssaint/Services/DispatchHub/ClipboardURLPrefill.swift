// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Reads the newest URL from the general pasteboard, tracking `changeCount` so
/// reopening the panel never re-fills an already-consumed link.
final class ClipboardURLPrefill {
    private var lastConsumedChangeCount: Int = -1

    func consumeNewURL() -> String? {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastConsumedChangeCount else { return nil }
        guard let raw = pb.string(forType: .string),
              let url = DispatchRouter.parseURL(raw) else {
            return nil
        }
        lastConsumedChangeCount = current
        return url.absoluteString
    }

    func readCurrentURL() -> String? {
        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: .string),
              let url = DispatchRouter.parseURL(raw) else {
            return nil
        }
        lastConsumedChangeCount = pb.changeCount
        return url.absoluteString
    }
}
