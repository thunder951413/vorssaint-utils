// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Floating panel controller for Dispatch Hub (mirrors ScratchpadService lifecycle).
final class DispatchHubService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DispatchHubService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var isPinned = false
    @Published private(set) var isWideMode = false

    private static let standardSize = NSSize(width: 600, height: 700)
    private static let wideSize = NSSize(width: 860, height: 780)
    private static let minWindowSize = NSSize(width: 440, height: 480)
    private static let maxWindowSize = NSSize(width: 1120, height: 1100)

    let store: DispatchHubStore
    private(set) var previousFrontmostBundleID: String?

    private let hotkey = QuickToolHotkey(id: 90)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?

    private override init() {
        self.store = MainActor.assumeIsolated { DispatchHubStore() }
        super.init()
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let available = AppFeature.dispatchHub.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.dispatchHubShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.dispatchHubShortcut,
                                            fallback: .dispatchHubDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.dispatchHubShortcut)
        if !available {
            hide()
            Task { @MainActor in store.stopAllPolling() }
            panel = nil
        }
    }

    func suspend() {
        hotkey.unregister()
        hide()
        Task { @MainActor in store.stopAllPolling() }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible, panel?.isKeyWindow == true {
            hide()
        } else {
            show()
        }
    }

    func togglePin() {
        isPinned.toggle()
        if let panel {
            panel.collectionBehavior = isPinned
                ? [.canJoinAllSpaces, .fullScreenAuxiliary]
                : [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
    }

    func toggleWideMode() {
        guard let panel else { return }
        isWideMode.toggle()
        let targetSize = isWideMode ? Self.wideSize : Self.standardSize
        let screen = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let clampedW = min(targetSize.width, screen.width - 32)
        let clampedH = min(targetSize.height, screen.height - 32)
        let newX = max(screen.minX + 16, min(panel.frame.midX - clampedW / 2, screen.maxX - clampedW - 16))
        let newY = max(screen.minY + 16, min(panel.frame.maxY - clampedH, screen.maxY - clampedH - 16))
        let targetFrame = NSRect(x: newX, y: newY, width: clampedW, height: clampedH)
        panel.setFrame(targetFrame, display: true, animate: true)
        DispatchHubSettings.saveFrame(targetFrame)
    }

    func show() {
        guard AppFeature.dispatchHub.isAvailable else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostBundleID = front.bundleIdentifier
        }
        if isVisible, let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor in store.onPanelShown() }
            return
        }
        isPinned = !DispatchHubSettings.closeOnClickOutside
        let panel = ensurePanel()
        installMonitors(for: panel)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            positionDefault(panel)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in store.onPanelShown() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        DispatchHubSettings.saveFrame(panel.frame)
        removeMonitors()
        panel.orderOut(nil)
        Task { @MainActor in store.onPanelHidden() }
    }

    func dispatchClipboardNow() {
        guard AppFeature.dispatchHub.isAvailable else { return }
        Task { @MainActor in store.dispatchClipboardSilently() }
    }

    // MARK: - Panel Construction

    private final class KeyableDispatchPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let defaultSize = Self.standardSize
        let panel = KeyableDispatchPanel(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Dispatch Hub"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = Self.minWindowSize
        panel.minSize = Self.minWindowSize
        panel.maxSize = Self.maxWindowSize
        panel.delegate = self

        let host = NSHostingController(rootView: DispatchHubView(service: self, store: store))
        host.sizingOptions = []
        panel.contentViewController = host

        if let saved = DispatchHubSettings.loadFrame(),
           saved.width >= 520 && saved.height >= 620,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            panel.setFrame(saved, display: false)
            isWideMode = saved.width >= 760
        } else {
            panel.setContentSize(defaultSize)
            positionDefault(panel)
            isWideMode = false
        }
        self.panel = panel
        return panel
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: min(Self.maxWindowSize.width, max(Self.minWindowSize.width, frameSize.width)),
            height: min(Self.maxWindowSize.height, max(Self.minWindowSize.height, frameSize.height))
        )
    }

    func windowDidResize(_ notification: Notification) {
        if let panel {
            isWideMode = panel.frame.width >= 760
            DispatchHubSettings.saveFrame(panel.frame)
        }
    }

    func windowDidMove(_ notification: Notification) {
        if let panel { DispatchHubSettings.saveFrame(panel.frame) }
    }

    private func positionDefault(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let topOffset = screen.height * 0.14
        let y = screen.maxY - size.height - topOffset
        panel.setFrame(
            NSRect(
                x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                y: max(screen.minY + 16, min(y, screen.maxY - size.height - 16)),
                width: size.width,
                height: size.height
            ),
            display: true,
            animate: false
        )
    }

    // MARK: - Event Monitors

    private var dismissesOnOutsideClick: Bool {
        !isPinned && DispatchHubSettings.closeOnClickOutside
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])

            if event.keyCode == UInt16(kVK_Escape) {
                let handled = MainActor.assumeIsolated { () -> Bool in
                    if self.store.showSettings {
                        self.store.showSettings = false
                        return true
                    }
                    return false
                }
                if handled { return nil }
                self.hide()
                return nil
            }

            if mods == .command {
                let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
                switch ch {
                case "w":
                    self.hide()
                    return nil
                case ",":
                    MainActor.assumeIsolated { self.store.showSettings.toggle() }
                    return nil
                case "e":
                    self.toggleWideMode()
                    return nil
                case "b":
                    let bundle = self.previousFrontmostBundleID
                    MainActor.assumeIsolated { self.store.grabBrowserURL(preferredBundleID: bundle) }
                    return nil
                case "0":
                    MainActor.assumeIsolated { self.store.manualTarget = nil }
                    return nil
                case "1":
                    MainActor.assumeIsolated { self.store.manualTarget = .shizhi }
                    return nil
                case "2":
                    MainActor.assumeIsolated { self.store.manualTarget = .teams }
                    return nil
                case "v":
                    let replaced = MainActor.assumeIsolated { () -> Bool in
                        guard !self.store.showSettings else { return false }
                        guard let raw = NSPasteboard.general.string(forType: .string),
                              DispatchRouter.parseURL(raw) != nil else { return false }
                        self.store.pasteFromClipboard()
                        return true
                    }
                    if replaced { return nil }
                case "o":
                    let opened = MainActor.assumeIsolated { self.store.openSelectedURL() }
                    if opened { return nil }
                case "c":
                    let isEditingText = panel.firstResponder is NSTextView
                    if !isEditingText {
                        let copied = MainActor.assumeIsolated { self.store.copySelectedPrimary() }
                        if copied { return nil }
                    }
                default:
                    break
                }
                if event.keyCode == UInt16(kVK_Return) {
                    MainActor.assumeIsolated { self.store.submitCurrent() }
                    return nil
                }
            }

            if mods.isEmpty && !(panel.firstResponder is NSTextView) {
                if event.keyCode == UInt16(kVK_DownArrow) {
                    MainActor.assumeIsolated { self.store.moveSelection(delta: 1) }
                    return nil
                }
                if event.keyCode == UInt16(kVK_UpArrow) {
                    MainActor.assumeIsolated { self.store.moveSelection(delta: -1) }
                    return nil
                }
            }
            return event
        }

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}
