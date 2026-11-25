// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Cocoa
import Combine
import os.log

/// Main coordinator for native macOS 27+ menu bar icon hiding, the floating hidden bar,
/// optional trigger status item, empty-space click handling, and Date/Clock pass-through.
@MainActor
final class MenuBarHiderService: NSObject, ObservableObject {
    static let shared = MenuBarHiderService()

    private static let triggerAutosaveName = "VorssaintMenuBarHiderTrigger"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vorssaint.utils",
                                       category: "menubar-hider")

    /// Supplied by AppDelegate so clicking Vorssaint's own icons is never treated as empty space.
    var vorssaintStatusItemContainsPoint: ((NSPoint) -> Bool)?

    /// Supplied by AppDelegate to open the Menu Bar Hider settings page cleanly.
    var onOpenSettings: (() -> Void)?

    // MARK: - Published State

    @Published private(set) var itemsBySection: [MenuBarHiderSection: [MenuBarHiderItem]] = [:]
    @Published private(set) var hasCompletedInitialScan = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isHidingPaused = false
    @Published private(set) var isBarPresented = false
    @Published private(set) var isMenuBarHiddenBySystemUserDefaults = false
    @Published private(set) var isMenuBarHiddenBySystem = false
    @Published private(set) var visibilityFailureDescription: String?

    // MARK: - Settings Accessors

    var isFeatureActive: Bool {
        MenuBarHiderSupport.isOSSupported
            && AppFeature.menuBarHider.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderEnabled)
    }

    var showTriggerIcon: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderShowTriggerIcon)
    }

    var showOnEmptyClick: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderShowOnEmptyClick)
    }

    var enableAlwaysHiddenSection: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderEnableAlwaysHidden)
    }

    var canToggleAlwaysHiddenWithOption: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderOptionToggleAlwaysHidden)
    }

    var barStyle: MenuBarHiderBarStyle {
        MenuBarHiderBarStyle.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.menuBarHiderBarStyle))
    }

    var barLocation: MenuBarHiderBarLocation {
        MenuBarHiderBarLocation.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.menuBarHiderBarLocation))
    }

    var iconSize: CGFloat {
        CGFloat(MenuBarHiderSupport.clampedIconSize(UserDefaults.standard.double(forKey: DefaultsKey.menuBarHiderIconSize)))
    }

    var itemSpacing: CGFloat {
        CGFloat(MenuBarHiderSupport.clampedItemSpacing(UserDefaults.standard.double(forKey: DefaultsKey.menuBarHiderItemSpacing)))
    }

    var barPadding: CGFloat {
        CGFloat(MenuBarHiderSupport.clampedBarPadding(UserDefaults.standard.double(forKey: DefaultsKey.menuBarHiderBarPadding)))
    }

    var autoRehide: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAutoRehide)
    }

    var rehideStrategy: MenuBarHiderRehideStrategy {
        MenuBarHiderRehideStrategy.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.menuBarHiderRehideStrategy))
    }

    var rehideInterval: TimeInterval {
        MenuBarHiderSupport.clampedRehideInterval(UserDefaults.standard.double(forKey: DefaultsKey.menuBarHiderRehideInterval))
    }

    var tempShowInterval: TimeInterval {
        MenuBarHiderSupport.clampedTempShowInterval(UserDefaults.standard.double(forKey: DefaultsKey.menuBarHiderTempShowInterval))
    }

    // MARK: - Subcomponents

    private(set) lazy var visibilityManager = MenuBarHiderVisibilityManager(service: self)
    private(set) lazy var barPanel = MenuBarHiderPanel(service: self)

    // MARK: - Internal State

    private var running = false
    private var sectionAssignments: [String: MenuBarHiderSection] = [:]
    private var itemSnapshots: [String: MenuBarHiderItem] = [:]
    private var refreshGeneration = 0
    private var cancellables = Set<AnyCancellable>()
    private var defaultsObserver: NSObjectProtocol?

    // Optional dedicated trigger status item
    private var triggerStatusItem: NSStatusItem?
    private var triggerHostedClickMonitor: Any?
    private var lastTriggerClickDate = Date.distantPast

    // Event monitoring (empty menu bar click, smart rehide, Clock pass-through)
    private var mouseDownMonitor: MenuBarHiderUniversalMonitor?
    private var mouseUpMonitor: MenuBarHiderUniversalMonitor?
    private var timedRehideTimer: Timer?
    private var timedRehideMonitor: MenuBarHiderUniversalMonitor?
    private var clockMouseDownPoint: CGPoint?
    private var clockBaselineWindowIDs = Set<CGWindowID>()
    private var clockActivationTask: Task<Void, Never>?
    private var isSynthesizingClockClick = false
    private var menuBarWindowFrameCache: (displayID: CGDirectDisplayID, date: ContinuousClock.Instant, frame: CGRect?)?

    private struct ApplicationMenuFrameKey: Hashable {
        let ownerPID: pid_t
        let displayID: CGDirectDisplayID
    }
    private var applicationMenuFrameCache = [ApplicationMenuFrameKey: (date: ContinuousClock.Instant, frame: CGRect?)]()
    private nonisolated static let applicationMenuFrameCacheLifetime: Duration = .milliseconds(500)

    private override init() {
        super.init()
        loadPersistedAssignments()
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let shouldRun = isFeatureActive && AXIsProcessTrusted()
        if shouldRun {
            if !running {
                start()
            } else {
                syncTriggerStatusItem()
                rebuildItemCache()
                visibilityManager.refreshNow()
            }
        } else {
            if running {
                stop()
            } else {
                removeTriggerStatusItem()
            }
        }
    }

    func suspend() {
        stop()
    }

    func stopBeforeTermination() {
        stop()
    }

    private func start() {
        guard !running else { return }
        running = true
        MenuBarHiderPrivateBridge.setCursorInBackground(true)
        refreshSystemMenuBarHiddenDefaults()
        loadPersistedAssignments()

        cancellables.removeAll()
        visibilityManager.$failureDescription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.visibilityFailureDescription = value
            }
            .store(in: &cancellables)

        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                guard let self else { return }
                self.isMenuBarHiddenBySystem = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                self.refreshSystemMenuBarHiddenDefaults()
            }
            .store(in: &cancellables)

        Publishers.Merge(
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refreshSystemMenuBarHiddenDefaults()
        }
        .store(in: &cancellables)

        // Periodic item scan (30s) + initial scan
        Timer.publish(every: 30, on: .main, in: .default)
            .autoconnect()
            .merge(with: Just(.now))
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.cacheItemsIfNeeded() }
            }
            .store(in: &cancellables)

        // Rescan on app launch/termination
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .delay(for: 0.25, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.cacheItemsIfNeeded() }
            }
            .store(in: &cancellables)

        // Focused-app auto-rehide
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleFrontmostAppChanged()
            }
            .store(in: &cancellables)

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.syncTriggerStatusItem()
                self.rebuildItemCache()
                self.visibilityManager.scheduleRefresh()
            }
        }

        syncTriggerStatusItem()
        startEventMonitors()
        visibilityManager.start()
    }

    private func stop() {
        running = false
        stopRehideChecks()
        stopEventMonitors()
        barPanel.close()
        visibilityManager.stop()
        removeTriggerStatusItem()
        cancellables.removeAll()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        isHidingPaused = false
        isBarPresented = false
        visibilityFailureDescription = nil
    }

    // MARK: - Item Queries & Section Assignments

    func items(in section: MenuBarHiderSection) -> [MenuBarHiderItem] {
        itemsBySection[section] ?? []
    }

    func managedItems(in section: MenuBarHiderSection) -> [MenuBarHiderItem] {
        items(in: section).filter(\.canBeHidden)
    }

    var hiddenItemCount: Int {
        managedItems(in: .hidden).count
            + (enableAlwaysHiddenSection ? managedItems(in: .alwaysHidden).count : 0)
    }

    func refreshItems() async {
        guard MenuBarHiderSupport.isOSSupported, AXIsProcessTrusted() else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        MenuBarHiderBackend.invalidateEnumerationCache()
        await cacheItemsIfNeeded()
    }

    func cacheItemsIfNeeded() async {
        guard MenuBarHiderSupport.isOSSupported, AXIsProcessTrusted() else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let snapshot = await MenuBarHiderBackend.refreshDescriptorSnapshot()
        guard generation == refreshGeneration else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let discovered = snapshot.items
            .map(MenuBarHiderItem.init(handle:))
            .filter { $0.ownerPID != ownPID }
        mergeDiscoveredItems(
            discovered: discovered,
            scannedPIDs: snapshot.scannedPIDs,
            concealedBundles: snapshot.concealedBundles
        )
        hasCompletedInitialScan = true
        if running {
            visibilityManager.scheduleRefresh()
        }
    }

    func assignItem(_ item: MenuBarHiderItem, to section: MenuBarHiderSection) {
        guard item.canBeHidden else { return }
        itemSnapshots[item.stableID] = item
        if let bundle = item.bundleIdentifier {
            sectionAssignments["bundle:" + bundle] = section
            for sibling in itemSnapshots.values where sibling.bundleIdentifier == bundle {
                sectionAssignments[sibling.stableID] = section
            }
        } else {
            sectionAssignments[item.stableID] = section
        }
        persistAssignments()
        rebuildItemCache()
        visibilityManager.scheduleRefresh()
    }

    func resetAllAssignments() {
        isHidingPaused = false
        barPanel.close()
        sectionAssignments.removeAll()
        UserDefaults.standard.removeObject(forKey: DefaultsKey.menuBarHiderAssignments)
        rebuildItemCache()
        visibilityManager.restoreAll()
    }

    func toggleHidingPaused() {
        if isHidingPaused {
            isHidingPaused = false
            visibilityManager.refreshNow()
        } else {
            isHidingPaused = true
            barPanel.close()
            visibilityManager.restoreAll()
        }
        updateTriggerIconAppearance()
    }

    // MARK: - Bar Presentation

    func toggleBar(section: MenuBarHiderSection = .hidden, on screen: NSScreen? = nil, menuBarClickX: CGFloat? = nil) {
        guard isFeatureActive else { return }
        let target: MenuBarHiderSection = (section == .alwaysHidden && enableAlwaysHiddenSection) ? .alwaysHidden : .hidden
        if barPanel.isVisible && barPanel.currentSection == target {
            closeBar()
        } else {
            showBar(section: target, on: screen, menuBarClickX: menuBarClickX)
        }
    }

    func showBar(section: MenuBarHiderSection = .hidden, on screen: NSScreen? = nil, menuBarClickX: CGFloat? = nil) {
        guard isFeatureActive,
              let targetScreen = screen ?? MenuBarHiderScreenGeometry.screenWithMouse ?? NSScreen.main
        else { return }
        let target: MenuBarHiderSection = (section == .alwaysHidden && enableAlwaysHiddenSection) ? .alwaysHidden : .hidden
        isBarPresented = true
        updateTriggerIconAppearance()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.barPanel.show(section: target, on: targetScreen, menuBarClickX: menuBarClickX)
            self.startRehideChecksIfNeeded()
        }
    }

    func closeBar() {
        stopRehideChecks()
        barPanel.close()
    }

    func noteBarClosed() {
        stopRehideChecks()
        isBarPresented = false
        updateTriggerIconAppearance()
    }

    // MARK: - Item Activation (Left / Right Click from Bar)

    func activateHiddenItem(_ item: MenuBarHiderItem, mouseButton: CGMouseButton) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.visibilityManager.withTemporarilyRevealedItem(item) { validate in
                    let deadline = ContinuousClock.now.advanced(by: .seconds(4))
                    var attempt = 0
                    repeat {
                        try validate()
                        let descriptors = await MenuBarHiderBackend.refreshEnumeration(force: attempt > 0)
                        attempt += 1
                        let hasRenderedSnapshot = await MenuBarHiderBackend.refreshRenderedSnapshot()
                        let latest = descriptors
                            .map(MenuBarHiderItem.init(handle:))
                            .first { hasRenderedSnapshot && $0.stableID == item.stableID && $0.isOnScreen }
                        try validate()
                        if let latest {
                            try await self.clickHostedItem(latest, with: mouseButton, preferPhysicalClick: true)
                            return
                        }
                        try await Task.sleep(for: .milliseconds(150))
                    } while ContinuousClock.now < deadline
                    throw MenuBarHiderVisibilityManager.RevealError.unavailable
                }
            } catch is CancellationError {
                // Superseded by another click, pause, or shutdown.
            } catch {
                self.presentActivationFailure(item, error: error, mouseButton: mouseButton)
            }
        }
    }

    private func clickHostedItem(
        _ item: MenuBarHiderItem,
        with mouseButton: CGMouseButton,
        preferPhysicalClick: Bool
    ) async throws {
        guard await MenuBarHiderBackend.refreshRenderedSnapshot() else {
            throw MenuBarHiderVisibilityManager.RevealError.unavailable
        }
        try Task.checkCancellation()
        if mouseButton == .left, !preferPhysicalClick, item.handle.performPress() {
            return
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let cursorLocation = MenuBarHiderCursor.locationCoreGraphics,
              let frame = item.handle.currentFrame
        else {
            throw MenuBarHiderVisibilityManager.RevealError.unavailable
        }
        let eventTypes: (down: CGEventType, up: CGEventType) = switch mouseButton {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let down = CGEvent(mouseEventSource: source, mouseType: eventTypes.down,
                                 mouseCursorPosition: point, mouseButton: mouseButton),
              let up = CGEvent(mouseEventSource: source, mouseType: eventTypes.up,
                               mouseCursorPosition: point, mouseButton: mouseButton)
        else {
            throw MenuBarHiderVisibilityManager.RevealError.unavailable
        }
        MenuBarHiderCursor.hide()
        defer {
            MenuBarHiderCursor.warp(to: cursorLocation)
            MenuBarHiderCursor.show()
        }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(20))
        try Task.checkCancellation()
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(20))
        up.post(tap: .cghidEventTap)
        try Task.checkCancellation()
    }

    private func presentActivationFailure(_ item: MenuBarHiderItem, error: Error, mouseButton: CGMouseButton) {
        Self.logger.error("Failed to open hosted menu bar item: \(error.localizedDescription, privacy: .public)")
        let s = FeatureStrings.menuBarHider(L10n.shared.language)
        let alert = NSAlert()
        alert.messageText = String(format: s.alertOpenFailedFormat, item.displayName)
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: s.alertRetry)
        if item.owningApplication?.bundleURL != nil {
            alert.addButton(withTitle: s.alertOpenApp)
        }
        alert.addButton(withTitle: s.alertCancel)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            activateHiddenItem(item, mouseButton: mouseButton)
        } else if response == .alertSecondButtonReturn, let url = item.owningApplication?.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: - Trigger Status Item

    var triggerStatusItemWindow: NSWindow? {
        triggerStatusItem?.button?.window
    }

    func triggerIconAnchorX(on screen: NSScreen) -> CGFloat? {
        let displayBounds = CGDisplayBounds(screen.displayID)
        if let frame = MenuBarHiderBackend.renderedItemFrames(
            for: ProcessInfo.processInfo.processIdentifier,
            matchingIdentity: Self.triggerAutosaveName
        ).first(where: { $0.intersects(displayBounds) }) {
            return frame.midX
        }
        if let windowFrame = triggerStatusItem?.button?.window?.frame,
           windowFrame.width > 1,
           screen.frame.intersects(windowFrame) {
            return windowFrame.midX
        }
        return nil
    }

    private func syncTriggerStatusItem() {
        if running && showTriggerIcon {
            installTriggerStatusItemIfNeeded()
            updateTriggerIconAppearance()
        } else {
            removeTriggerStatusItem()
        }
    }

    private func installTriggerStatusItemIfNeeded() {
        guard triggerStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.triggerAutosaveName
        item.behavior = []
        item.isVisible = true
        triggerStatusItem = item
        if let button = item.button {
            bindTriggerButton(button)
        }
        updateTriggerIconAppearance()
        configureTriggerHostedClickMonitor()
        // AppKit on macOS 27 may realize hosted status buttons asynchronously.
        for delay in [0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.running, let button = self.triggerStatusItem?.button else { return }
                self.bindTriggerButton(button)
                self.updateTriggerIconAppearance()
            }
        }
    }

    private func bindTriggerButton(_ button: NSStatusBarButton) {
        button.setAccessibilityIdentifier(Self.triggerAutosaveName)
        button.target = self
        button.action = #selector(triggerStatusButtonClicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        button.isEnabled = true
    }

    private func updateTriggerIconAppearance() {
        guard let button = triggerStatusItem?.button else { return }
        let symbolName: String
        if isHidingPaused {
            symbolName = "eye"
        } else if isBarPresented {
            symbolName = "chevron.down"
        } else {
            symbolName = "chevron.left"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        let s = FeatureStrings.menuBarHider(L10n.shared.language)
        button.toolTip = s.triggerTooltip
    }

    private func removeTriggerStatusItem() {
        if let triggerHostedClickMonitor {
            NSEvent.removeMonitor(triggerHostedClickMonitor)
            self.triggerHostedClickMonitor = nil
        }
        if let item = triggerStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            triggerStatusItem = nil
        }
    }

    @objc private func triggerStatusButtonClicked() {
        guard let event = NSApp.currentEvent else {
            routeTriggerClick(button: .primary, modifiers: [], on: MenuBarHiderScreenGeometry.screenWithMouse, appKitPoint: MenuBarHiderCursor.locationAppKit)
            return
        }
        let button: MenuBarHiderClickPolicy.Button = (event.type == .rightMouseUp || event.type == .rightMouseDown) ? .secondary : .primary
        let modifiers = MenuBarHiderClickPolicy.ModifierSnapshot(
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
        routeTriggerClick(
            button: button,
            modifiers: modifiers,
            on: MenuBarHiderScreenGeometry.screenWithMouse,
            appKitPoint: MenuBarHiderCursor.locationAppKit
        )
    }

    private func configureTriggerHostedClickMonitor() {
        guard triggerHostedClickMonitor == nil else { return }
        triggerHostedClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.triggerStatusItem != nil,
                      let cgPoint = event.cgEvent?.location ?? MenuBarHiderCursor.locationCoreGraphics
                else { return }
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let frames = MenuBarHiderBackend.renderedItemFrames(
                    for: ownPID,
                    matchingIdentity: Self.triggerAutosaveName
                )
                guard frames.contains(where: { $0.insetBy(dx: -2, dy: -4).contains(cgPoint) }) else {
                    return
                }
                let button: MenuBarHiderClickPolicy.Button = event.type == .rightMouseDown ? .secondary : .primary
                let modifiers = MenuBarHiderClickPolicy.ModifierSnapshot(
                    option: event.modifierFlags.contains(.option),
                    control: event.modifierFlags.contains(.control)
                )
                let screen = NSScreen.screens.first(where: { CGDisplayBounds($0.displayID).contains(cgPoint) })
                    ?? MenuBarHiderScreenGeometry.screenWithMouse
                self.routeTriggerClick(
                    button: button,
                    modifiers: modifiers,
                    on: screen,
                    appKitPoint: event.cgEvent?.unflippedLocation ?? MenuBarHiderCursor.locationAppKit
                )
            }
        }
    }

    private func routeTriggerClick(
        button: MenuBarHiderClickPolicy.Button,
        modifiers: MenuBarHiderClickPolicy.ModifierSnapshot,
        on screen: NSScreen?,
        appKitPoint: CGPoint?
    ) {
        let now = Date.now
        guard now.timeIntervalSince(lastTriggerClickDate) > 0.18 else { return }
        lastTriggerClickDate = now

        let action = MenuBarHiderClickPolicy.resolve(
            button: button,
            modifiers: modifiers,
            allowsAlwaysHidden: enableAlwaysHiddenSection && canToggleAlwaysHiddenWithOption
        )
        switch action {
        case .showMenu:
            showContextMenu(at: appKitPoint ?? NSEvent.mouseLocation)
        case .toggleAlwaysHidden:
            toggleBar(section: .alwaysHidden, on: screen)
        case .toggleHidden:
            toggleBar(section: .hidden, on: screen)
        }
    }

    // MARK: - Context Menu

    func showContextMenu(at point: CGPoint) {
        let s = FeatureStrings.menuBarHider(L10n.shared.language)
        let menu = NSMenu(title: s.title)

        let hiddenOpen = barPanel.isVisible && barPanel.currentSection == .hidden
        let toggleHidden = NSMenuItem(
            title: hiddenOpen ? s.menuCollapseHidden : s.menuExpandHidden,
            action: #selector(menuToggleHiddenBar),
            keyEquivalent: ""
        )
        toggleHidden.target = self
        menu.addItem(toggleHidden)

        if enableAlwaysHiddenSection {
            let alwaysOpen = barPanel.isVisible && barPanel.currentSection == .alwaysHidden
            let toggleAlways = NSMenuItem(
                title: alwaysOpen ? s.menuCollapseAlwaysHidden : s.menuExpandAlwaysHidden,
                action: #selector(menuToggleAlwaysHiddenBar),
                keyEquivalent: ""
            )
            toggleAlways.target = self
            menu.addItem(toggleAlways)
        }

        let pauseItem = NSMenuItem(
            title: isHidingPaused ? s.menuResumeHiding : s.menuPauseHiding,
            action: #selector(menuTogglePauseHiding),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let manageItem = NSMenuItem(
            title: s.menuManageIcons,
            action: #selector(menuOpenSettings),
            keyEquivalent: ""
        )
        manageItem.target = self
        menu.addItem(manageItem)

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func menuToggleHiddenBar() {
        toggleBar(section: .hidden)
    }

    @objc private func menuToggleAlwaysHiddenBar() {
        toggleBar(section: .alwaysHidden)
    }

    @objc private func menuTogglePauseHiding() {
        toggleHidingPaused()
    }

    @objc private func menuOpenSettings() {
        closeBar()
        onOpenSettings?()
    }

    // MARK: - Event Monitors (Empty Menu Bar Click, Smart Rehide, Clock Bridge)

    private func startEventMonitors() {
        stopEventMonitors()

        mouseDownMonitor = MenuBarHiderUniversalMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, !self.isSynthesizingClockClick else { return event }
            switch event.type {
            case .leftMouseDown:
                self.handleClockMouseDown(with: event)
                self.handleEmptySpaceLeftClick(with: event)
                self.handleSmartRehide(with: event)
            case .rightMouseDown:
                self.handleEmptySpaceRightClick(with: event)
            default:
                break
            }
            return event
        }

        mouseUpMonitor = MenuBarHiderUniversalMonitor(mask: .leftMouseUp) { [weak self] event in
            guard let self, !self.isSynthesizingClockClick else { return event }
            self.handleClockMouseUp(with: event)
            return event
        }

        mouseDownMonitor?.start()
        mouseUpMonitor?.start()
    }

    private func stopEventMonitors() {
        clockActivationTask?.cancel()
        clockActivationTask = nil
        clockMouseDownPoint = nil
        clockBaselineWindowIDs.removeAll()
        isSynthesizingClockClick = false
        mouseDownMonitor?.stop()
        mouseUpMonitor?.stop()
        mouseDownMonitor = nil
        mouseUpMonitor = nil
    }

    private func handleEmptySpaceLeftClick(with event: NSEvent) {
        guard showOnEmptyClick, let click = menuBarClick(with: event) else { return }
        let modifiers = MenuBarHiderClickPolicy.ModifierSnapshot(
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
        Task { @MainActor [weak self] in
            guard let self,
                  await self.isEmptyMenuBarClick(at: click.point, appKitPoint: click.appKitPoint, on: click.screen),
                  self.showOnEmptyClick
            else { return }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard let screen = NSScreen.screens.first(where: { $0.displayID == click.screen.displayID }) else { return }
            let action = MenuBarHiderClickPolicy.resolve(
                button: .primary,
                modifiers: modifiers,
                allowsAlwaysHidden: self.enableAlwaysHiddenSection && self.canToggleAlwaysHiddenWithOption
            )
            switch action {
            case .showMenu:
                self.showContextMenu(at: click.appKitPoint)
            case .toggleAlwaysHidden:
                self.toggleBar(section: .alwaysHidden, on: screen, menuBarClickX: click.point.x)
            case .toggleHidden:
                self.toggleBar(section: .hidden, on: screen, menuBarClickX: click.point.x)
            }
        }
    }

    private func handleEmptySpaceRightClick(with event: NSEvent) {
        guard showOnEmptyClick, let click = menuBarClick(with: event) else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  await self.isEmptyMenuBarClick(at: click.point, appKitPoint: click.appKitPoint, on: click.screen),
                  self.showOnEmptyClick
            else { return }
            self.showContextMenu(at: click.appKitPoint)
        }
    }

    private func handleSmartRehide(with event: NSEvent) {
        guard autoRehide, rehideStrategy == .smart else { return }
        guard barPanel.isVisible else { return }
        guard event.window !== triggerStatusItemWindow else { return }
        guard event.window !== barPanel else { return }
        guard !isMouseInsideMenuBar else { return }

        let generation = barPanel.presentationGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let initialSpace = MenuBarHiderPrivateBridge.activeSpaceID
            try? await Task.sleep(for: .milliseconds(250))
            guard generation == self.barPanel.presentationGeneration else { return }
            if MenuBarHiderPrivateBridge.activeSpaceID != initialSpace {
                self.closeBar()
                return
            }
            guard let mouseLocation = MenuBarHiderCursor.locationCoreGraphics,
                  let windowUnderMouse = MenuBarHiderWindowInfo.getOnScreenWindows(excludeDesktopWindows: false)
                    .filter({ $0.layer < Int(CGWindowLevelForKey(.cursorWindow)) })
                    .first(where: {
                        $0.frame.contains(mouseLocation)
                            && $0.alpha > 0
                            && $0.windowID != kCGNullWindowID
                            && !$0.isWindowServerWindow
                    }),
                  let owningApp = windowUnderMouse.owningApplication
            else { return }

            if owningApp.bundleIdentifier != "com.apple.dock" {
                guard owningApp.isActive, owningApp.activationPolicy == .regular else { return }
            }
            self.closeBar()
        }
    }

    private func handleFrontmostAppChanged() {
        guard running, autoRehide, rehideStrategy == .focusedApp, barPanel.isVisible,
              !isMouseInsideMenuBar, !isMouseInsideBar
        else { return }
        Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, self.autoRehide, self.rehideStrategy == .focusedApp,
                  !self.isMouseInsideMenuBar, !self.isMouseInsideBar
            else { return }
            self.closeBar()
        }
    }

    private func startRehideChecksIfNeeded() {
        stopRehideChecks()
        guard autoRehide, rehideStrategy == .timed else { return }

        let armTimerIfNeeded: @MainActor () -> Void = { [weak self] in
            guard let self, self.barPanel.isVisible else { return }
            let inside = self.isMouseInsideMenuBar || self.isMouseInsideBar
            if !inside {
                if self.timedRehideTimer == nil {
                    self.timedRehideTimer = .scheduledTimer(withTimeInterval: self.rehideInterval, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.timedRehideTimer = nil
                            if !(self.isMouseInsideMenuBar || self.isMouseInsideBar) {
                                self.closeBar()
                            } else {
                                self.startRehideChecksIfNeeded()
                            }
                        }
                    }
                }
            } else {
                self.timedRehideTimer?.invalidate()
                self.timedRehideTimer = nil
            }
        }

        armTimerIfNeeded()
        timedRehideMonitor = MenuBarHiderUniversalMonitor(mask: .mouseMoved) { event in
            Task { @MainActor in armTimerIfNeeded() }
            return event
        }
        timedRehideMonitor?.start()
    }

    private func stopRehideChecks() {
        timedRehideTimer?.invalidate()
        timedRehideTimer = nil
        timedRehideMonitor?.stop()
        timedRehideMonitor = nil
    }

    // MARK: - macOS 27+ Clock / Notification Center Pass-Through

    private func handleClockMouseDown(with event: NSEvent) {
        clockMouseDownPoint = nil
        clockBaselineWindowIDs.removeAll()
        guard visibilityManager.needsClockActivationBridge,
              clockActivationTask == nil,
              event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              let location = event.cgEvent?.location ?? MenuBarHiderCursor.locationCoreGraphics,
              isMouseInsideMenuBar || Self.isPointInMenuBarBand(location)
        else { return }

        if MenuBarHiderBackend.renderedItemFrameSnapshot() != nil,
           MenuBarHiderBackend.systemClockFrame(at: location) == nil {
            return
        }
        guard !Self.isClockPanelOpen() else { return }
        clockBaselineWindowIDs = Set(MenuBarHiderWindowInfo.getOnScreenWindows().map(\.windowID))
        clockMouseDownPoint = location
    }

    private func handleClockMouseUp(with event: NSEvent) {
        guard let downPoint = clockMouseDownPoint else { return }
        let baselineIDs = clockBaselineWindowIDs
        clockMouseDownPoint = nil
        clockBaselineWindowIDs.removeAll()
        guard let location = event.cgEvent?.location ?? MenuBarHiderCursor.locationCoreGraphics,
              hypot(location.x - downPoint.x, location.y - downPoint.y) <= 6,
              let screen = NSScreen.screens.first(where: {
                  CGDisplayBounds($0.displayID).insetBy(dx: -2, dy: -2).contains(location)
              })
        else { return }

        let visibility = visibilityManager
        clockActivationTask = Task { @MainActor [weak self] in
            defer { self?.clockActivationTask = nil }
            guard await !Self.waitForClockPanel(baselineWindowIDs: baselineIDs, within: .milliseconds(80)),
                  !Task.isCancelled
            else { return }

            if MenuBarHiderBackend.systemClockFrame(at: downPoint) == nil {
                guard await MenuBarHiderBackend.refreshRenderedSnapshot() else { return }
            }
            guard let initialClockFrame = MenuBarHiderBackend.systemClockFrame(at: downPoint, allowingStale: true),
                  MenuBarHiderBackend.systemClockFrame(at: location, allowingStale: true) != nil,
                  visibility.beginClockActivationBridge()
            else { return }
            defer { visibility.endClockActivationBridge() }
            self?.closeBar()

            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }

            var didActivate = Self.isClockPanelOpen(baselineWindowIDs: baselineIDs)
            for attempt in 0..<3 where !didActivate {
                guard !Task.isCancelled else { return }
                _ = await MenuBarHiderBackend.refreshRenderedSnapshot()
                if Self.isClockPanelOpen(baselineWindowIDs: baselineIDs) {
                    didActivate = true
                    break
                }
                let clockFrame = MenuBarHiderBackend.systemClockFrame(on: screen.displayID) ?? initialClockFrame
                let clickPoint = CGPoint(x: clockFrame.midX, y: clockFrame.midY)
                guard await self?.postSyntheticClockClick(at: clickPoint) == true else { break }
                let waitBudget: Duration = attempt == 0 ? .milliseconds(160) : .milliseconds(320)
                if await Self.waitForClockPanel(baselineWindowIDs: baselineIDs, within: waitBudget) {
                    didActivate = true
                    break
                }
            }
            guard didActivate else { return }

            var session = MenuBarHiderClockSession()
            let started = ContinuousClock.now
            while true {
                guard !Task.isCancelled else { return }
                let isOpen = Self.isClockPanelOpen(baselineWindowIDs: baselineIDs)
                switch session.observe(isOpen: isOpen, elapsed: started.duration(to: .now)) {
                case .restore:
                    return
                case .wait(let interval):
                    do { try await Task.sleep(for: interval) } catch { return }
                }
            }
        }
    }

    private func postSyntheticClockClick(at point: CGPoint) async -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let cursorLocation = MenuBarHiderCursor.locationCoreGraphics,
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left)
        else { return false }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        isSynthesizingClockClick = true
        MenuBarHiderCursor.hide()
        defer {
            MenuBarHiderCursor.warp(to: cursorLocation)
            MenuBarHiderCursor.show()
            isSynthesizingClockClick = false
        }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        do { try await Task.sleep(for: .milliseconds(15)) } catch { return false }
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(20))
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(25))
        return !Task.isCancelled
    }

    private static func isPointInMenuBarBand(_ point: CGPoint) -> Bool {
        NSScreen.screens.contains { screen in
            let bounds = CGDisplayBounds(screen.displayID).insetBy(dx: -2, dy: -2)
            return bounds.contains(point) && point.y <= bounds.minY + 52
        }
    }

    private static func waitForClockPanel(baselineWindowIDs: Set<CGWindowID>, within timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return false }
            if isClockPanelOpen(baselineWindowIDs: baselineWindowIDs) { return true }
        } while ContinuousClock.now < deadline
        return false
    }

    private static func isClockPanelOpen(baselineWindowIDs: Set<CGWindowID> = []) -> Bool {
        let displayBounds = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        let floatingLayer = Int(CGWindowLevelForKey(.floatingWindow))
        let windows = MenuBarHiderWindowInfo.getOnScreenWindows().map { window in
            MenuBarHiderClockSession.SystemWindowSnapshot(
                id: window.windowID,
                bundleIdentifier: window.owningApplication?.bundleIdentifier,
                title: window.title,
                frame: window.frame,
                layer: window.layer,
                alpha: window.alpha
            )
        }
        return MenuBarHiderClockSession.isClockPanelOpen(
            windows: windows,
            baselineWindowIDs: baselineWindowIDs,
            floatingLayerMinimum: floatingLayer,
            displayBounds: displayBounds
        )
    }

    // MARK: - Geometry & Empty-Space Detection

    var isMouseInsideMenuBar: Bool {
        guard let screen = MenuBarHiderScreenGeometry.screenWithMouse ?? NSScreen.main,
              let cursor = CGEvent(source: nil)
        else { return false }
        return isInsideMenuBar(on: screen, at: cursor.location, appKitPoint: cursor.unflippedLocation)
    }

    var isMouseInsideBar: Bool {
        guard barPanel.isVisible,
              let mouseLocation = MenuBarHiderCursor.locationAppKit
        else { return false }
        return barPanel.frame.insetBy(dx: -10, dy: -10).contains(mouseLocation)
    }

    var isMouseInsideEmptyMenuBarSpace: Bool {
        guard isMouseInsideMenuBar,
              let screen = MenuBarHiderScreenGeometry.screenWithMouse ?? NSScreen.main,
              let point = MenuBarHiderCursor.locationCoreGraphics,
              let appKitPoint = MenuBarHiderCursor.locationAppKit
        else { return false }
        if isOverNotchOrVorssaintUI(appKitPoint: appKitPoint, on: screen) { return false }
        let menuFrame = getApplicationMenuFrame(for: screen.displayID)
        guard MenuBarHiderAppMenuGeometry.isEmptySpace(at: point, applicationMenuFrame: menuFrame) else { return false }
        return MenuBarHiderAppMenuGeometry.isEmptyHostedSpace(
            at: point,
            applicationMenuFrame: menuFrame,
            itemFrames: MenuBarHiderBackend.renderedItemFrameSnapshot(),
            displayBounds: CGDisplayBounds(screen.displayID)
        )
    }

    private func menuBarClick(with event: NSEvent) -> (screen: NSScreen, point: CGPoint, appKitPoint: CGPoint)? {
        guard let cgEvent = event.cgEvent,
              let screen = NSScreen.screens.first(where: { CGDisplayBounds($0.displayID).contains(cgEvent.location) }),
              isInsideMenuBar(on: screen, at: cgEvent.location, appKitPoint: cgEvent.unflippedLocation),
              !isOverNotchOrVorssaintUI(appKitPoint: cgEvent.unflippedLocation, on: screen)
        else { return nil }
        return (screen, cgEvent.location, cgEvent.unflippedLocation)
    }

    /// Excludes hardware notch, Vorssaint Dynamic Island, Vorssaint's own status items,
    /// and our trigger status item so clicking them never triggers an empty-space toggle.
    private func isOverNotchOrVorssaintUI(appKitPoint: CGPoint, on screen: NSScreen) -> Bool {
        if MenuBarHiderScreenGeometry.frameOfNotch(for: screen)?.contains(appKitPoint) == true {
            return true
        }
        if AppFeature.notch.isAvailable, NotchService.shared.containsMenuBarPoint(appKitPoint) {
            return true
        }
        if vorssaintStatusItemContainsPoint?(appKitPoint) == true {
            return true
        }
        if let triggerFrame = triggerStatusItem?.button?.window?.frame,
           triggerFrame.width > 1,
           triggerFrame.insetBy(dx: -4, dy: -8).contains(appKitPoint) {
            return true
        }
        return false
    }

    private func isEmptyMenuBarClick(at point: CGPoint, appKitPoint: CGPoint, on screen: NSScreen) async -> Bool {
        if isOverNotchOrVorssaintUI(appKitPoint: appKitPoint, on: screen) {
            return false
        }
        let displayID = screen.displayID
        let bounds = CGDisplayBounds(displayID)
        let menuOwner = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        let menuFrame = getApplicationMenuFrame(for: displayID, maxAge: .zero)
        guard MenuBarHiderAppMenuGeometry.isEmptySpace(at: point, applicationMenuFrame: menuFrame) else {
            return false
        }
        if MenuBarHiderBackend.renderedItemFrameSnapshot() == nil {
            guard await MenuBarHiderBackend.refreshRenderedSnapshot() else { return false }
        }
        guard !Task.isCancelled,
              NSWorkspace.shared.menuBarOwningApplication?.processIdentifier == menuOwner,
              NSScreen.screens.contains(where: { $0.displayID == displayID })
        else { return false }
        return MenuBarHiderAppMenuGeometry.isEmptyHostedSpace(
            at: point,
            applicationMenuFrame: menuFrame,
            itemFrames: MenuBarHiderBackend.renderedItemFrameSnapshot(),
            displayBounds: bounds
        )
    }

    private func isInsideMenuBar(on screen: NSScreen, at point: CGPoint, appKitPoint: CGPoint) -> Bool {
        if !isMenuBarHiddenBySystem,
           !MenuBarHiderPrivateBridge.isActiveSpaceFullscreen,
           screen.visibleFrame.maxY < screen.frame.maxY {
            return MenuBarHiderScreenGeometry.menuBarContains(appKitPoint, on: screen)
        }
        return menuBarWindowFrame(for: screen.displayID)?.contains(point) == true
    }

    private func menuBarWindowFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        let now = ContinuousClock.now
        if let cached = menuBarWindowFrameCache, cached.displayID == displayID,
           cached.date.duration(to: now) < .milliseconds(100) {
            return cached.frame
        }
        let frame = MenuBarHiderWindowInfo.getMenuBarWindow(for: displayID)?.frame
        menuBarWindowFrameCache = (displayID, now, frame)
        return frame
    }

    private func getApplicationMenuFrame(
        for displayID: CGDirectDisplayID,
        maxAge: Duration = MenuBarHiderService.applicationMenuFrameCacheLifetime
    ) -> CGRect? {
        let key = ApplicationMenuFrameKey(
            ownerPID: NSWorkspace.shared.menuBarOwningApplication?.processIdentifier ?? 0,
            displayID: displayID
        )
        let now = ContinuousClock.now
        if maxAge > .zero, let cached = applicationMenuFrameCache[key], cached.date.duration(to: now) < maxAge {
            return cached.frame
        }
        let frame = readApplicationMenuFrame(for: displayID)
        if applicationMenuFrameCache.count > 16 {
            applicationMenuFrameCache.removeAll()
        }
        applicationMenuFrameCache[key] = (now, frame)
        return frame
    }

    private func readApplicationMenuFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)
        var ownerMenuBar: AXUIElement?

        if let owner = NSWorkspace.shared.menuBarOwningApplication {
            let application = AXUIElementCreateApplication(owner.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.05)
            ownerMenuBar = MenuBarHiderBackend.attribute(kAXMenuBarAttribute, of: application)
            if let ownerMenuBar,
               let frame = applicationMenuFrame(from: ownerMenuBar, displayBounds: displayBounds) {
                return frame
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(displayBounds.minX + 1),
            Float(displayBounds.minY + 12),
            &hitElement
        ) == .success,
              let menuBar = hitElement,
              let role: String = MenuBarHiderBackend.attribute(kAXRoleAttribute, of: menuBar),
              role == kAXMenuBarRole as String
        else { return nil }

        if let frame = applicationMenuFrame(from: menuBar, displayBounds: displayBounds) {
            return frame
        }
        guard let ownerMenuBar, CFEqual(menuBar, ownerMenuBar),
              let proxyFrame = axFrame(of: menuBar),
              let sourceScreen = NSScreen.screens.first(where: { screen in
                  screen.displayID != displayID && CGDisplayBounds(screen.displayID).origin == proxyFrame.origin
              }),
              let sourceFrame = applicationMenuFrame(from: menuBar, displayBounds: CGDisplayBounds(sourceScreen.displayID))
        else { return nil }
        return MenuBarHiderAppMenuGeometry.projectedFrame(sourceFrame, on: displayBounds)
    }

    private func applicationMenuFrame(from menuBar: AXUIElement, displayBounds: CGRect) -> CGRect? {
        AXUIElementSetMessagingTimeout(menuBar, 0.05)
        guard let items: [AXUIElement] = MenuBarHiderBackend.attribute(kAXChildrenAttribute, of: menuBar),
              !items.isEmpty
        else { return nil }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        var frames = [CGRect]()
        for item in items {
            guard ContinuousClock.now < deadline else { return nil }
            AXUIElementSetMessagingTimeout(item, 0.05)
            guard let frame = axFrame(of: item) else { return nil }
            frames.append(frame)
        }
        return MenuBarHiderAppMenuGeometry.frame(itemFrames: frames, displayBounds: displayBounds)
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        if let axValue: AXValue = MenuBarHiderBackend.attribute("AXFrame", of: element),
           AXValueGetType(axValue) == .cgRect {
            var rect = CGRect.zero
            if AXValueGetValue(axValue, .cgRect, &rect) {
                return rect
            }
        }
        return MenuBarHiderBackend.frame(of: element)
    }

    // MARK: - Persistence & Cache

    private func refreshSystemMenuBarHiddenDefaults() {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let isHidden = (globalDomain?["_HIHideMenuBar"] as? Bool) ?? false
        if isMenuBarHiddenBySystemUserDefaults != isHidden {
            isMenuBarHiddenBySystemUserDefaults = isHidden
        }
    }

    private func mergeDiscoveredItems(
        discovered: [MenuBarHiderItem],
        scannedPIDs: Set<pid_t>,
        concealedBundles: Set<String>
    ) {
        let livePIDs = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map(\.processIdentifier))
        itemSnapshots = MenuBarHiderSnapshotPolicy.merge(
            existing: itemSnapshots,
            discovered: discovered,
            liveOwners: livePIDs,
            scannedOwners: scannedPIDs,
            id: { $0.stableID },
            owner: { $0.ownerPID },
            preserveMissing: { item in
                item.bundleIdentifier.map { concealedBundles.contains($0) } ?? false
            }
        )
        rebuildItemCache()
    }

    private func rebuildItemCache() {
        var grouped: [MenuBarHiderSection: [MenuBarHiderItem]] = [:]
        let alwaysEnabled = enableAlwaysHiddenSection
        for item in itemSnapshots.values {
            let ownerKey = item.bundleIdentifier.map { "bundle:" + $0 }
            var section = ownerKey.flatMap { sectionAssignments[$0] }
                ?? sectionAssignments[item.stableID]
                ?? .visible
            if !item.canBeHidden {
                section = .visible
            }
            if section == .alwaysHidden && !alwaysEnabled {
                section = .visible
            }
            grouped[section, default: []].append(item)
        }
        for section in MenuBarHiderSection.allCases {
            grouped[section] = (grouped[section] ?? []).sorted { lhs, rhs in
                let cmp = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return lhs.stableID < rhs.stableID
            }
        }
        if grouped != itemsBySection {
            itemsBySection = grouped
        }
    }

    private func loadPersistedAssignments() {
        let stored = UserDefaults.standard.dictionary(forKey: DefaultsKey.menuBarHiderAssignments) as? [String: String]
        sectionAssignments = MenuBarHiderSupport.decodeAssignments(stored)
    }

    private func persistAssignments() {
        UserDefaults.standard.set(
            MenuBarHiderSupport.encodeAssignments(sectionAssignments),
            forKey: DefaultsKey.menuBarHiderAssignments
        )
    }
}
