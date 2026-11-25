// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (Thaw) © 2026 Toni Förster
// Copyright (C) 2026 Vorssaint

import Cocoa
import Combine
import MenuBarVisibilityBridge
import os.log

/// Owns the process-scoped macOS 27+ `MenuBarClientCore` visibility assertion.
/// Releasing it restores every hidden icon immediately without touching system preferences.
@MainActor
final class MenuBarHiderVisibilityManager: ObservableObject {
    @Published private(set) var failureDescription: String?

    enum RevealError: LocalizedError {
        case permissionRequired
        case timedOut
        case unavailable

        var errorDescription: String? {
            let s = FeatureStrings.menuBarHider(L10n.shared.language)
            switch self {
            case .permissionRequired: return s.errorPermissionRequired
            case .timedOut: return s.errorRevealTimedOut
            case .unavailable: return s.errorItemUnavailable
            }
        }
    }

    private static let allowedSystemItemKinds: [NSNumber] = (0...8).map { NSNumber(value: $0) }
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vorssaint.utils",
                                       category: "menubar-hider-visibility")

    private weak var service: MenuBarHiderService?
    private lazy var assertion = MenuBarHiderAssertionSession<UnsafeMutableRawPointer>(
        activate: { configuration, completion in
            VorssaintMenuBarVisibilityActivate(configuration.allowed.sorted(), Self.allowedSystemItemKinds) { error in
                MainActor.assumeIsolated { completion(error) }
            }
        },
        invalidate: { VorssaintMenuBarVisibilityInvalidate($0) }
    )

    private var needsReactivation = false
    private var lastFailed: MenuBarHiderVisibilityPolicy.Configuration?
    private var generation = 0
    private var ignoreStateChangesUntil = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryConfiguration: MenuBarHiderVisibilityPolicy.Configuration?
    private var activationFailureCount = 0
    private var revealTasks = [String: Task<Void, Never>]()
    private var temporarilyRevealedBundles = Set<String>()
    private var revealTokens = [String: UUID]()

    private struct RevealWaiter {
        let bundle: String
        let continuation: CheckedContinuation<Void, Error>
        let timeout: Task<Void, Never>
    }
    private var revealWaiters = [UUID: RevealWaiter]()
    private var permissionWasAvailable = true
    private var isStopped = true
    private var isClockActivationInProgress = false

    init(service: MenuBarHiderService) {
        self.service = service
    }

    func start() {
        guard MenuBarHiderSupport.isOSSupported else { return }
        guard isStopped else {
            scheduleRefresh()
            return
        }
        isStopped = false
        cancellables.removeAll()

        if !VorssaintMenuBarVisibilityAvailable() {
            failureDescription = FeatureStrings.menuBarHider(L10n.shared.language).errorAPIUnavailable
        } else {
            failureDescription = nil
        }

        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MenuBarHiderBackend.invalidateEnumerationCache()
                    if name == NSWorkspace.didWakeNotification {
                        self?.needsReactivation = true
                        self?.lastFailed = nil
                    }
                    self?.scheduleRefresh()
                }
                .store(in: &cancellables)
        }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MenuBarHiderBackend.invalidateEnumerationCache()
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.donotdisturb.stateChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, Date.now >= self.ignoreStateChangesUntil else { return }
                self.needsReactivation = true
                self.lastFailed = nil
                self.scheduleRefresh()
            }
            .store(in: &cancellables)

        scheduleRefresh()
    }

    func stop() {
        cancellables.removeAll()
        restoreAll(stop: true)
    }

    func scheduleRefresh() {
        guard !isStopped else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            self.refreshNow()
        }
    }

    func refreshNow() {
        guard MenuBarHiderSupport.isOSSupported, !isStopped, let service else { return }
        guard !isClockActivationInProgress else { return }
        guard checkAccessibility() else { return }
        guard !service.isHidingPaused else {
            if assertion.isActive || assertion.isActivating {
                releaseRestriction()
            }
            resolveRevealWaiters()
            return
        }

        let alwaysEnabled = service.enableAlwaysHiddenSection
        let entries: [MenuBarHiderVisibilityPolicy.Item] = MenuBarHiderSection.allCases.flatMap { section in
            let hide = section == .hidden || (section == .alwaysHidden && alwaysEnabled)
            return service.items(in: section).map { item in
                let bundle = item.bundleIdentifier
                return MenuBarHiderVisibilityPolicy.Item(
                    bundleIdentifier: bundle,
                    shouldHide: hide && item.canBeHidden && !temporarilyRevealedBundles.contains(bundle ?? "")
                )
            }
        }
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.vorssaint.utils"
        let desired = MenuBarHiderVisibilityPolicy.configuration(
            items: entries,
            runningBundleIdentifiers: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            ownBundleIdentifier: ownBundle
        )
        if retryConfiguration != nil, retryConfiguration != desired {
            cancelActivationRetry()
            lastFailed = nil
        }
        guard !desired.concealed.isEmpty else {
            releaseRestriction()
            failureDescription = nil
            lastFailed = nil
            cancelActivationRetry()
            resolveRevealWaiters()
            return
        }
        guard VorssaintMenuBarVisibilityAvailable() else {
            failureDescription = FeatureStrings.menuBarHider(L10n.shared.language).errorAPIUnavailable
            return
        }
        guard !assertion.isActivating else { return }
        if !needsReactivation, let applied = assertion.activeConfiguration, assertion.isActive,
           applied.concealed == desired.concealed,
           desired.allowed.isSubset(of: applied.allowed) {
            resolveRevealWaiters()
            return
        }
        guard lastFailed != desired else { return }

        needsReactivation = false
        generation += 1
        let attempt = generation
        ignoreStateChangesUntil = .now.addingTimeInterval(1.5)
        assertion.begin(desired) { [weak self] result in
            guard let self, self.generation == attempt, !self.isStopped else { return }
            self.ignoreStateChangesUntil = .now.addingTimeInterval(1.5)
            switch result {
            case .failure(let error):
                self.needsReactivation = true
                self.recordActivationFailure(desired, description: error.localizedDescription)
                self.failRevealWaiters(error)
                Self.logger.error("Visibility assertion failed: \(error.localizedDescription, privacy: .public)")
            case .success:
                MenuBarHiderBackend.setConcealedBundleIdentifiers(desired.concealed)
                self.cancelActivationRetry()
                self.lastFailed = nil
                self.failureDescription = nil
                MenuBarHiderBackend.invalidateEnumerationCache()
                self.resolveRevealWaiters()
            }
            self.scheduleRefresh()
        }
    }

    func withTemporarilyRevealedItem(
        _ item: MenuBarHiderItem,
        action: @MainActor (_ validate: @escaping @MainActor () throws -> Void) async throws -> Void
    ) async throws {
        guard !isStopped else { throw CancellationError() }
        guard checkAccessibility() else { throw RevealError.permissionRequired }
        guard let bundle = item.bundleIdentifier else { throw RevealError.unavailable }
        var baselineWindowIDs = Set(
            MenuBarHiderWindowInfo.getOnScreenWindows().filter { $0.ownerPID == item.ownerPID }.map(\.windowID)
        )
        if let previous = revealTokens[bundle] {
            finishRevealWaiter(previous, error: CancellationError())
        }
        let token = UUID()
        revealTokens[bundle] = token
        temporarilyRevealedBundles.insert(bundle)
        revealTasks[bundle]?.cancel()
        revealTasks[bundle] = nil
        var didPerformAction = false
        defer {
            scheduleRehide(
                item,
                bundle: bundle,
                token: token,
                baselineWindowIDs: baselineWindowIDs,
                didPerformAction: didPerformAction
            )
        }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    self?.finishRevealWaiter(token, error: RevealError.timedOut)
                }
                revealWaiters[token] = RevealWaiter(bundle: bundle, continuation: continuation, timeout: timeout)
                refreshNow()
                resolveRevealWaiters()
            }
            try Task.checkCancellation()
            guard revealTokens[bundle] == token, !isStopped else { throw CancellationError() }
            baselineWindowIDs.formUnion(
                MenuBarHiderWindowInfo.getOnScreenWindows().filter { $0.ownerPID == item.ownerPID }.map(\.windowID)
            )
            try await action { [weak self] in
                try Task.checkCancellation()
                guard let self, !self.isStopped, self.revealTokens[bundle] == token else {
                    throw CancellationError()
                }
                guard self.checkAccessibility() else { throw RevealError.permissionRequired }
            }
            didPerformAction = true
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishRevealWaiter(token, error: CancellationError()) }
        }
    }

    func restoreAll(stop: Bool = false) {
        isStopped = stop
        isClockActivationInProgress = false
        refreshTask?.cancel()
        refreshTask = nil
        cancelActivationRetry()
        revealTasks.values.forEach { $0.cancel() }
        revealTasks.removeAll()
        temporarilyRevealedBundles.removeAll()
        revealTokens.removeAll()
        failRevealWaiters(CancellationError())
        lastFailed = nil
        failureDescription = nil
        releaseRestriction()
    }

    var needsClockActivationBridge: Bool {
        MenuBarHiderSupport.isOSSupported
            && MenuBarHiderClockSession.requiresActivationBridge(
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            )
            && !isStopped
            && !isClockActivationInProgress
            && assertion.isActive
    }

    func beginClockActivationBridge() -> Bool {
        guard needsClockActivationBridge else { return false }
        isClockActivationInProgress = true
        releaseRestriction()
        return true
    }

    func endClockActivationBridge() {
        guard isClockActivationInProgress else { return }
        isClockActivationInProgress = false
        refreshNow()
    }

    // MARK: - Private

    private func resolveRevealWaiters() {
        guard !assertion.isActivating else { return }
        let concealed = assertion.activeConfiguration?.concealed ?? []
        let ready = revealWaiters.filter { !concealed.contains($0.value.bundle) }.map(\.key)
        for token in ready {
            finishRevealWaiter(token, error: nil)
        }
    }

    private func finishRevealWaiter(_ token: UUID, error: Error?) {
        guard let waiter = revealWaiters.removeValue(forKey: token) else { return }
        waiter.timeout.cancel()
        if let error {
            waiter.continuation.resume(throwing: error)
        } else {
            waiter.continuation.resume()
        }
    }

    private func failRevealWaiters(_ error: Error) {
        for token in Array(revealWaiters.keys) {
            finishRevealWaiter(token, error: error)
        }
    }

    private func scheduleRehide(
        _ item: MenuBarHiderItem,
        bundle: String,
        token: UUID,
        baselineWindowIDs: Set<CGWindowID>,
        didPerformAction: Bool
    ) {
        guard revealTokens[bundle] == token, !isStopped else { return }
        let configuredDelay = service?.tempShowInterval ?? MenuBarHiderSupport.defaultTempShowInterval
        let boundedDelay = MenuBarHiderSupport.clampedTempShowInterval(configuredDelay)
        let delay = didPerformAction ? max(0.5, boundedDelay) : 0
        revealTasks[bundle] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            let waitStarted = ContinuousClock.now
            while didPerformAction && MenuBarHiderTempRevealPolicy.shouldWait(
                windows: MenuBarHiderWindowInfo.getOnScreenWindows().map {
                    .init(id: $0.windowID, ownerPID: $0.ownerPID, layer: $0.layer)
                },
                ownerPID: item.ownerPID,
                baselineIDs: baselineWindowIDs,
                interfaceLayers: Int(CGWindowLevelForKey(.modalPanelWindow))...Int(CGWindowLevelForKey(.popUpMenuWindow)),
                elapsed: waitStarted.duration(to: .now)
            ) {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            guard self.revealTokens[bundle] == token, !Task.isCancelled else { return }
            self.revealTokens[bundle] = nil
            self.temporarilyRevealedBundles.remove(bundle)
            self.revealTasks[bundle] = nil
            self.refreshNow()
        }
    }

    @discardableResult
    private func checkAccessibility() -> Bool {
        guard AXIsProcessTrusted() else {
            permissionWasAvailable = false
            revealTasks.values.forEach { $0.cancel() }
            revealTasks.removeAll()
            revealTokens.removeAll()
            temporarilyRevealedBundles.removeAll()
            failRevealWaiters(RevealError.permissionRequired)
            if assertion.isActive || assertion.isActivating {
                releaseRestriction()
                cancelActivationRetry()
            }
            failureDescription = RevealError.permissionRequired.localizedDescription
            return false
        }
        if !permissionWasAvailable {
            permissionWasAvailable = true
            needsReactivation = true
            lastFailed = nil
        }
        return true
    }

    private func recordActivationFailure(
        _ configuration: MenuBarHiderVisibilityPolicy.Configuration,
        description: String
    ) {
        if retryConfiguration != configuration {
            cancelActivationRetry()
            retryConfiguration = configuration
        }
        let delays: [Duration] = [
            .milliseconds(500),
            .seconds(1),
            .seconds(2),
            .seconds(4),
            .seconds(8),
        ]
        activationFailureCount = min(activationFailureCount + 1, delays.count)
        lastFailed = configuration
        let fmt = FeatureStrings.menuBarHider(L10n.shared.language).errorHidePartialFormat
        failureDescription = String(format: fmt, description)

        let delay = delays[activationFailureCount - 1]
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isStopped,
                  self.retryConfiguration == configuration
            else { return }
            self.retryTask = nil
            self.lastFailed = nil
            self.refreshNow()
        }
    }

    private func cancelActivationRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryConfiguration = nil
        activationFailureCount = 0
    }

    private func releaseRestriction() {
        let hadRestriction = assertion.isActive || assertion.isActivating
        if hadRestriction {
            MenuBarHiderBackend.invalidateEnumerationCache()
            generation += 1
            ignoreStateChangesUntil = .now.addingTimeInterval(1.5)
            assertion.invalidateAll()
        }
        needsReactivation = false
        MenuBarHiderBackend.setConcealedBundleIdentifiers([])
    }
}
