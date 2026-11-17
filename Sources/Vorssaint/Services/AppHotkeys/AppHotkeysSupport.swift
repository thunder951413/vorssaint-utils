// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What happens when the user presses an app's hotkey while that app is already
/// frontmost with at least one visible window on screen.
enum AppHotkeyFrontmostBehavior: String, CaseIterable, Codable, Equatable, Identifiable {
    case hide
    case cycleWindows
    case keepFrontmost

    var id: String { rawValue }

    static let defaultBehavior: Self = .hide

    static func sanitized(_ raw: String?) -> Self {
        guard let raw, let behavior = Self(rawValue: raw) else { return defaultBehavior }
        return behavior
    }
}

/// One configured application entry in App Hotkeys.
///
/// Keyed by portable bundle identifier so settings backups travel across Macs
/// without leaking machine-local filesystem paths.
struct AppHotkeyEntry: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var appNameFallback: String
    var shortcut: String?
    var isEnabled: Bool

    init(bundleID: String,
         appNameFallback: String,
         shortcut: String? = nil,
         isEnabled: Bool = true) {
        self.bundleID = bundleID
        self.appNameFallback = appNameFallback
        self.shortcut = shortcut
        self.isEnabled = isEnabled
    }

    var resolvedShortcut: GlobalShortcut? {
        guard let shortcut, let parsed = GlobalShortcut(storageValue: shortcut),
              parsed.isValid else { return nil }
        return parsed
    }
}

enum AppHotkeysSupport {
    /// Generous enough for heavy power users while keeping Settings snappy and
    /// Carbon hotkey IDs bounded well away from every other feature.
    static let limit = 60

    /// Starts well above quick tools (10..60), command bar rows (200..220),
    /// and radial menu profiles (1700..1799).
    static let baseHotkeyID: UInt32 = 3000

    static let excludedSystemBundleIDs: Set<String> = [
        "com.vorssaint.utils",
        "com.vorssaint.utils.dev",
    ]

    enum WakeDecision: Equatable {
        /// Launch the app if not running, or unhide / bring forward / reopen
        /// its main window when it is hidden, in the background, or frontmost
        /// with all windows closed or minimized.
        case launchOrActivate
        /// Hide the active app so focus returns to the previously active app.
        case hideAndReturnPrevious
        /// Rotate through the active app's open windows on the current Space.
        case cycleWindows
        /// Keep the active app in front without hiding or cycling.
        case keepFrontmost
    }

    enum ShortcutAssignmentIssue: Equatable {
        case invalid
        case occupiedByApp(bundleID: String)
    }

    enum AddAppResult: Equatable {
        case added([AppHotkeyEntry])
        case alreadyPresent
        case invalidBundleID
        case limitReached
    }

    static func storageKey(for bundleID: String) -> String {
        "\(DefaultsKey.appHotkeysEntries).\(bundleID)"
    }

    static func isEligibleBundleID(_ bundleID: String?,
                                   ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !excludedSystemBundleIDs.contains(trimmed),
              trimmed != ownBundleID else {
            return false
        }
        return !MouseAppExceptionSupport.isExecutablePathIdentity(trimmed)
    }

    static func sanitizedEntries(_ entries: [AppHotkeyEntry],
                                 ownBundleID: String? = Bundle.main.bundleIdentifier) -> [AppHotkeyEntry] {
        var seen = Set<String>()
        var usedShortcuts = Set<GlobalShortcut>()
        var result: [AppHotkeyEntry] = []
        for entry in entries {
            let trimmedID = entry.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isEligibleBundleID(trimmedID, ownBundleID: ownBundleID),
                  seen.insert(trimmedID).inserted else { continue }
            guard result.count < limit else { break }

            let fallbackName = entry.appNameFallback.trimmingCharacters(in: .whitespacesAndNewlines)
            var normalizedShortcut: String? = nil
            if let parsed = entry.resolvedShortcut, usedShortcuts.insert(parsed).inserted {
                normalizedShortcut = parsed.storageValue
            }
            result.append(AppHotkeyEntry(
                bundleID: trimmedID,
                appNameFallback: fallbackName.isEmpty ? trimmedID : fallbackName,
                shortcut: normalizedShortcut,
                isEnabled: entry.isEnabled
            ))
        }
        return result
    }

    static func decode(_ data: Data?,
                       ownBundleID: String? = Bundle.main.bundleIdentifier) -> [AppHotkeyEntry] {
        guard let data, !data.isEmpty,
              let decoded = try? JSONDecoder().decode([AppHotkeyEntry].self, from: data) else {
            return []
        }
        return sanitizedEntries(decoded, ownBundleID: ownBundleID)
    }

    static func encode(_ entries: [AppHotkeyEntry],
                       ownBundleID: String? = Bundle.main.bundleIdentifier) -> Data? {
        let sanitized = sanitizedEntries(entries, ownBundleID: ownBundleID)
        return try? JSONEncoder().encode(sanitized)
    }

    static func activeShortcuts(in entries: [AppHotkeyEntry]) -> [(bundleID: String, shortcut: GlobalShortcut)] {
        entries.compactMap { entry in
            guard entry.isEnabled, let shortcut = entry.resolvedShortcut else { return nil }
            return (entry.bundleID, shortcut)
        }
    }

    /// Accessibility is needed only when the feature is enabled, configured to
    /// cycle same-app windows when frontmost, and has at least one active binding.
    static func needsAccessibility(enabled: Bool,
                                   frontmostBehaviorRaw: String?,
                                   entriesData: Data?) -> Bool {
        guard enabled,
              AppHotkeyFrontmostBehavior.sanitized(frontmostBehaviorRaw) == .cycleWindows else {
            return false
        }
        return !activeShortcuts(in: decode(entriesData)).isEmpty
    }

    /// Pure decision for what pressing an app's hotkey should do right now.
    ///
    /// Note the `hasOnScreenWindows` check: if an app owns the menu bar as the
    /// frontmost process while all of its windows are minimized or closed, a
    /// wake shortcut should bring a window back onto the screen rather than
    /// hiding an already empty workspace.
    static func wakeDecision(isRunning: Bool,
                             isHidden: Bool,
                             isFrontmost: Bool,
                             hasOnScreenWindows: Bool,
                             frontmostBehavior: AppHotkeyFrontmostBehavior) -> WakeDecision {
        guard isRunning, !isHidden, isFrontmost, hasOnScreenWindows else {
            return .launchOrActivate
        }
        switch frontmostBehavior {
        case .hide:
            return .hideAndReturnPrevious
        case .cycleWindows:
            return .cycleWindows
        case .keepFrontmost:
            return .keepFrontmost
        }
    }

    static func assignmentIssue(_ shortcut: GlobalShortcut,
                                for bundleID: String,
                                in entries: [AppHotkeyEntry]) -> ShortcutAssignmentIssue? {
        guard shortcut.isValid else { return .invalid }
        if let owner = entries.first(where: { $0.bundleID != bundleID && $0.resolvedShortcut == shortcut }) {
            return .occupiedByApp(bundleID: owner.bundleID)
        }
        return nil
    }

    static func ownerBundleID(for shortcut: GlobalShortcut,
                              excluding excludedBundleID: String? = nil,
                              in entries: [AppHotkeyEntry],
                              includeDisabled: Bool = false) -> String? {
        entries.first { entry in
            entry.bundleID != excludedBundleID
                && (includeDisabled || entry.isEnabled)
                && entry.resolvedShortcut == shortcut
        }?.bundleID
    }

    static func addingApp(bundleID: String,
                          name: String,
                          to entries: [AppHotkeyEntry],
                          ownBundleID: String? = Bundle.main.bundleIdentifier) -> AddAppResult {
        let trimmedID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEligibleBundleID(trimmedID, ownBundleID: ownBundleID) else {
            return .invalidBundleID
        }
        if entries.contains(where: { $0.bundleID == trimmedID }) {
            return .alreadyPresent
        }
        guard entries.count < limit else {
            return .limitReached
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = entries
        next.append(AppHotkeyEntry(
            bundleID: trimmedID,
            appNameFallback: trimmedName.isEmpty ? trimmedID : trimmedName,
            shortcut: nil,
            isEnabled: true
        ))
        return .added(next)
    }

    static func importingApps(_ candidates: [(bundleID: String, name: String)],
                              into entries: [AppHotkeyEntry],
                              ownBundleID: String? = Bundle.main.bundleIdentifier)
        -> (entries: [AppHotkeyEntry], addedCount: Int) {
        var next = entries
        var added = 0
        for candidate in candidates {
            guard next.count < limit else { break }
            if case .added(let updated) = addingApp(bundleID: candidate.bundleID,
                                                    name: candidate.name,
                                                    to: next,
                                                    ownBundleID: ownBundleID) {
                next = updated
                added += 1
            }
        }
        return (next, added)
    }

    static func settingShortcut(_ shortcut: GlobalShortcut?,
                                for bundleID: String,
                                in entries: [AppHotkeyEntry]) -> [AppHotkeyEntry] {
        var next = entries
        guard let index = next.firstIndex(where: { $0.bundleID == bundleID }) else { return next }
        if let shortcut {
            guard shortcut.isValid else { return next }
            for otherIndex in next.indices where otherIndex != index && next[otherIndex].resolvedShortcut == shortcut {
                next[otherIndex].shortcut = nil
            }
            next[index].shortcut = shortcut.storageValue
        } else {
            next[index].shortcut = nil
        }
        return next
    }

    static func settingEnabled(_ isEnabled: Bool,
                               for bundleID: String,
                               in entries: [AppHotkeyEntry]) -> [AppHotkeyEntry] {
        var next = entries
        guard let index = next.firstIndex(where: { $0.bundleID == bundleID }) else { return next }
        next[index].isEnabled = isEnabled
        return next
    }

    static func removingApp(bundleID: String,
                            from entries: [AppHotkeyEntry]) -> [AppHotkeyEntry] {
        entries.filter { $0.bundleID != bundleID }
    }

    static func movingEntry(bundleID: String,
                            direction: Int,
                            in entries: [AppHotkeyEntry]) -> [AppHotkeyEntry] {
        guard let index = entries.firstIndex(where: { $0.bundleID == bundleID }) else { return entries }
        let target = index + direction
        guard entries.indices.contains(target), target != index else { return entries }
        var next = entries
        let entry = next.remove(at: index)
        next.insert(entry, at: target)
        return next
    }

    /// Extracts ordered Dock application bundle identifiers from `com.apple.dock`
    /// (`persistent-apps`), starting with Finder (which always heads the Dock)
    /// and resolving URL-only Dock tiles through an injectable lookup.
    static func dockBundleIDs(from dockDomain: [String: Any]?,
                              ownBundleID: String? = Bundle.main.bundleIdentifier,
                              includeFinder: Bool = true,
                              resolveBundleIDForURL: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier })
        -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func appendIfEligible(_ rawID: String?) {
            guard let trimmed = rawID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  isEligibleBundleID(trimmed, ownBundleID: ownBundleID),
                  seen.insert(trimmed).inserted else { return }
            result.append(trimmed)
        }

        if includeFinder {
            appendIfEligible("com.apple.finder")
        }

        guard let persistentApps = dockDomain?["persistent-apps"] as? [[String: Any]] else {
            return result
        }

        for item in persistentApps {
            guard let tileData = item["tile-data"] as? [String: Any] else { continue }
            if let bundleID = tileData["bundle-identifier"] as? String, !bundleID.isEmpty {
                appendIfEligible(bundleID)
                continue
            }
            if let fileData = tileData["file-data"] as? [String: Any],
               let urlString = fileData["_CFURLString"] as? String {
                let url = URL(string: urlString) ?? URL(fileURLWithPath: urlString)
                if url.isFileURL {
                    appendIfEligible(resolveBundleIDForURL(url))
                }
            }
        }
        return result
    }
}
