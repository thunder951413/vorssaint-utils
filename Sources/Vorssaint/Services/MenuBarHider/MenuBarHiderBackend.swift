// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Cocoa
import os.log

/// Accessibility handle for a macOS 27+ `MenuBarAgent`-hosted status item.
final class MenuBarHiderItemHandle: @unchecked Sendable {
    let element: AXUIElement
    let sourcePID: pid_t
    let sourceBundleIdentifier: String?
    let stableID: String
    let title: String?
    let identityStrings: [String]
    let role: String?
    let subrole: String?
    let windowID: CGWindowID?
    let initialFrame: CGRect
    let usesLocalInitialFrame: Bool

    init(
        element: AXUIElement,
        sourcePID: pid_t,
        sourceBundleIdentifier: String?,
        stableID: String,
        title: String?,
        identityStrings: [String],
        role: String?,
        subrole: String?,
        windowID: CGWindowID?,
        initialFrame: CGRect,
        usesLocalInitialFrame: Bool
    ) {
        self.element = element
        self.sourcePID = sourcePID
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.stableID = stableID
        self.title = title
        self.identityStrings = identityStrings
        self.role = role
        self.subrole = subrole
        self.windowID = windowID
        self.initialFrame = initialFrame
        self.usesLocalInitialFrame = usesLocalInitialFrame
    }

    var currentFrame: CGRect? {
        guard !MenuBarHiderBackend.isConcealed(sourceBundleIdentifier) else {
            return nil
        }
        return MenuBarHiderBackend.renderedFrame(for: self)
    }

    var isOnScreen: Bool {
        if usesLocalInitialFrame {
            return currentFrame != nil
        }
        guard let frame = currentFrame else {
            return false
        }
        return NSScreen.screens.contains { CGDisplayBounds($0.displayID).intersects(frame) }
    }

    func performPress() -> Bool {
        guard
            !MenuBarHiderBackend.isConcealed(sourceBundleIdentifier),
            let rendered = MenuBarHiderBackend.renderedElement(for: self)
        else {
            return false
        }
        return MenuBarHiderBackend.press(rendered)
    }
}

/// Representation of a discovered status item in the macOS 27+ hosted menu bar.
struct MenuBarHiderItem: Identifiable, Hashable {
    let handle: MenuBarHiderItemHandle
    let stableID: String
    let ownerPID: pid_t
    let bundleIdentifier: String?
    let title: String?
    let initialFrame: CGRect

    var id: String { stableID }

    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    var frame: CGRect {
        handle.currentFrame ?? initialFrame
    }

    var isOnScreen: Bool {
        handle.isOnScreen
    }

    /// Only third-party apps (excluding Apple system items and Vorssaint itself) can be hidden.
    var canBeHidden: Bool {
        guard let bundle = bundleIdentifier, !bundle.isEmpty else {
            return false
        }
        return !bundle.hasPrefix("com.apple.") && bundle != Bundle.main.bundleIdentifier
    }

    var displayName: String {
        if let app = owningApplication {
            if let name = app.localizedName, !name.isEmpty {
                return name
            }
            if let bundle = app.bundleIdentifier, !bundle.isEmpty {
                return bundle
            }
        }
        if let title, !title.isEmpty {
            return title
        }
        if let bundle = bundleIdentifier, !bundle.isEmpty {
            return bundle
        }
        return FeatureStrings.menuBarHider(L10n.shared.language).unknownApp
    }

    init(handle: MenuBarHiderItemHandle) {
        self.handle = handle
        self.stableID = "hosted:\(handle.stableID)"
        self.ownerPID = handle.sourcePID
        self.bundleIdentifier = handle.sourceBundleIdentifier
        self.title = handle.title
        self.initialFrame = handle.initialFrame
    }

    static func == (lhs: MenuBarHiderItem, rhs: MenuBarHiderItem) -> Bool {
        lhs.stableID == rhs.stableID
            && lhs.ownerPID == rhs.ownerPID
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.title == rhs.title
            && lhs.initialFrame == rhs.initialFrame
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableID)
        hasher.combine(ownerPID)
        hasher.combine(bundleIdentifier)
        hasher.combine(title)
        hasher.combine(NSStringFromRect(initialFrame))
    }
}

/// Accessibility-backed menu bar item discovery, rendered-tree tracking, and action dispatch
/// for macOS 27+ `MenuBarAgent`-hosted status items.
enum MenuBarHiderBackend {
    struct DescriptorSnapshot: Sendable {
        let items: [MenuBarHiderItemHandle]
        let scannedPIDs: Set<pid_t>
        let concealedBundles: Set<String>

        static let empty = DescriptorSnapshot(items: [], scannedPIDs: [], concealedBundles: [])
    }

    struct RenderedItem: @unchecked Sendable {
        let element: AXUIElement?
        let pid: pid_t
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let identityStrings: Set<String>
    }

    struct ApplicationSnapshot: Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let isResponsive: Bool
    }

    struct EnumerationSnapshot: Sendable {
        let applications: [ApplicationSnapshot]
        let displayBounds: [CGRect]
    }

    struct EnumerationState {
        var cache: (date: Date, snapshot: DescriptorSnapshot)?
        var isEnumerating = false
        var cacheGeneration = 0
        var cursor = 0
        var waiters = [CheckedContinuation<DescriptorSnapshot, Never>]()
        var pendingSnapshot: EnumerationSnapshot?
        var concealedBundleIdentifiers = Set<String>()

        mutating func expireCache() {
            cache = cache.map {
                (
                    date: .distantPast,
                    snapshot: DescriptorSnapshot(
                        items: $0.snapshot.items,
                        scannedPIDs: [],
                        concealedBundles: concealedBundleIdentifiers
                    )
                )
            }
        }
    }

    final class LockedEnumerationState: @unchecked Sendable {
        private let lock = NSLock()
        private var state = EnumerationState()

        func withLock<R>(_ body: (inout EnumerationState) -> R) -> R {
            lock.withLock { body(&state) }
        }
    }

    enum AttributeRead<Value> {
        case value(Value)
        case absent
        case failed(AXError)
    }

    private struct EnumerationScan {
        let items: [MenuBarHiderItemHandle]
        let scannedPIDs: Set<pid_t>
        let livePIDs: Set<pid_t>
        let nextCursor: Int
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vorssaint.utils",
                                       category: "menubar-hider")
    private static let renderedCache = MenuBarHiderAsyncCache<[RenderedItem]>(lifetime: 0.25)
    private static let renderedQueue = DispatchQueue(label: "com.vorssaint.menubar-hider.rendered", qos: .userInitiated)
    private static let enumerationQueue = DispatchQueue(label: "com.vorssaint.menubar-hider.enumeration", qos: .utility)
    private static let enumerationState = LockedEnumerationState()

    private static let enumerationTTL: TimeInterval = 2
    private static let staleRenderedSnapshotAge: TimeInterval = 5
    private static let perApplicationTimeout: Float = 0.15
    private static let perApplicationBudget: TimeInterval = 0.35
    private static let scanBudget: TimeInterval = 1.5
    private static let maxEnumerationRestarts = 2
    private static let pressTimeout: Float = 1

    // MARK: - Concealment & Cache State

    static func isConcealed(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return enumerationState.withLock { $0.concealedBundleIdentifiers.contains(bundleIdentifier) }
    }

    static func setConcealedBundleIdentifiers(_ identifiers: Set<String>) {
        let changed = enumerationState.withLock { state -> Bool in
            guard identifiers != state.concealedBundleIdentifiers else { return false }
            state.concealedBundleIdentifiers = identifiers
            state.cacheGeneration += 1
            state.expireCache()
            return true
        }
        if changed {
            renderedCache.invalidate()
        }
    }

    static func invalidateEnumerationCache() {
        enumerationState.withLock { state in
            state.cacheGeneration += 1
            state.expireCache()
        }
        renderedCache.invalidate()
    }

    // MARK: - AX Actions & Attribute Readers

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, pressTimeout)
        switch AXUIElementPerformAction(element, kAXPressAction as CFString) {
        case .success:
            return true
        case .cannotComplete:
            logger.debug("AXPress did not complete in time; treating as delivered")
            return true
        case let error:
            logger.debug("AXPress failed: \(error.rawValue)")
            return false
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard case .value(let frame) = frameRead(of: element) else { return nil }
        return frame
    }

    static func frameRead(of element: AXUIElement) -> AttributeRead<CGRect> {
        let positionValue: AXValue
        let sizeValue: AXValue
        switch attributeRead(kAXPositionAttribute, of: element) as AttributeRead<AXValue> {
        case .value(let value): positionValue = value
        case .absent: return .absent
        case .failed(let error): return .failed(error)
        }
        switch attributeRead(kAXSizeAttribute, of: element) as AttributeRead<AXValue> {
        case .value(let value): sizeValue = value
        case .absent: return .absent
        case .failed(let error): return .failed(error)
        }
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize
        else {
            return .failed(.failure)
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return .failed(.failure)
        }
        return .value(CGRect(origin: position, size: size))
    }

    static func attributeRead<T>(_ name: String, of element: AXUIElement) -> AttributeRead<T> {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
        case .success:
            guard let typedValue = value as? T else { return .failed(.failure) }
            return .value(typedValue)
        case .noValue, .attributeUnsupported:
            return .absent
        case let error:
            return .failed(error)
        }
    }

    static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        guard case let .value(value) = attributeRead(name, of: element) as AttributeRead<T> else {
            return nil
        }
        return value
    }

    // MARK: - Enumeration

    @MainActor
    static func refreshEnumeration(force: Bool = false) async -> [MenuBarHiderItemHandle] {
        await refreshDescriptorSnapshot(force: force).items
    }

    @MainActor
    static func refreshDescriptorSnapshot(force: Bool = false) async -> DescriptorSnapshot {
        guard AXIsProcessTrusted() else { return .empty }
        let cachedSnapshot = enumerationState.withLock { state -> DescriptorSnapshot? in
            guard !force,
                  let cached = state.cache,
                  Date.now.timeIntervalSince(cached.date) < enumerationTTL
            else { return nil }
            return cached.snapshot
        }
        if let cachedSnapshot {
            return cachedSnapshot
        }
        return await refreshEnumeration(snapshot: makeEnumerationSnapshot(), force: force)
    }

    @MainActor
    private static func makeEnumerationSnapshot() -> EnumerationSnapshot {
        let applications = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationSnapshot? in
            guard app.isFinishedLaunching, !app.isTerminated else { return nil }
            return ApplicationSnapshot(
                pid: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                isResponsive: MenuBarHiderPrivateBridge.isApplicationResponsive(pid: app.processIdentifier)
            )
        }
        return EnumerationSnapshot(
            applications: applications,
            displayBounds: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        )
    }

    private static func refreshEnumeration(snapshot: EnumerationSnapshot, force: Bool) async -> DescriptorSnapshot {
        await withCheckedContinuation { continuation in
            let startInfo = enumerationState.withLock { state -> (generation: Int, cursor: Int)? in
                if !force,
                   let cached = state.cache,
                   Date.now.timeIntervalSince(cached.date) < enumerationTTL {
                    continuation.resume(returning: cached.snapshot)
                    return nil
                }
                state.waiters.append(continuation)
                if state.isEnumerating {
                    state.pendingSnapshot = snapshot
                    return nil
                }
                state.isEnumerating = true
                return (state.cacheGeneration, state.cursor)
            }
            if let startInfo {
                startEnumeration(
                    snapshot: snapshot,
                    generation: startInfo.generation,
                    cursor: startInfo.cursor
                )
            }
        }
    }

    private static func startEnumeration(
        snapshot: EnumerationSnapshot,
        generation: Int,
        cursor: Int,
        restarts: Int = 0
    ) {
        enumerationQueue.async {
            let result = enumerateUncached(snapshot: snapshot, cursor: cursor)

            enum CompletionAction {
                case restart(EnumerationSnapshot, Int, Int)
                case refreshSnapshotAndRestart
                case finish(DescriptorSnapshot, [CheckedContinuation<DescriptorSnapshot, Never>])
            }

            let action: CompletionAction = enumerationState.withLock { state in
                if generation == state.cacheGeneration {
                    state.cursor = result.nextCursor
                    let existingItems = state.cache?.snapshot.items ?? []
                    let retainedOwners = MenuBarHiderScanPolicy.retainedOwners(
                        existing: Set(existingItems.map(\.sourcePID)),
                        live: result.livePIDs,
                        scanned: result.scannedPIDs
                    )
                    let retained = existingItems.filter { retainedOwners.contains($0.sourcePID) }
                    state.cache = (
                        .now,
                        DescriptorSnapshot(
                            items: retained + result.items,
                            scannedPIDs: result.scannedPIDs,
                            concealedBundles: state.concealedBundleIdentifiers
                        )
                    )
                } else if restarts < maxEnumerationRestarts, let newerSnapshot = state.pendingSnapshot {
                    state.pendingSnapshot = nil
                    return .restart(newerSnapshot, state.cacheGeneration, state.cursor)
                } else if restarts < maxEnumerationRestarts {
                    return .refreshSnapshotAndRestart
                }

                let reply = state.cache?.snapshot ?? .empty
                let waiters = state.waiters
                state.waiters.removeAll()
                state.isEnumerating = false
                state.pendingSnapshot = nil
                return .finish(reply, waiters)
            }

            switch action {
            case let .restart(newerSnapshot, newerGeneration, newerCursor):
                startEnumeration(
                    snapshot: newerSnapshot,
                    generation: newerGeneration,
                    cursor: newerCursor,
                    restarts: restarts + 1
                )
            case .refreshSnapshotAndRestart:
                Task { @MainActor in
                    let newerSnapshot = makeEnumerationSnapshot()
                    let (newerGeneration, newerCursor) = enumerationState.withLock {
                        ($0.cacheGeneration, $0.cursor)
                    }
                    startEnumeration(
                        snapshot: newerSnapshot,
                        generation: newerGeneration,
                        cursor: newerCursor,
                        restarts: restarts + 1
                    )
                }
            case let .finish(reply, waiters):
                waiters.forEach { $0.resume(returning: reply) }
            }
        }
    }

    private static func enumerateUncached(snapshot: EnumerationSnapshot, cursor: Int) -> EnumerationScan {
        var result = [MenuBarHiderItemHandle]()
        var stableIDOccurrences = [String: Int]()
        let deadline = Date.now.addingTimeInterval(scanBudget)
        let applications = snapshot.applications
        let displayBounds = snapshot.displayBounds

        let scannableApplications = applications.filter(\.isResponsive)
        let start = scannableApplications.isEmpty ? 0 : cursor % scannableApplications.count
        let orderedApplications = MenuBarHiderScanPolicy
            .orderedIndices(count: scannableApplications.count, cursor: cursor)
            .map { scannableApplications[$0] }
        var scannedPIDs = Set<pid_t>()
        var nextCursor = start

        applicationLoop: for (offset, app) in orderedApplications.enumerated() {
            guard Date.now < deadline else {
                logger.warning("Hosted menu bar enumeration exceeded scan budget")
                break
            }
            if !scannableApplications.isEmpty {
                nextCursor = MenuBarHiderScanPolicy.nextCursor(
                    count: scannableApplications.count,
                    cursor: start,
                    scannedCount: offset + 1
                )
            }
            let applicationDeadline = min(deadline, Date.now.addingTimeInterval(perApplicationBudget))
            let itemStartIndex = result.endIndex

            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, perApplicationTimeout)
            let menuBar: AXUIElement
            switch attributeRead(kAXExtrasMenuBarAttribute, of: appElement) as AttributeRead<AXUIElement> {
            case let .value(value):
                menuBar = value
                AXUIElementSetMessagingTimeout(menuBar, perApplicationTimeout)
            case .absent:
                scannedPIDs.insert(app.pid)
                continue
            case .failed:
                continue
            }
            let children: [AXUIElement]
            switch attributeRead(kAXChildrenAttribute, of: menuBar) as AttributeRead<[AXUIElement]> {
            case let .value(value):
                children = value
            case .absent:
                scannedPIDs.insert(app.pid)
                continue
            case .failed:
                continue
            }

            for element in children {
                AXUIElementSetMessagingTimeout(element, perApplicationTimeout)
                guard Date.now < applicationDeadline else {
                    result.removeSubrange(itemStartIndex..<result.endIndex)
                    continue applicationLoop
                }
                let frame: CGRect
                switch frameRead(of: element) {
                case .value(let value): frame = value
                case .absent: continue
                case .failed:
                    result.removeSubrange(itemStartIndex..<result.endIndex)
                    continue applicationLoop
                }
                guard frame.width > 0, frame.height > 0 else { continue }
                guard Date.now < applicationDeadline else {
                    result.removeSubrange(itemStartIndex..<result.endIndex)
                    continue applicationLoop
                }

                var metadata = [String?]()
                for name in [
                    kAXIdentifierAttribute,
                    kAXTitleAttribute,
                    kAXHelpAttribute,
                    kAXDescriptionAttribute,
                    kAXRoleAttribute,
                    kAXSubroleAttribute,
                ] {
                    guard Date.now < applicationDeadline else {
                        result.removeSubrange(itemStartIndex..<result.endIndex)
                        continue applicationLoop
                    }
                    switch attributeRead(name, of: element) as AttributeRead<String> {
                    case .value(let value): metadata.append(value)
                    case .absent: metadata.append(nil)
                    case .failed:
                        result.removeSubrange(itemStartIndex..<result.endIndex)
                        continue applicationLoop
                    }
                }
                let identifier = metadata[0]
                let identityStrings = metadata.prefix(4).compactMap { (value: String?) -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                let title = identityStrings.first
                guard Date.now < applicationDeadline else {
                    result.removeSubrange(itemStartIndex..<result.endIndex)
                    continue applicationLoop
                }
                let role = metadata[4]
                let subrole = metadata[5]
                let baseStableID = [
                    app.bundleIdentifier ?? "pid:\(app.pid)",
                    role ?? "",
                    subrole ?? "",
                    identifier.flatMap { $0.isEmpty ? nil : $0 } ?? "unidentified",
                ].joined(separator: "|")
                let occurrence = stableIDOccurrences[baseStableID, default: 0]
                stableIDOccurrences[baseStableID] = occurrence + 1
                let stableID = "\(baseStableID)|\(occurrence)"

                let windowID = MenuBarHiderPrivateBridge.windowID(for: element)
                guard Date.now < applicationDeadline else {
                    result.removeSubrange(itemStartIndex..<result.endIndex)
                    continue applicationLoop
                }
                let isGlobalFrame = displayBounds.contains { bounds in
                    frame.minY <= bounds.minY + 80 && frame.intersects(bounds)
                }

                result.append(
                    MenuBarHiderItemHandle(
                        element: element,
                        sourcePID: app.pid,
                        sourceBundleIdentifier: app.bundleIdentifier,
                        stableID: stableID,
                        title: title,
                        identityStrings: identityStrings,
                        role: role,
                        subrole: subrole,
                        windowID: windowID,
                        initialFrame: frame,
                        usesLocalInitialFrame: !isGlobalFrame
                    )
                )
            }
            scannedPIDs.insert(app.pid)
        }

        var seen = Set<String>()
        let deduplicated = result.filter { item in
            let key = item.usesLocalInitialFrame
                ? item.stableID
                : "\(item.sourcePID)|\(NSStringFromRect(item.initialFrame))|\(item.title ?? "")"
            return seen.insert(key).inserted
        }
        return EnumerationScan(
            items: deduplicated,
            scannedPIDs: scannedPIDs,
            livePIDs: Set(applications.map(\.pid)),
            nextCursor: nextCursor
        )
    }

    // MARK: - Rendered Snapshot (MenuBarAgent)

    static func renderedFrame(for item: MenuBarHiderItemHandle) -> CGRect? {
        matchingRenderedItem(for: item, in: renderedItems(allowingStale: true))?.frame
    }

    static func renderedItemFrames(for sourcePID: pid_t? = nil, matchingIdentity identity: String? = nil) -> [CGRect] {
        renderedItemFrameSnapshot(for: sourcePID, matchingIdentity: identity) ?? []
    }

    static func renderedItemFrameSnapshot(for sourcePID: pid_t? = nil, matchingIdentity identity: String? = nil) -> [CGRect]? {
        renderedCache.requestRefresh { await loadRenderedItems() }
        return renderedCache.value()?
            .filter { item in
                (sourcePID == nil || item.pid == sourcePID)
                    && (identity == nil || item.identityStrings.contains(identity!))
            }
            .map(\.frame)
    }

    @MainActor
    static func refreshRenderedSnapshot() async -> Bool {
        await renderedCache.refresh(force: true) { await loadRenderedItems() } != nil
    }

    static func systemClockFrame(at point: CGPoint, allowingStale: Bool = false) -> CGRect? {
        for item in renderedItems(allowingStale: allowingStale)
        where item.identityStrings.contains("com.apple.menuextra.clock") {
            let displayBounds = CGDisplayBounds(item.displayID)
            let minX = item.frame.minX - 4
            let maxX = displayBounds.maxX - item.frame.maxX <= 32 ? displayBounds.maxX : item.frame.maxX + 4
            let minY = min(displayBounds.minY, item.frame.minY)
            let hitRect = CGRect(
                x: minX,
                y: minY,
                width: max(0, maxX - minX),
                height: max(item.frame.maxY - minY + 6, 40)
            )
            if hitRect.contains(point) {
                return item.frame
            }
        }
        return nil
    }

    static func systemClockFrame(on displayID: CGDirectDisplayID) -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)
        return renderedItems(allowingStale: true).first {
            $0.identityStrings.contains("com.apple.menuextra.clock")
                && displayBounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }?.frame
    }

    static func renderedElement(for item: MenuBarHiderItemHandle) -> AXUIElement? {
        matchingRenderedItem(for: item, in: renderedItems())?.element
    }

    private static func preferredRenderedDisplayID() -> CGDirectDisplayID? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated {
            let location = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) {
                return screen.displayID
            }
            if let screen = NSScreen.screens.first(where: {
                location.x >= $0.frame.minX && location.x < $0.frame.maxX && location.y == $0.frame.maxY
            }) {
                return screen.displayID
            }
            return NSScreen.main?.displayID
        }
    }

    private static func matchingRenderedItem(
        for source: MenuBarHiderItemHandle,
        in candidates: [RenderedItem]
    ) -> RenderedItem? {
        let sourceStrings = Set(source.identityStrings)
        let matches = candidates.filter { candidate in
            guard candidate.pid == source.sourcePID else { return false }
            if let element = candidate.element, CFEqual(element, source.element) {
                return true
            }
            if source.sourceBundleIdentifier == "com.apple.MenuBarAgent" {
                return !sourceStrings.isEmpty && !sourceStrings.isDisjoint(with: candidate.identityStrings)
            }
            return sourceStrings.isEmpty || candidate.identityStrings.isEmpty
                || !sourceStrings.isDisjoint(with: candidate.identityStrings)
        }
        return MenuBarHiderRenderedMatcher.pickUnambiguousMatch(
            from: matches,
            preferredDisplayID: preferredRenderedDisplayID(),
            displayID: \.displayID,
            frame: \.frame
        )
    }

    private static func renderedItems(allowingStale: Bool = false) -> [RenderedItem] {
        renderedCache.requestRefresh { await loadRenderedItems() }
        if allowingStale {
            return renderedCache.lastValue(maxAge: staleRenderedSnapshotAge) ?? []
        }
        return renderedCache.value() ?? []
    }

    private static func loadRenderedItems() async -> [RenderedItem]? {
        let input = await MainActor.run { () -> (pid_t, [(displayID: CGDirectDisplayID, bounds: CGRect)])? in
            guard AXIsProcessTrusted(),
                  let host = NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
            else { return nil }
            let displays = NSScreen.screens.map { ($0.displayID, CGDisplayBounds($0.displayID)) }
            return (host.processIdentifier, displays)
        }
        guard let (pid, displays) = input else { return nil }
        return await withCheckedContinuation { continuation in
            renderedQueue.async {
                continuation.resume(returning: readRenderedItems(hostPID: pid, displays: displays))
            }
        }
    }

    private static func readRenderedItems(
        hostPID: pid_t,
        displays: [(displayID: CGDirectDisplayID, bounds: CGRect)]
    ) -> [RenderedItem]? {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        let application = AXUIElementCreateApplication(hostPID)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let windows: [AXUIElement] = attribute(kAXWindowsAttribute, of: application) else {
            return nil
        }
        var remainingNodes = min(2048, 512 * max(1, windows.count))
        var visited = Set<AXUIElement>()
        var result = [RenderedItem]()
        var complete = true

        func visit(_ element: AXUIElement, parent: AXUIElement? = nil, depth: Int) {
            guard complete, visited.insert(element).inserted else { return }
            guard depth > 0, remainingNodes > 0, ContinuousClock.now < deadline else {
                complete = false
                return
            }
            remainingNodes -= 1
            AXUIElementSetMessagingTimeout(element, 0.05)
            let role: String?
            switch attributeRead(kAXRoleAttribute, of: element) as AttributeRead<String> {
            case .value(let value): role = value
            case .absent: role = nil
            case .failed:
                complete = false
                return
            }
            if role == kAXApplicationRole as String || role == kAXUnknownRole as String {
                var pid: pid_t = 0
                guard let parent,
                      AXUIElementGetPid(element, &pid) == .success,
                      let frame = frame(of: parent)
                else {
                    complete = false
                    return
                }
                if let displayID = matchingMenuBarDisplayID(for: frame, displays: displays) {
                    result.append(
                        RenderedItem(
                            element: nil,
                            pid: pid,
                            displayID: displayID,
                            frame: frame,
                            identityStrings: []
                        )
                    )
                }
                return
            }
            if role == kAXButtonRole as String || role == kAXMenuBarItemRole as String {
                var pid: pid_t = 0
                guard AXUIElementGetPid(element, &pid) == .success,
                      let frame = frame(of: element)
                else {
                    complete = false
                    return
                }
                if let displayID = matchingMenuBarDisplayID(for: frame, displays: displays) {
                    let strings: [String?] = [
                        attribute(kAXIdentifierAttribute, of: element),
                        attribute(kAXTitleAttribute, of: element),
                        attribute(kAXHelpAttribute, of: element),
                        attribute(kAXDescriptionAttribute, of: element),
                    ]
                    result.append(
                        RenderedItem(
                            element: element,
                            pid: pid,
                            displayID: displayID,
                            frame: frame,
                            identityStrings: Set(strings.compactMap { $0 }.filter { !$0.isEmpty })
                        )
                    )
                }
                return
            }
            switch attributeRead(kAXChildrenAttribute, of: element) as AttributeRead<[AXUIElement]> {
            case .value(let children):
                for child in children {
                    visit(child, parent: element, depth: depth - 1)
                }
            case .absent:
                break
            case .failed:
                complete = false
            }
        }

        for window in windows {
            visit(window, depth: 12)
        }
        return complete && ContinuousClock.now < deadline ? result : nil
    }

    private static func matchingMenuBarDisplayID(
        for frame: CGRect,
        displays: [(displayID: CGDirectDisplayID, bounds: CGRect)]
    ) -> CGDirectDisplayID? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        return displays.first { display in
            frame.intersects(display.bounds) && frame.minY <= display.bounds.minY + 80
        }?.displayID
    }
}
