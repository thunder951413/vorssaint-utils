// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

enum AppHotkeysFeatureTests {
    static func run(_ suite: TestSuite) {
        // MARK: Frontmost behavior sanitization

        suite.expect(AppHotkeyFrontmostBehavior.sanitized(nil) == .hide
                && AppHotkeyFrontmostBehavior.sanitized("unknown") == .hide
                && AppHotkeyFrontmostBehavior.sanitized("cycleWindows") == .cycleWindows
                && AppHotkeyFrontmostBehavior.sanitized("keepFrontmost") == .keepFrontmost,
               "frontmost behavior defaults to hide & switch back and sanitizes unknown values")

        // MARK: Wake decision state machine

        for behavior in AppHotkeyFrontmostBehavior.allCases {
            suite.expect(AppHotkeysSupport.wakeDecision(
                isRunning: false,
                isHidden: false,
                isFrontmost: false,
                hasOnScreenWindows: false,
                frontmostBehavior: behavior
            ) == .launchOrActivate,
                   "an app that is not running always launches (\(behavior.rawValue))")

            suite.expect(AppHotkeysSupport.wakeDecision(
                isRunning: true,
                isHidden: true,
                isFrontmost: false,
                hasOnScreenWindows: false,
                frontmostBehavior: behavior
            ) == .launchOrActivate,
                   "a hidden app always unhides and activates (\(behavior.rawValue))")

            suite.expect(AppHotkeysSupport.wakeDecision(
                isRunning: true,
                isHidden: false,
                isFrontmost: false,
                hasOnScreenWindows: true,
                frontmostBehavior: behavior
            ) == .launchOrActivate,
                   "a background running app always comes to the front (\(behavior.rawValue))")

            suite.expect(AppHotkeysSupport.wakeDecision(
                isRunning: true,
                isHidden: false,
                isFrontmost: true,
                hasOnScreenWindows: false,
                frontmostBehavior: behavior
            ) == .launchOrActivate,
                   "a frontmost app with zero visible windows reopens a window instead of hiding (\(behavior.rawValue))")
        }

        suite.expect(AppHotkeysSupport.wakeDecision(
            isRunning: true,
            isHidden: false,
            isFrontmost: true,
            hasOnScreenWindows: true,
            frontmostBehavior: .hide
        ) == .hideAndReturnPrevious,
               "pressing a frontmost visible app's hotkey in hide mode hides it and returns focus")

        suite.expect(AppHotkeysSupport.wakeDecision(
            isRunning: true,
            isHidden: false,
            isFrontmost: true,
            hasOnScreenWindows: true,
            frontmostBehavior: .cycleWindows
        ) == .cycleWindows,
               "pressing a frontmost visible app's hotkey in cycleWindows mode rotates its windows")

        suite.expect(AppHotkeysSupport.wakeDecision(
            isRunning: true,
            isHidden: false,
            isFrontmost: true,
            hasOnScreenWindows: true,
            frontmostBehavior: .keepFrontmost
        ) == .keepFrontmost,
               "pressing a frontmost visible app's hotkey in keepFrontmost mode keeps it forward")

        // MARK: Entry persistence, sanitization & conflict detection

        let opt1 = GlobalShortcut(keyCode: Int64(kVK_ANSI_1), modifiers: [.option])
        let opt2 = GlobalShortcut(keyCode: Int64(kVK_ANSI_2), modifiers: [.option])
        let bareA = GlobalShortcut(keyCode: Int64(kVK_ANSI_A), modifiers: [])

        var entries: [AppHotkeyEntry] = []
        if case .added(let next) = AppHotkeysSupport.addingApp(
            bundleID: "com.apple.Safari", name: "Safari", to: entries, ownBundleID: "com.vorssaint.utils"
        ) {
            entries = next
        }
        if case .added(let next) = AppHotkeysSupport.addingApp(
            bundleID: "com.apple.Terminal", name: "Terminal", to: entries, ownBundleID: "com.vorssaint.utils"
        ) {
            entries = next
        }
        suite.expect(entries.count == 2, "two distinct eligible apps are added")
        suite.expect(AppHotkeysSupport.addingApp(
            bundleID: "com.apple.Safari", name: "Safari", to: entries, ownBundleID: "com.vorssaint.utils"
        ) == .alreadyPresent, "duplicate bundle IDs are rejected")
        suite.expect(AppHotkeysSupport.addingApp(
            bundleID: "com.vorssaint.utils", name: "Vorssaint", to: entries, ownBundleID: "com.vorssaint.utils"
        ) == .invalidBundleID, "Vorssaint itself cannot be added to app hotkeys")
        suite.expect(AppHotkeysSupport.addingApp(
            bundleID: "/usr/bin/java", name: "java", to: entries, ownBundleID: "com.vorssaint.utils"
        ) == .invalidBundleID, "machine-local executable paths are rejected to keep backups portable")

        entries = AppHotkeysSupport.settingShortcut(opt1, for: "com.apple.Safari", in: entries)
        suite.expect(entries.first?.resolvedShortcut == opt1, "valid shortcut binds to Safari")
        suite.expect(AppHotkeysSupport.assignmentIssue(bareA, for: "com.apple.Terminal", in: entries) == .invalid,
               "a bare letter without modifiers is rejected")
        suite.expect(AppHotkeysSupport.assignmentIssue(opt1, for: "com.apple.Terminal", in: entries)
                == .occupiedByApp(bundleID: "com.apple.Safari"),
               "binding another app's shortcut reports the owning app")

        entries = AppHotkeysSupport.settingShortcut(opt2, for: "com.apple.Terminal", in: entries)
        let active = AppHotkeysSupport.activeShortcuts(in: entries)
        suite.expect(active.count == 2 && active[0].bundleID == "com.apple.Safari"
                && active[1].bundleID == "com.apple.Terminal",
               "both enabled bindings are active in list order")

        let encoded = AppHotkeysSupport.encode(entries, ownBundleID: "com.vorssaint.utils")
        let decoded = AppHotkeysSupport.decode(encoded, ownBundleID: "com.vorssaint.utils")
        suite.expect(decoded == entries, "entries round-trip cleanly through JSON Data")

        let moved = AppHotkeysSupport.movingEntry(bundleID: "com.apple.Terminal", direction: -1, in: entries)
        suite.expect(moved.map(\.bundleID) == ["com.apple.Terminal", "com.apple.Safari"],
               "entries reorder cleanly")

        let disabledSafari = AppHotkeysSupport.settingEnabled(false, for: "com.apple.Safari", in: entries)
        suite.expect(AppHotkeysSupport.activeShortcuts(in: disabledSafari).map(\.bundleID) == ["com.apple.Terminal"]
                && AppHotkeysSupport.ownerBundleID(for: opt1, in: disabledSafari, includeDisabled: false) == nil
                && AppHotkeysSupport.ownerBundleID(for: opt1, in: disabledSafari, includeDisabled: true) == "com.apple.Safari",
               "disabling an app silences its hotkey while keeping its saved shortcut")

        let clearedSafari = AppHotkeysSupport.settingShortcut(nil, for: "com.apple.Safari", in: entries)
        suite.expect(clearedSafari.first?.resolvedShortcut == nil, "clearing a shortcut preserves the app row")

        let removedSafari = AppHotkeysSupport.removingApp(bundleID: "com.apple.Safari", from: entries)
        suite.expect(removedSafari.map(\.bundleID) == ["com.apple.Terminal"], "removing an app drops only that row")

        // MARK: Dock persistent-apps import

        let fakeDockDomain: [String: Any] = [
            "persistent-apps": [
                ["tile-data": ["bundle-identifier": "com.apple.Safari"]],
                ["tile-data": ["bundle-identifier": "com.vorssaint.utils"]],
                ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Notes.app/"]]],
                ["tile-data": ["bundle-identifier": "com.apple.Safari"]],
            ]
        ]
        let dockIDs = AppHotkeysSupport.dockBundleIDs(
            from: fakeDockDomain,
            ownBundleID: "com.vorssaint.utils",
            includeFinder: true,
            resolveBundleIDForURL: { url in
                url.path.contains("Notes.app") ? "com.apple.Notes" : nil
            }
        )
        suite.expect(dockIDs == ["com.apple.finder", "com.apple.Safari", "com.apple.Notes"],
               "Dock import starts with Finder, resolves URL tiles, deduplicates, and skips Vorssaint")

        // MARK: Conditional Accessibility requirement

        suite.expect(!AppHotkeysSupport.needsAccessibility(
            enabled: true, frontmostBehaviorRaw: "hide", entriesData: encoded
        ), "default hide mode needs no Accessibility permission")
        suite.expect(!AppHotkeysSupport.needsAccessibility(
            enabled: true, frontmostBehaviorRaw: "cycleWindows", entriesData: nil
        ), "cycleWindows with no bound shortcuts needs no Accessibility permission")
        suite.expect(!AppHotkeysSupport.needsAccessibility(
            enabled: false, frontmostBehaviorRaw: "cycleWindows", entriesData: encoded
        ), "disabled App Hotkeys needs no Accessibility permission")
        suite.expect(AppHotkeysSupport.needsAccessibility(
            enabled: true, frontmostBehaviorRaw: "cycleWindows", entriesData: encoded
        ), "enabled cycleWindows with at least one bound shortcut requests Accessibility")
    }
}
