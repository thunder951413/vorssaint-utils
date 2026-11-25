// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MenuBarHiderFeatureTests {
    static func run(_ suite: TestSuite) {
        // MARK: Visibility policy

        let config = MenuBarHiderVisibilityPolicy.configuration(
            items: [
                .init(bundleIdentifier: "com.example.hidden", shouldHide: true),
                .init(bundleIdentifier: "com.example.visible", shouldHide: false),
                .init(bundleIdentifier: "com.apple.controlcenter", shouldHide: true),
                .init(bundleIdentifier: "com.vorssaint.utils", shouldHide: true),
                .init(bundleIdentifier: "com.example.mixed", shouldHide: true),
                .init(bundleIdentifier: "com.example.mixed", shouldHide: false),
            ],
            runningBundleIdentifiers: ["com.example.hidden", "com.example.visible", "com.example.background"],
            ownBundleIdentifier: "com.vorssaint.utils"
        )
        suite.expect(config.concealed == ["com.example.hidden"],
                     "visibility policy only conceals third-party hidden bundles, never Apple or own bundle or mixed-visible bundles")
        suite.expect(config.allowed.contains("com.vorssaint.utils")
                     && config.allowed.contains("com.example.visible")
                     && config.allowed.contains("com.example.background")
                     && config.allowed.contains("com.example.mixed")
                     && !config.allowed.contains("com.example.hidden"),
                     "visibility policy allowlist retains own bundle, visible bundles, and background apps while excluding concealed bundles")

        // MARK: Scan & snapshot merge policies

        suite.expect(MenuBarHiderScanPolicy.orderedIndices(count: 4, cursor: 2) == [2, 3, 0, 1],
                     "rotating scan cursor starts from the previous stopping point")
        suite.expect(MenuBarHiderScanPolicy.nextCursor(count: 4, cursor: 2, scannedCount: 3) == 1,
                     "rotating scan cursor wraps cleanly")
        suite.expect(MenuBarHiderScanPolicy.shouldRequestRefresh(cacheIsFresh: true, scanInFlight: false, force: false) == false
                     && MenuBarHiderScanPolicy.shouldRequestRefresh(cacheIsFresh: false, scanInFlight: true, force: false) == false
                     && MenuBarHiderScanPolicy.shouldRequestRefresh(cacheIsFresh: true, scanInFlight: true, force: true) == true,
                     "scan scheduling avoids duplicate work unless forced")

        struct MockItem: Equatable {
            let id: String
            let pid: Int32
            let concealed: Bool
        }
        let merged = MenuBarHiderSnapshotPolicy.merge(
            existing: [
                "a": MockItem(id: "a", pid: 10, concealed: true),
                "b": MockItem(id: "b", pid: 20, concealed: false),
                "c": MockItem(id: "c", pid: 30, concealed: false),
                "dead": MockItem(id: "dead", pid: 99, concealed: true),
            ],
            discovered: [MockItem(id: "new", pid: 40, concealed: false)],
            liveOwners: [10, 20, 30, 40],
            scannedOwners: [10, 20, 40],
            id: \.id,
            owner: \.pid,
            preserveMissing: \.concealed
        )
        suite.expect(Set(merged.keys) == ["a", "c", "new"],
                     "snapshot merge preserves concealed items and unscanned live owners while pruning exited or scanned-absent owners")

        // MARK: Temporary reveal rehide policy

        let layers = 8...101
        let popup = MenuBarHiderTempRevealPolicy.Window(id: 500, ownerPID: 42, layer: 101)
        let normalWindow = MenuBarHiderTempRevealPolicy.Window(id: 501, ownerPID: 42, layer: 0)
        suite.expect(MenuBarHiderTempRevealPolicy.shouldWait(
            windows: [popup], ownerPID: 42, baselineIDs: [100], interfaceLayers: layers, elapsed: .seconds(5)
        ), "temporary reveal waits while a new popup menu from the same owner is open")
        suite.expect(!MenuBarHiderTempRevealPolicy.shouldWait(
            windows: [normalWindow], ownerPID: 42, baselineIDs: [100], interfaceLayers: layers, elapsed: .seconds(5)
        ), "regular document windows do not hold temporary reveal open")
        suite.expect(!MenuBarHiderTempRevealPolicy.shouldWait(
            windows: [popup], ownerPID: 42, baselineIDs: [500], interfaceLayers: layers, elapsed: .seconds(5)
        ), "pre-existing baseline windows do not hold temporary reveal open")
        suite.expect(!MenuBarHiderTempRevealPolicy.shouldWait(
            windows: [popup], ownerPID: 42, baselineIDs: [], interfaceLayers: layers, elapsed: .seconds(121)
        ), "temporary reveal wait is bounded to prevent sticking forever")

        // MARK: Click policy

        suite.expect(MenuBarHiderClickPolicy.resolve(button: .primary, modifiers: [], allowsAlwaysHidden: true) == .toggleHidden,
                     "plain primary click toggles hidden section")
        suite.expect(MenuBarHiderClickPolicy.resolve(button: .primary, modifiers: .option, allowsAlwaysHidden: true) == .toggleAlwaysHidden,
                     "option primary click toggles always-hidden section when enabled")
        suite.expect(MenuBarHiderClickPolicy.resolve(button: .primary, modifiers: .option, allowsAlwaysHidden: false) == .toggleHidden,
                     "option primary click falls back to hidden section when always-hidden is disabled")
        suite.expect(MenuBarHiderClickPolicy.resolve(button: .secondary, modifiers: [], allowsAlwaysHidden: true) == .showMenu
                     && MenuBarHiderClickPolicy.resolve(button: .primary, modifiers: .control, allowsAlwaysHidden: true) == .showMenu,
                     "secondary click or control-click opens the context menu")

        // MARK: Application menu geometry

        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let appMenu = MenuBarHiderAppMenuGeometry.frame(
            itemFrames: [
                CGRect(x: 8, y: 0, width: 32, height: 32),
                CGRect(x: 44, y: 0, width: 64, height: 32),
                CGRect(x: 112, y: 0, width: 88, height: 32),
            ],
            displayBounds: display
        )
        suite.expect(appMenu == CGRect(x: 0, y: 0, width: 200, height: 32),
                     "application menu geometry covers from display minX through the rightmost menu title")
        suite.expect(MenuBarHiderAppMenuGeometry.isEmptyHostedSpace(
            at: CGPoint(x: 600, y: 16),
            applicationMenuFrame: appMenu,
            itemFrames: [CGRect(x: 1200, y: 0, width: 28, height: 32)],
            displayBounds: display
        ), "point between app menus and status items is recognized as empty menu bar space")
        suite.expect(!MenuBarHiderAppMenuGeometry.isEmptyHostedSpace(
            at: CGPoint(x: 120, y: 16),
            applicationMenuFrame: appMenu,
            itemFrames: [CGRect(x: 1200, y: 0, width: 28, height: 32)],
            displayBounds: display
        ), "point inside application menus is never treated as empty space")
        suite.expect(!MenuBarHiderAppMenuGeometry.isEmptyHostedSpace(
            at: CGPoint(x: 1210, y: 16),
            applicationMenuFrame: appMenu,
            itemFrames: [CGRect(x: 1200, y: 0, width: 28, height: 32)],
            displayBounds: display
        ), "point on a hosted status item is never treated as empty space")

        // MARK: Clock / Notification Center visibility session

        var clockSession = MenuBarHiderClockSession()
        suite.expect(clockSession.observe(isOpen: false, elapsed: .milliseconds(500)) == .wait(.milliseconds(100)),
                     "clock session waits briefly for Notification Center to appear")
        suite.expect(clockSession.observe(isOpen: true, elapsed: .milliseconds(600)) == .wait(.milliseconds(100)),
                     "clock session stays open while Notification Center is visible")
        suite.expect(clockSession.observe(isOpen: false, elapsed: .milliseconds(700)) == .wait(.milliseconds(100)),
                     "clock session debounces brief disappearance")
        suite.expect(clockSession.observe(isOpen: false, elapsed: .milliseconds(1050)) == .restore,
                     "clock session restores hiding once Notification Center stays closed for 300ms")

        let ncWindow = MenuBarHiderClockSession.SystemWindowSnapshot(
            id: 77,
            bundleIdentifier: "com.apple.notificationcenterui",
            title: "Notification Center",
            frame: CGRect(x: 1150, y: 36, width: 350, height: 600),
            layer: 20,
            alpha: 1
        )
        suite.expect(MenuBarHiderClockSession.isClockPanelOpen(
            windows: [ncWindow],
            floatingLayerMinimum: 3,
            displayBounds: [display]
        ), "Notification Center trailing panel is detected as open")

        // MARK: Multi-display unambiguous rendered matcher

        struct Candidate: Equatable {
            let display: CGDirectDisplayID
            let frame: CGRect
        }
        let d1 = Candidate(display: 1, frame: CGRect(x: 100, y: 0, width: 24, height: 24))
        let d2 = Candidate(display: 2, frame: CGRect(x: 1600, y: 0, width: 24, height: 24))
        let d2Dup = Candidate(display: 2, frame: CGRect(x: 1640, y: 0, width: 24, height: 24))
        suite.expect(MenuBarHiderRenderedMatcher.pickUnambiguousMatch(
            from: [d1, d2], preferredDisplayID: 2, displayID: \.display, frame: \.frame
        ) == d2, "multi-display matcher prefers the pointer's display")
        suite.expect(MenuBarHiderRenderedMatcher.pickUnambiguousMatch(
            from: [d2, d2Dup], preferredDisplayID: 2, displayID: \.display, frame: \.frame
        ) == nil, "ambiguous distinct frames on the same display are rejected safely")

        // MARK: Support bounds & localization contracts

        suite.expect(MenuBarHiderSupport.clampedIconSize(8) == 16
                     && MenuBarHiderSupport.clampedIconSize(99) == 36
                     && MenuBarHiderSupport.clampedIconSize(.nan) == MenuBarHiderSupport.defaultIconSize,
                     "icon size clamps cleanly and rejects NaN")
        suite.expect(MenuBarHiderSupport.isOSSupported(version: OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 1))
                     && !MenuBarHiderSupport.isOSSupported(version: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)),
                     "OS gate requires macOS 27+")

        for language in AppLanguage.allCases {
            let s = FeatureStrings.menuBarHider(language)
            let values = Mirror(reflecting: s).children.compactMap { $0.value as? String }
            suite.expect(values.allSatisfy { !$0.isEmpty && !$0.contains("\u{2014}") },
                         "MenuBarHider strings in \(language.rawValue) are non-empty and free of em-dashes")
        }
    }
}
