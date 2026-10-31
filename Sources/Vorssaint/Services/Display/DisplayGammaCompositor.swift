// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import os

/// The one writer of display gamma curves in this app.
///
/// Software dimming and the colour filter both shape the same transfer table,
/// and macOS keeps only the last table written. Two writers that each start
/// from the clean curve undo each other on every write, which is exactly what
/// running another colour app beside this one looks like: a dim that holds
/// while its slider moves and is gone the moment something else writes. So
/// every factor lands here and is multiplied onto the display's own curve in
/// a single write.
///
/// Thread safe: brightness calls in from its work queue, the colour filter
/// from the main thread.
final class DisplayGammaCompositor {
    static let shared = DisplayGammaCompositor()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display")

    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var count: UInt32
        /// Which monitor the curve was read from. Display numbers are handed
        /// out again after a reconnection, so this is what stops one
        /// monitor's curve from ever being written to another.
        var fingerprint: String
    }

    private let lock = NSLock()
    /// The unmodified curve of each display this app has shaped, captured
    /// before the first change so restoring is exact.
    private var baselines: [CGDirectDisplayID: GammaTable] = [:]
    /// How many untouched curves are worth keeping for displays that are not
    /// attached right now. A curve is a few kilobytes and keeping it is what
    /// makes a reconnection safe, so the cap only exists so a long session
    /// full of different monitors cannot grow without bound.
    private static let rememberedBaselines = 16
    /// Software dim factor per display, below one only.
    private var dims: [CGDirectDisplayID: Float] = [:]
    private var color = DisplayColorGains.neutral
    private var colorDisplays = Set<CGDirectDisplayID>()
    /// Displays whose live curve is this app's, not their own, so it is never
    /// read back as a baseline.
    private var modified = Set<CGDirectDisplayID>()

    private init() {}

    /// Identifies the physical monitor behind a display number.
    static func fingerprint(_ id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id))"
    }

    /// Reads the display's own curve unless this app is already shaping it.
    /// True when a usable baseline exists afterwards.
    @discardableResult
    func captureBaselineIfNeeded(_ id: CGDirectDisplayID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return captureLocked(id)
    }

    func isDimmed(_ id: CGDirectDisplayID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return dims[id] != nil
    }

    /// Sets one display's software dim; one or more lifts it.
    @discardableResult
    func setDim(_ value: Double, for id: CGDirectDisplayID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let baseline = baselines[id], baseline.fingerprint == Self.fingerprint(id) else {
            return false
        }
        let factor = BrightnessSupport.softwareDimFactor(for: value)
        if factor >= 0.999 { dims.removeValue(forKey: id) } else { dims[id] = factor }
        return writeLocked(id)
    }

    /// Writes the clean curve without forgetting the dim, for a display about
    /// to be reconfigured: it should come back clean and have the dim put
    /// back by the rebuild that follows.
    func writeBaseline(_ id: CGDirectDisplayID) {
        lock.lock()
        defer { lock.unlock() }
        guard let baseline = baselines[id], baseline.fingerprint == Self.fingerprint(id) else { return }
        CGSetDisplayTransferByTable(id, baseline.count, baseline.red, baseline.green, baseline.blue)
    }

    /// Lifts every software dim and leaves the colour filter in place.
    func clearDims() {
        lock.lock()
        defer { lock.unlock() }
        let affected = Array(dims.keys)
        dims = [:]
        for id in affected { writeLocked(id) }
        trimLocked()
    }

    /// Lays `gains` over every display in `displays`, and takes it off any
    /// display that had it and is not in the set any more.
    func setColor(_ gains: DisplayColorGains, displays: Set<CGDirectDisplayID>) {
        lock.lock()
        defer { lock.unlock() }
        let target = gains.isNeutral ? [] : displays
        let affected = colorDisplays.union(target)
        color = gains
        colorDisplays = target
        for id in affected {
            if target.contains(id) { captureLocked(id) }
            writeLocked(id)
        }
        trimLocked()
    }

    /// Writes every shaped curve again. Reconfigurations, wake and ColorSync
    /// put the clean curve back behind this app's back.
    func reassert() {
        lock.lock()
        defer { lock.unlock() }
        for id in modified { writeLocked(id) }
    }

    /// Forgets curves of displays long gone once more have piled up than any
    /// desk has monitors.
    func trimBaselines(keeping online: Set<CGDirectDisplayID>) {
        lock.lock()
        defer { lock.unlock() }
        guard baselines.count > Self.rememberedBaselines else { return }
        baselines = baselines.filter { online.contains($0.key) }
    }

    /// Puts every display's own curve back, for quitting.
    func restoreAll() {
        lock.lock()
        defer { lock.unlock() }
        for (id, baseline) in baselines where Self.fingerprint(id) == baseline.fingerprint {
            CGSetDisplayTransferByTable(id, baseline.count, baseline.red, baseline.green, baseline.blue)
            Self.log.log("restored gamma baseline for display \(id)")
        }
        baselines = [:]
        dims = [:]
        colorDisplays = []
        color = .neutral
        modified = []
    }

    // MARK: Locked helpers

    @discardableResult
    private func captureLocked(_ id: CGDirectDisplayID) -> Bool {
        let fingerprint = Self.fingerprint(id)
        // A curve is only read while the screen is still showing its own. Once
        // this app shapes it the live curve is a scaled copy, and reading that
        // back would take the dim as the new normal and darken the screen
        // again on every reconnection until it is black. A display this app
        // is not shaping is read again, so a colour profile the user changes
        // becomes what everything else scales from.
        if baselines[id]?.fingerprint == fingerprint, modified.contains(id) { return true }
        let capacity = 256
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = [CGGammaValue](repeating: 0, count: capacity)
        var blue = [CGGammaValue](repeating: 0, count: capacity)
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, UInt32(capacity), &red, &green, &blue,
                                          &sampleCount) == .success,
              sampleCount > 0 else {
            return baselines[id]?.fingerprint == fingerprint
        }
        let count = Int(min(sampleCount, UInt32(capacity)))
        baselines[id] = GammaTable(red: Array(red.prefix(count)),
                                   green: Array(green.prefix(count)),
                                   blue: Array(blue.prefix(count)),
                                   count: UInt32(count),
                                   fingerprint: fingerprint)
        Self.log.log("captured gamma baseline for display \(id) [\(fingerprint, privacy: .public)], peak \(red[count - 1])")
        return true
    }

    @discardableResult
    private func writeLocked(_ id: CGDirectDisplayID) -> Bool {
        guard let baseline = baselines[id], baseline.fingerprint == Self.fingerprint(id) else {
            return false
        }
        let dim = Double(dims[id] ?? 1)
        let gains = colorDisplays.contains(id) ? color : .neutral
        if dim >= 0.999, gains.isNeutral {
            let restored = CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                                       baseline.green, baseline.blue) == .success
            if restored { modified.remove(id) }
            return restored
        }
        let red = DisplayColorSupport.scaledTable(baseline.red, factor: dim * gains.red)
        let green = DisplayColorSupport.scaledTable(baseline.green, factor: dim * gains.green)
        let blue = DisplayColorSupport.scaledTable(baseline.blue, factor: dim * gains.blue)
        let applied = CGSetDisplayTransferByTable(id, baseline.count, red, green, blue) == .success
        if applied { modified.insert(id) }
        return applied
    }

    private func trimLocked() {
        // Nothing to trim against here; `trimBaselines` does it with the
        // online set. Dropping a curve this app still shapes would make the
        // next capture read the shaped curve back as clean.
        guard baselines.count > Self.rememberedBaselines else { return }
        let keep = modified.union(colorDisplays).union(dims.keys)
        baselines = baselines.filter { keep.contains($0.key) }
    }
}
