// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Logical sections for menu bar icon hiding.
enum MenuBarHiderSection: String, CaseIterable, Hashable, Codable {
    case visible
    case hidden
    case alwaysHidden

    static func sanitized(_ raw: String?) -> MenuBarHiderSection {
        guard let raw, let value = MenuBarHiderSection(rawValue: raw) else { return .visible }
        return value
    }
}

/// Visual surface style for the floating hidden-items bar.
enum MenuBarHiderBarStyle: String, CaseIterable, Hashable, Identifiable {
    case frosted
    case solid

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> MenuBarHiderBarStyle {
        guard let raw, let value = MenuBarHiderBarStyle(rawValue: raw) else { return .frosted }
        return value
    }
}

/// Horizontal anchoring preference for the floating hidden-items bar.
enum MenuBarHiderBarLocation: String, CaseIterable, Hashable, Identifiable {
    case dynamic
    case mousePointer
    case triggerIcon

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> MenuBarHiderBarLocation {
        guard let raw, let value = MenuBarHiderBarLocation(rawValue: raw) else { return .dynamic }
        return value
    }
}

/// Auto-rehide behavior for the floating hidden-items bar.
enum MenuBarHiderRehideStrategy: String, CaseIterable, Hashable, Identifiable {
    case smart
    case timed
    case focusedApp

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> MenuBarHiderRehideStrategy {
        guard let raw, let value = MenuBarHiderRehideStrategy(rawValue: raw) else { return .smart }
        return value
    }
}

/// Value bounds and defaults shared between Settings, Service, and tests.
enum MenuBarHiderSupport {
    static let minimumSupportedMacOSMajorVersion = 27

    static let iconSizeRange: ClosedRange<Double> = 16...36
    static let defaultIconSize: Double = 22

    static let itemSpacingRange: ClosedRange<Double> = 0...12
    static let defaultItemSpacing: Double = 4

    static let barPaddingRange: ClosedRange<Double> = 2...12
    static let defaultBarPadding: Double = 4

    static let rehideIntervalRange: ClosedRange<Double> = 1...30
    static let defaultRehideInterval: Double = 15

    static let tempShowIntervalRange: ClosedRange<Double> = 2...30
    static let defaultTempShowInterval: Double = 15

    static var isOSSupported: Bool {
        isOSSupported(version: ProcessInfo.processInfo.operatingSystemVersion)
    }

    static func isOSSupported(version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= minimumSupportedMacOSMajorVersion
    }

    static func clampedIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIconSize }
        return min(iconSizeRange.upperBound, max(iconSizeRange.lowerBound, value.rounded()))
    }

    static func clampedItemSpacing(_ value: Double) -> Double {
        guard value.isFinite else { return defaultItemSpacing }
        return min(itemSpacingRange.upperBound, max(itemSpacingRange.lowerBound, value.rounded()))
    }

    static func clampedBarPadding(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBarPadding }
        return min(barPaddingRange.upperBound, max(barPaddingRange.lowerBound, value.rounded()))
    }

    static func clampedRehideInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultRehideInterval }
        return min(rehideIntervalRange.upperBound, max(rehideIntervalRange.lowerBound, value.rounded()))
    }

    static func clampedTempShowInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTempShowInterval }
        return min(tempShowIntervalRange.upperBound, max(tempShowIntervalRange.lowerBound, value.rounded()))
    }

    static func decodeAssignments(_ raw: [String: String]?) -> [String: MenuBarHiderSection] {
        guard let raw else { return [:] }
        var result: [String: MenuBarHiderSection] = [:]
        for (key, value) in raw {
            guard let section = MenuBarHiderSection(rawValue: value) else { continue }
            result[key] = section
        }
        return result
    }

    static func encodeAssignments(_ assignments: [String: MenuBarHiderSection]) -> [String: String] {
        assignments.mapValues(\.rawValue)
    }
}

/// The macOS 27 visibility assertion operates on owning applications, not windows.
/// Pure policy independent of AppKit so its allowlist rules remain unit-testable.
enum MenuBarHiderVisibilityPolicy {
    struct Item {
        let bundleIdentifier: String?
        let shouldHide: Bool
    }

    struct Configuration: Equatable {
        let concealed: Set<String>
        let allowed: Set<String>
    }

    static func configuration(
        items: [Item],
        runningBundleIdentifiers: Set<String>,
        ownBundleIdentifier: String
    ) -> Configuration {
        let visible = Set(items.filter { !$0.shouldHide }.compactMap(\.bundleIdentifier))
        let concealed = Set(items.filter(\.shouldHide).compactMap(\.bundleIdentifier))
            .subtracting(visible)
            .filter { !$0.isEmpty && $0 != ownBundleIdentifier && !$0.hasPrefix("com.apple.") }
        // Include discovered owners too: some hosted helpers do not appear in
        // NSWorkspace's application list. Never hide an unselected owner.
        let allOwners = Set(items.compactMap(\.bundleIdentifier))
        let allowed = runningBundleIdentifiers.union(allOwners)
            .union([ownBundleIdentifier]).subtracting(concealed).filter { !$0.isEmpty }
        return Configuration(concealed: concealed, allowed: allowed)
    }
}

/// Pure scheduling rules for the bounded hosted-menu accessibility scanner.
enum MenuBarHiderScanPolicy {
    static func shouldRequestRefresh(cacheIsFresh: Bool, scanInFlight: Bool, force: Bool) -> Bool {
        force || (!cacheIsFresh && !scanInFlight)
    }

    static func orderedIndices(count: Int, cursor: Int) -> [Int] {
        guard count > 0 else { return [] }
        let start = cursor % count
        return (0..<count).map { (start + $0) % count }
    }

    static func nextCursor(count: Int, cursor: Int, scannedCount: Int) -> Int {
        guard count > 0 else { return 0 }
        return (cursor + scannedCount) % count
    }

    static func retainedOwners<Owner: Hashable>(
        existing: Set<Owner>,
        live: Set<Owner>,
        scanned: Set<Owner>
    ) -> Set<Owner> {
        existing.intersection(live).subtracting(scanned)
    }
}

/// Only a complete, unconcealed owner scan can establish that an item was
/// removed. Missing/partial scans and native concealment retain descriptors.
enum MenuBarHiderSnapshotPolicy {
    static func merge<Item, ID: Hashable, Owner: Hashable>(
        existing: [ID: Item],
        discovered: [Item],
        liveOwners: Set<Owner>,
        scannedOwners: Set<Owner>,
        id: (Item) -> ID,
        owner: (Item) -> Owner,
        preserveMissing: (Item) -> Bool
    ) -> [ID: Item] {
        let discoveredIDs = Set(discovered.map(id))
        var result = existing.filter { key, item in
            liveOwners.contains(owner(item))
                && (!scannedOwners.contains(owner(item)) || preserveMissing(item) || discoveredIDs.contains(key))
        }
        for item in discovered where liveOwners.contains(owner(item)) {
            result[id(item)] = item
        }
        return result
    }
}

/// Controls how long a temporarily revealed app stays visible while its menu/popover is open.
enum MenuBarHiderTempRevealPolicy {
    struct Window {
        let id: UInt32
        let ownerPID: Int32
        let layer: Int
    }

    static func shouldWait(
        windows: [Window],
        ownerPID: Int32,
        baselineIDs: Set<UInt32>,
        interfaceLayers: ClosedRange<Int>,
        elapsed: Duration,
        maximumWait: Duration = .seconds(120)
    ) -> Bool {
        guard elapsed < maximumWait else { return false }
        return windows.contains {
            $0.ownerPID == ownerPID && !baselineIDs.contains($0.id) && interfaceLayers.contains($0.layer)
        }
    }
}

/// Resolves menu bar clicks without depending on mutable global modifier state.
enum MenuBarHiderClickPolicy {
    enum Button {
        case primary
        case secondary
    }

    struct ModifierSnapshot: OptionSet {
        let rawValue: UInt8

        static let option = ModifierSnapshot(rawValue: 1 << 0)
        static let control = ModifierSnapshot(rawValue: 1 << 1)

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        init(option: Bool, control: Bool) {
            var value: ModifierSnapshot = []
            if option { value.insert(.option) }
            if control { value.insert(.control) }
            self = value
        }
    }

    enum Action: Equatable {
        case toggleHidden
        case toggleAlwaysHidden
        case showMenu
    }

    static func resolve(
        button: Button,
        modifiers: ModifierSnapshot,
        allowsAlwaysHidden: Bool
    ) -> Action {
        if button == .secondary || modifiers.contains(.control) {
            return .showMenu
        }
        if allowsAlwaysHidden, modifiers.contains(.option) {
            return .toggleAlwaysHidden
        }
        return .toggleHidden
    }
}

/// All input and output rectangles use top-left CoreGraphics coordinates.
/// A missing menu snapshot must never be treated as empty space.
enum MenuBarHiderAppMenuGeometry {
    static func frame(itemFrames: [CGRect], displayBounds: CGRect) -> CGRect? {
        guard !itemFrames.isEmpty else { return nil }
        let menuBand = CGRect(
            x: displayBounds.minX,
            y: displayBounds.minY,
            width: displayBounds.width,
            height: 80
        )
        guard itemFrames.allSatisfy({ frame in
            !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
                && frame.height <= 80 && frame.intersects(menuBand)
        }) else { return nil }
        let union = itemFrames.reduce(CGRect.null) { $0.union($1) }
        guard union.maxX > displayBounds.minX, union.maxX <= displayBounds.maxX else { return nil }
        return CGRect(
            x: displayBounds.minX,
            y: union.minY,
            width: union.maxX - displayBounds.minX,
            height: union.height
        )
    }

    static func isEmptySpace(at point: CGPoint, applicationMenuFrame: CGRect?) -> Bool {
        guard let applicationMenuFrame else { return false }
        return point.x > applicationMenuFrame.maxX
    }

    static func projectedFrame(_ frame: CGRect, on displayBounds: CGRect) -> CGRect? {
        guard frame.width > 0, frame.width < displayBounds.width else { return nil }
        return CGRect(
            x: displayBounds.minX,
            y: displayBounds.minY,
            width: frame.width,
            height: frame.height
        )
    }

    static func isEmptyHostedSpace(
        at point: CGPoint,
        applicationMenuFrame: CGRect?,
        itemFrames: [CGRect]?,
        displayBounds: CGRect
    ) -> Bool {
        guard isEmptySpace(at: point, applicationMenuFrame: applicationMenuFrame), let itemFrames else { return false }
        let onDisplay = itemFrames.filter { $0.intersects(displayBounds) }
        if let trailingMaxX = onDisplay.map(\.maxX).max(),
           displayBounds.maxX - trailingMaxX <= 32,
           point.x >= trailingMaxX - 2 {
            return false
        }
        return !onDisplay.contains {
            point.x >= $0.minX - 2 && point.x <= $0.maxX + 2
        }
    }
}

/// Multi-display rendered item disambiguation.
enum MenuBarHiderRenderedMatcher {
    static func pickUnambiguousMatch<Candidate>(
        from matches: [Candidate],
        preferredDisplayID: CGDirectDisplayID?,
        displayID: (Candidate) -> CGDirectDisplayID,
        frame: (Candidate) -> CGRect
    ) -> Candidate? {
        guard let firstMatch = matches.first else {
            return nil
        }
        let targetDisplayID: CGDirectDisplayID
        if let preferredDisplayID, matches.contains(where: { displayID($0) == preferredDisplayID }) {
            targetDisplayID = preferredDisplayID
        } else {
            targetDisplayID = displayID(firstMatch)
        }
        let displayMatches = matches.filter { displayID($0) == targetDisplayID }
        guard
            let first = displayMatches.first,
            displayMatches.dropFirst().allSatisfy({ frame($0) == frame(first) })
        else {
            return nil
        }
        return first
    }
}

/// Tracks Notification Center or Calendar popover visibility while the Clock
/// activation bridge is active on macOS 27+.
struct MenuBarHiderClockSession {
    struct SystemWindowSnapshot {
        let id: CGWindowID
        let bundleIdentifier: String?
        let title: String?
        let frame: CGRect
        let layer: Int
        let alpha: Double
    }

    enum Decision: Equatable {
        case wait(Duration)
        case restore
    }

    private static let clockHostBundles: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
    ]

    private var appeared = false
    private var missingSince: Duration?

    static func requiresActivationBridge(operatingSystemVersion version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= 27
    }

    mutating func observe(isOpen: Bool, elapsed: Duration) -> Decision {
        if isOpen {
            appeared = true
            missingSince = nil
        } else if appeared {
            if let missingSince, elapsed - missingSince >= .milliseconds(300) {
                return .restore
            }
            if missingSince == nil {
                missingSince = elapsed
            }
        } else if elapsed >= .seconds(3) {
            return .restore
        }
        return .wait(elapsed >= .seconds(30) ? .seconds(1) : .milliseconds(100))
    }

    static func isNotificationCenterWindow(
        title: String?,
        frame: CGRect,
        displayBounds: [CGRect]
    ) -> Bool {
        if title == "Notification Center" || title == "Calendar" {
            return true
        }
        guard frame.width > 0, frame.height > 0 else {
            return false
        }
        return displayBounds.contains { bounds in
            guard bounds.width > 0, bounds.height > 0, frame.intersects(bounds) else {
                return false
            }
            let coversDisplay = abs(frame.minX - bounds.minX) < 2
                && abs(frame.minY - bounds.minY) < 2
                && frame.width >= bounds.width * 0.8
                && frame.height >= bounds.height * 0.8
            if coversDisplay {
                return true
            }
            let isTrailingPanel = abs(frame.maxX - bounds.maxX) <= 32
                && frame.minY <= bounds.minY + 60
                && frame.width >= 240
                && frame.height >= 180
            return isTrailingPanel
        }
    }

    static func isClockPanelOpen(
        windows: [SystemWindowSnapshot],
        baselineWindowIDs: Set<CGWindowID> = [],
        floatingLayerMinimum: Int,
        displayBounds: [CGRect]
    ) -> Bool {
        windows.contains { window in
            guard window.alpha > 0,
                  let bundle = window.bundleIdentifier,
                  clockHostBundles.contains(bundle)
            else {
                return false
            }
            if bundle == "com.apple.notificationcenterui",
               isNotificationCenterWindow(
                   title: window.title,
                   frame: window.frame,
                   displayBounds: displayBounds
               ) {
                return true
            }
            guard !baselineWindowIDs.contains(window.id),
                  window.layer >= floatingLayerMinimum,
                  window.frame.width >= 200,
                  window.frame.height >= 180
            else {
                return false
            }
            return displayBounds.contains { $0.intersects(window.frame) }
        }
    }
}

/// Keeps a working native restriction alive while its replacement is pending.
@MainActor
final class MenuBarHiderAssertionSession<Handle> {
    typealias Configuration = MenuBarHiderVisibilityPolicy.Configuration
    typealias Completion = @MainActor (Result<Configuration, Error>) -> Void

    enum Failure: LocalizedError {
        case unavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The menu bar hiding request could not start."
            case .timedOut:
                return "macOS did not finish updating menu bar visibility. Try again."
            }
        }
    }

    private let activate: (Configuration, @escaping @MainActor (Error?) -> Void) -> Handle?
    private let invalidate: (Handle) -> Void
    private let timeout: Duration
    private var activeHandle: Handle?
    private var pendingHandle: Handle?
    private var pendingConfiguration: Configuration?
    private var completion: Completion?
    private var timeoutTask: Task<Void, Never>?
    private var generation = 0

    private(set) var activeConfiguration: Configuration?
    var isActive: Bool { activeHandle != nil }
    var isActivating: Bool { pendingConfiguration != nil }

    init(
        timeout: Duration = .seconds(3),
        activate: @escaping (Configuration, @escaping @MainActor (Error?) -> Void) -> Handle?,
        invalidate: @escaping (Handle) -> Void
    ) {
        self.timeout = timeout
        self.activate = activate
        self.invalidate = invalidate
    }

    @discardableResult
    func begin(_ configuration: Configuration, completion: @escaping Completion) -> Bool {
        guard !isActivating else { return false }
        generation += 1
        let attempt = generation
        pendingConfiguration = configuration
        self.completion = completion
        pendingHandle = activate(configuration) { [weak self] error in
            Task { @MainActor [weak self] in self?.finish(attempt, error: error) }
        }
        guard pendingHandle != nil else {
            finish(attempt, error: Failure.unavailable)
            return true
        }
        timeoutTask = Task { @MainActor [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(attempt, error: Failure.timedOut)
        }
        return true
    }

    func invalidateAll() {
        generation += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        let callback = completion
        completion = nil
        pendingConfiguration = nil
        if let pendingHandle { invalidate(pendingHandle) }
        if let activeHandle { invalidate(activeHandle) }
        pendingHandle = nil
        activeHandle = nil
        activeConfiguration = nil
        callback?(.failure(CancellationError()))
    }

    private func finish(_ attempt: Int, error: Error?) {
        guard generation == attempt, let configuration = pendingConfiguration else { return }
        generation += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        let callback = completion
        completion = nil
        pendingConfiguration = nil
        if let error {
            if let pendingHandle { invalidate(pendingHandle) }
            pendingHandle = nil
            callback?(.failure(error))
        } else {
            let previous = activeHandle
            activeHandle = pendingHandle
            pendingHandle = nil
            activeConfiguration = configuration
            if let previous { invalidate(previous) }
            callback?(.success(configuration))
        }
    }
}

/// Coalesced async cache where passive readers never block and invalidation prevents stale publishes.
final class MenuBarHiderAsyncCache<Value>: @unchecked Sendable {
    private struct Reply {
        let value: Value?
        let invalidated: Bool
    }

    private let lock = NSLock()
    private let lifetime: TimeInterval
    private var entry: (date: Date, value: Value)?
    private var lastAttempt = Date.distantPast
    private var generation = 0
    private var inFlight: UUID?
    private var waiters = [CheckedContinuation<Reply, Never>]()

    init(lifetime: TimeInterval) {
        self.lifetime = lifetime
    }

    func value(at date: Date = .now) -> Value? {
        lock.withLock {
            guard let entry, date.timeIntervalSince(entry.date) < lifetime else { return nil }
            return entry.value
        }
    }

    func lastValue(maxAge: TimeInterval, at date: Date = .now) -> Value? {
        lock.withLock {
            guard let entry, date.timeIntervalSince(entry.date) < maxAge else { return nil }
            return entry.value
        }
    }

    func invalidate() {
        lock.withLock {
            generation += 1
            entry = nil
            lastAttempt = .distantPast
        }
    }

    func requestRefresh(force: Bool = false, load: @escaping () async -> Value?) {
        enqueue(force: force, continuation: nil, load: load)
    }

    func refresh(force: Bool = false, load: @escaping () async -> Value?) async -> Value? {
        var needsFreshScan = force
        while !Task.isCancelled {
            let reply: Reply = await withCheckedContinuation {
                enqueue(force: needsFreshScan, continuation: $0, load: load)
            }
            guard !Task.isCancelled else { return nil }
            if !reply.invalidated { return reply.value }
            needsFreshScan = true
        }
        return nil
    }

    private func enqueue(
        force: Bool,
        continuation: CheckedContinuation<Reply, Never>?,
        load: @escaping () async -> Value?
    ) {
        lock.lock()
        if !force, let entry, Date.now.timeIntervalSince(entry.date) < lifetime {
            lock.unlock()
            continuation?.resume(returning: Reply(value: entry.value, invalidated: false))
            return
        }
        if inFlight != nil {
            if let continuation { waiters.append(continuation) }
            lock.unlock()
            return
        }
        if !force, Date.now.timeIntervalSince(lastAttempt) < lifetime {
            lock.unlock()
            continuation?.resume(returning: Reply(value: nil, invalidated: false))
            return
        }
        let token = UUID()
        let attempt = generation
        inFlight = token
        lastAttempt = .now
        if let continuation { waiters.append(continuation) }
        lock.unlock()
        Task { [self] in
            let value = await load()
            finish(token: token, generation: attempt, value: value)
        }
    }

    private func finish(token: UUID, generation attempt: Int, value: Value?) {
        lock.lock()
        guard inFlight == token else {
            lock.unlock()
            return
        }
        let currentValue = generation == attempt ? value : nil
        entry = currentValue.map { (date: .now, value: $0) }
        let completions = waiters
        waiters.removeAll()
        inFlight = nil
        let reply = Reply(value: currentValue, invalidated: generation != attempt)
        lock.unlock()
        completions.forEach { $0.resume(returning: reply) }
    }
}
