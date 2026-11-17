// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

/// Registers per-application global Carbon hotkeys and executes their wake /
/// frontmost actions without keeping any event tap or background timer alive.
final class AppHotkeysService: ObservableObject {
    static let shared = AppHotkeysService()

    @Published private(set) var entries: [AppHotkeyEntry] = []
    @Published private(set) var refusedBundleIDs: Set<String> = []
    @Published private(set) var runningBundleIDs: Set<String> = []

    private var hotkeys: [QuickToolHotkey] = []
    private var activationObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var observingSurfaceIDs: Set<UUID> = []
    private var currentFrontmostPID: pid_t?
    private var previousFrontmostPID: pid_t?

    private init() {
        entries = AppHotkeysSupport.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.appHotkeysEntries)
        )
    }

    var activeShortcutCount: Int {
        guard AppFeature.appHotkeys.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.appHotkeysEnabled) else {
            return 0
        }
        return AppHotkeysSupport.activeShortcuts(in: entries).count
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let decoded = AppHotkeysSupport.decode(defaults.data(forKey: DefaultsKey.appHotkeysEntries))
        if decoded != entries {
            entries = decoded
        }

        let isActive = AppFeature.appHotkeys.isAvailable
            && defaults.bool(forKey: DefaultsKey.appHotkeysEnabled)

        unregisterHotkeys()

        guard isActive else {
            if !refusedBundleIDs.isEmpty { refusedBundleIDs = [] }
            stopTrackingFrontmostApp()
            return
        }

        let bindings = AppHotkeysSupport.activeShortcuts(in: decoded)
        guard !bindings.isEmpty else {
            if !refusedBundleIDs.isEmpty { refusedBundleIDs = [] }
            stopTrackingFrontmostApp()
            return
        }

        startTrackingFrontmostAppIfNeeded()

        var nextRefused: Set<String> = []
        for (offset, binding) in bindings.enumerated() {
            let hotkey = QuickToolHotkey(id: AppHotkeysSupport.baseHotkeyID + UInt32(offset))
            let bundleID = binding.bundleID
            hotkey.onPress = { [weak self] in
                self?.trigger(bundleID: bundleID)
            }
            let storageKey = AppHotkeysSupport.storageKey(for: bundleID)
            if !hotkey.sync(enabled: true, shortcut: binding.shortcut, storageKey: storageKey) {
                nextRefused.insert(bundleID)
            }
            hotkeys.append(hotkey)
        }
        if nextRefused != refusedBundleIDs {
            refusedBundleIDs = nextRefused
        }
    }

    func suspend() {
        unregisterHotkeys()
        if !refusedBundleIDs.isEmpty { refusedBundleIDs = [] }
        stopTrackingFrontmostApp()
        stopObservingRunningApps()
    }

    private func unregisterHotkeys() {
        for hotkey in hotkeys {
            hotkey.unregister()
        }
        hotkeys = []
    }

    // MARK: - Live Running State for Settings UI

    func setObservingRunningApps(_ surfaceID: UUID, visible: Bool) {
        if visible {
            observingSurfaceIDs.insert(surfaceID)
            refreshRunningApps()
            startObservingRunningAppsIfNeeded()
        } else {
            observingSurfaceIDs.remove(surfaceID)
            if observingSurfaceIDs.isEmpty {
                stopObservingRunningApps()
            }
        }
    }

    func refreshRunningApps() {
        let ids = Set(
            NSWorkspace.shared.runningApplications.compactMap { app -> String? in
                guard app.activationPolicy == .regular, !app.isTerminated else { return nil }
                return app.bundleIdentifier
            }
        )
        if ids != runningBundleIDs {
            runningBundleIDs = ids
        }
    }

    private func startObservingRunningAppsIfNeeded() {
        let center = NSWorkspace.shared.notificationCenter
        if launchObserver == nil {
            launchObserver = center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshRunningApps()
            }
        }
        if terminateObserver == nil {
            terminateObserver = center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshRunningApps()
            }
        }
    }

    private func stopObservingRunningApps() {
        let center = NSWorkspace.shared.notificationCenter
        if let launchObserver {
            center.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        if let terminateObserver {
            center.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
    }

    // MARK: - Frontmost Tracking for Hide & Return

    private func startTrackingFrontmostAppIfNeeded() {
        guard activationObserver == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           Self.isTrackableRegularApp(front) {
            currentFrontmostPID = front.processIdentifier
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  !ActivationHandoff.isHandingOff,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  Self.isTrackableRegularApp(app) else { return }
            let pid = app.processIdentifier
            if let current = self.currentFrontmostPID, current != pid {
                self.previousFrontmostPID = current
            }
            self.currentFrontmostPID = pid
        }
    }

    private func stopTrackingFrontmostApp() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        currentFrontmostPID = nil
        previousFrontmostPID = nil
    }

    private static func isTrackableRegularApp(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, !app.isTerminated else { return false }
        let bundleID = app.bundleIdentifier
        return bundleID != Bundle.main.bundleIdentifier
            && bundleID != AssistiveKeyboard.bundleID
    }

    private func previousRegularApp(excluding excludedPID: pid_t) -> NSRunningApplication? {
        if let previousPID = previousFrontmostPID,
           previousPID != excludedPID,
           let app = NSRunningApplication(processIdentifier: previousPID),
           Self.isTrackableRegularApp(app),
           !app.isHidden {
            return app
        }
        // Fallback before any activation change has been observed since launch:
        // inspect WindowServer z-order for the topmost visible regular app behind us.
        let ownPID = getpid()
        for entry in WindowServerSupport.onScreenWindowInfo() {
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != excludedPID, pid != ownPID,
                  let app = NSRunningApplication(processIdentifier: pid),
                  Self.isTrackableRegularApp(app),
                  !app.isHidden else { continue }
            return app
        }
        return nil
    }

    // MARK: - Configuration & Conflict Detection

    func displayName(for entry: AppHotkeyEntry) -> String {
        let resolved = InstalledApps.name(for: entry.bundleID)
        return resolved == entry.bundleID ? entry.appNameFallback : resolved
    }

    func displayName(forBundleID bundleID: String) -> String {
        if let entry = entries.first(where: { $0.bundleID == bundleID }) {
            return displayName(for: entry)
        }
        return InstalledApps.name(for: bundleID)
    }

    /// Returns the conflicting app name if `shortcut` is already claimed by an
    /// active App Hotkeys entry.
    func shortcutConflictTitle(_ shortcut: GlobalShortcut,
                               excluding excludedBundleID: String? = nil,
                               includeInactive: Bool = false) -> String? {
        guard AppFeature.appHotkeys.isAvailable else { return nil }
        let featureEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.appHotkeysEnabled)
        guard includeInactive || featureEnabled else { return nil }
        guard let ownerID = AppHotkeysSupport.ownerBundleID(
            for: shortcut,
            excluding: excludedBundleID,
            in: entries,
            includeDisabled: includeInactive
        ) else { return nil }
        let appTitle = displayName(forBundleID: ownerID)
        let featureTitle = FeatureStrings.appHotkeys(L10n.shared.language).title
        return "\(featureTitle) (\(appTitle))"
    }

    func validationError(for shortcut: GlobalShortcut, bundleID: String) -> String? {
        let strings = L10n.shared.s
        switch AppHotkeysSupport.assignmentIssue(shortcut, for: bundleID, in: entries) {
        case .invalid:
            return strings.shortcutInvalid
        case .occupiedByApp(let ownerID):
            return String(format: strings.shortcutConflictFormat, displayName(forBundleID: ownerID))
        case nil:
            break
        }
        if let role = GlobalShortcutRole.conflict(for: shortcut, excluding: nil) {
            return String(format: strings.shortcutConflictFormat, role.title(strings))
        }
        if AppFeature.windowLayout.isAvailable,
           let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            return String(format: strings.shortcutConflictFormat, conflict)
        }
        if AppFeature.commandBar.isAvailable {
            let barShortcuts = CommandBarService.shared.rowShortcuts
            if CommandBarRowShortcuts.key(for: shortcut, in: barShortcuts) != nil {
                return String(format: strings.shortcutConflictFormat,
                              FeatureStrings.commandBar(L10n.shared.language).appCenterTitle)
            }
        }
        return nil
    }

    @discardableResult
    func addApp(bundleID: String, name: String? = nil) -> AppHotkeysSupport.AddAppResult {
        let resolvedName = name ?? InstalledApps.name(for: bundleID)
        let outcome = AppHotkeysSupport.addingApp(bundleID: bundleID, name: resolvedName, to: entries)
        if case .added(let next) = outcome {
            persist(next)
        }
        return outcome
    }

    func importDockApps() -> Int {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")
            ?? UserDefaults(suiteName: "com.apple.dock")?.dictionaryRepresentation()
        let dockIDs = AppHotkeysSupport.dockBundleIDs(from: domain)
        let candidates = dockIDs.map { id in
            (bundleID: id, name: InstalledApps.name(for: id))
        }
        let outcome = AppHotkeysSupport.importingApps(candidates, into: entries)
        if outcome.addedCount > 0 {
            persist(outcome.entries)
        }
        return outcome.addedCount
    }

    func removeApp(bundleID: String) {
        let storageKey = AppHotkeysSupport.storageKey(for: bundleID)
        SystemShortcutTakeover.setTakeOver(storageKey, false)
        SystemShortcutTakeover.release(storageKey)
        let next = AppHotkeysSupport.removingApp(bundleID: bundleID, from: entries)
        persist(next)
    }

    func setAppEnabled(_ isEnabled: Bool, for bundleID: String) {
        let next = AppHotkeysSupport.settingEnabled(isEnabled, for: bundleID, in: entries)
        persist(next)
    }

    func moveEntry(bundleID: String, direction: Int) {
        let next = AppHotkeysSupport.movingEntry(bundleID: bundleID, direction: direction, in: entries)
        guard next != entries else { return }
        persist(next)
    }

    func saveShortcut(_ shortcut: GlobalShortcut?,
                      for bundleID: String,
                      takenOverSystemShortcut: Bool = false) {
        let storageKey = AppHotkeysSupport.storageKey(for: bundleID)
        SystemShortcutTakeover.setTakeOver(storageKey, shortcut != nil && takenOverSystemShortcut)
        if shortcut == nil {
            SystemShortcutTakeover.release(storageKey)
        }
        let next = AppHotkeysSupport.settingShortcut(shortcut, for: bundleID, in: entries)
        persist(next)
    }

    private func persist(_ next: [AppHotkeyEntry]) {
        let sanitized = AppHotkeysSupport.sanitizedEntries(next)
        entries = sanitized
        UserDefaults.standard.set(AppHotkeysSupport.encode(sanitized), forKey: DefaultsKey.appHotkeysEntries)
        syncWithPreferences()
    }

    // MARK: - Execution

    func trigger(bundleID: String) {
        let defaults = UserDefaults.standard
        guard AppFeature.appHotkeys.isAvailable,
              defaults.bool(forKey: DefaultsKey.appHotkeysEnabled),
              entries.contains(where: { $0.bundleID == bundleID && $0.isEnabled && $0.resolvedShortcut != nil })
        else { return }

        let behavior = AppHotkeyFrontmostBehavior.sanitized(
            defaults.string(forKey: DefaultsKey.appHotkeysFrontmostBehavior)
        )
        let running = NSWorkspace.shared.runningApplications.first {
            !$0.isTerminated && $0.bundleIdentifier == bundleID
        }
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isFrontmost: Bool = {
            guard let running, !running.isHidden else { return false }
            return running.isActive || frontmostApp?.processIdentifier == running.processIdentifier
        }()
        let hasOnScreenWindows = running.map { Self.hasOnScreenStandardWindow(pid: $0.processIdentifier) } ?? false

        let decision = AppHotkeysSupport.wakeDecision(
            isRunning: running != nil,
            isHidden: running?.isHidden ?? false,
            isFrontmost: isFrontmost,
            hasOnScreenWindows: hasOnScreenWindows,
            frontmostBehavior: behavior
        )

        switch decision {
        case .launchOrActivate:
            if let frontmostApp,
               Self.isTrackableRegularApp(frontmostApp),
               frontmostApp.processIdentifier != running?.processIdentifier {
                previousFrontmostPID = frontmostApp.processIdentifier
            }
            launchOrActivateApp(bundleID: bundleID, running: running, hasOnScreenWindows: hasOnScreenWindows)

        case .hideAndReturnPrevious:
            guard let running else { return }
            hideAndReturnPrevious(running: running)

        case .cycleWindows:
            guard let running else { return }
            cycleAppWindows(running: running)

        case .keepFrontmost:
            guard let running else { return }
            if !hasOnScreenWindows {
                launchOrActivateApp(bundleID: bundleID, running: running, hasOnScreenWindows: false)
            } else {
                activateCooperatively(running)
            }
        }
    }

    private func launchOrActivateApp(bundleID: String,
                                     running: NSRunningApplication?,
                                     hasOnScreenWindows: Bool) {
        if let running {
            if running.isHidden {
                running.unhide()
            }
            if hasOnScreenWindows {
                activateCooperatively(running)
                return
            }
            // Running without an on-screen window on this Space (e.g. closed into
            // the Dock with Cmd+W, minimized, or living on another Space):
            // yield activation first and ask NSWorkspace to open the bundle URL
            // so the app receives standard reopen semantics (kAEReopenApplication).
            ActivationHandoff.yield(to: running)
            if let url = running.bundleURL ?? InstalledApps.url(for: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak running] _, error in
                    if error != nil, let running {
                        DispatchQueue.main.async {
                            if !running.activate(from: NSRunningApplication.current, options: []) {
                                running.activate(options: [])
                            }
                        }
                    }
                }
            } else {
                activateCooperatively(running)
            }
            return
        }

        guard let url = InstalledApps.url(for: bundleID) else {
            NSSound.beep()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if error != nil {
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }

    private func activateCooperatively(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        ActivationHandoff.yield(to: app)
        if !app.activate(from: NSRunningApplication.current, options: []) {
            app.activate(options: [])
        }
        currentFrontmostPID = app.processIdentifier
    }

    private func hideAndReturnPrevious(running: NSRunningApplication) {
        let pid = running.processIdentifier
        let fallback = previousRegularApp(excluding: pid)
        let didHide = running.hide()
        if !didHide, let fallback {
            activateCooperatively(fallback)
        }
    }

    private func cycleAppWindows(running: NSRunningApplication) {
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            Permissions.shared.openAccessibilitySettings()
            return
        }
        let pid = running.processIdentifier
        let unminimized = Self.unminimizedStandardWindows(pid: pid)
        let ids = unminimized.map { AXWindowResolver.windowID(for: $0) }
        let onScreen = Self.onScreenWindowIDs(pid: pid)
        let candidateIndices = DockClickSupport.cycleCandidateIndices(
            windowIDs: ids,
            onScreenFrontToBack: onScreen
        )
        let candidates = candidateIndices.map { unminimized[$0] }
        guard candidates.count > 1, let rearWindow = candidates.last else { return }

        AXUIElementPerformAction(rearWindow, kAXRaiseAction as CFString)
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, rearWindow)
    }

    // MARK: - WindowServer & AX Queries

    private static func onScreenWindowIDs(pid: pid_t) -> [CGWindowID] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { entry -> CGWindowID? in
            guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = WindowServerSupport.bounds(from: entry),
                  bounds.width >= 50, bounds.height >= 50,
                  let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { return nil }
            return CGWindowID(number)
        }
    }

    private static func hasOnScreenStandardWindow(pid: pid_t) -> Bool {
        !onScreenWindowIDs(pid: pid).isEmpty
    }

    private static func unminimizedStandardWindows(pid: pid_t, timeout: Float = 0.35) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return []
        }
        var result: [AXUIElement] = []
        for window in windows {
            AXUIElementSetMessagingTimeout(window, timeout)
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
                  (roleRef as? String) == (kAXWindowRole as String) else { continue }
            var minRef: CFTypeRef?
            let isMin = (AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minRef) == .success)
                ? (minRef as? Bool ?? false) : false
            if isMin { continue }
            var fullRef: CFTypeRef?
            let isFull = (AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullRef) == .success)
                ? (fullRef as? Bool ?? false) : false
            if isFull { continue }
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String,
               subrole != "AXStandardWindow" {
                continue
            }
            result.append(window)
        }
        return result
    }
}
