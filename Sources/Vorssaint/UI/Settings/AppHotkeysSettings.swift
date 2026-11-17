// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AppHotkeysSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AppHotkeysService.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    @AppStorage(DefaultsKey.appHotkeysEnabled) private var enabled = true
    @AppStorage(DefaultsKey.appHotkeysFrontmostBehavior)
    private var frontmostBehaviorRaw = AppHotkeyFrontmostBehavior.defaultBehavior.rawValue

    @State private var showingAppPicker = false
    @State private var filterQuery = ""
    @State private var statusBanner: (text: String, isWarning: Bool)?
    @State private var surfaceID = UUID()

    private var strings: AppHotkeysFeatureStrings {
        FeatureStrings.appHotkeys(l10n.language)
    }

    private var frontmostBehavior: AppHotkeyFrontmostBehavior {
        AppHotkeyFrontmostBehavior.sanitized(frontmostBehaviorRaw)
    }

    private var frontmostBehaviorBinding: Binding<String> {
        Binding(
            get: { frontmostBehavior.rawValue },
            set: { newValue in
                frontmostBehaviorRaw = AppHotkeyFrontmostBehavior.sanitized(newValue).rawValue
                if AppHotkeyFrontmostBehavior.sanitized(newValue) == .cycleWindows,
                   enabled, !permissions.accessibility {
                    permissions.requestAccessibility()
                    permissions.openAccessibilitySettings()
                }
            }
        )
    }

    private var frontmostBehaviorCaption: String {
        switch frontmostBehavior {
        case .hide:
            return strings.frontmostHideCaption
        case .cycleWindows:
            return strings.frontmostCycleWindowsCaption
        case .keepFrontmost:
            return strings.frontmostKeepCaption
        }
    }

    private var filteredEntries: [AppHotkeyEntry] {
        let trimmed = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return service.entries }
        return service.entries.filter { entry in
            let title = service.displayName(for: entry)
            return SettingsSearchSupport.matches(
                query: trimmed,
                title: title,
                keywords: [entry.bundleID, entry.resolvedShortcut?.displayString ?? ""]
            )
        }
    }

    private var isFiltering: Bool {
        !filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(strings.title).font(.title2.bold())
                    Text(strings.pageCaption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                generalCard

                if enabled, frontmostBehavior == .cycleWindows, !permissions.accessibility {
                    SettingsCard(title: l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }

                applicationsCard
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.65)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
        .observesSecureInput(isActive: enabled)
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
        .onAppear {
            service.syncWithPreferences()
            service.setObservingRunningApps(surfaceID, visible: true)
        }
        .onDisappear {
            service.setObservingRunningApps(surfaceID, visible: false)
        }
        .onChange(of: l10n.language) { _, _ in
            statusBanner = nil
        }
    }

    // MARK: - General & Frontmost Behavior

    private var generalCard: some View {
        SettingsCard {
            SettingsRow(symbol: AppFeature.appHotkeys.symbolName,
                        title: strings.enable,
                        caption: strings.enableCaption) {
                Toggle(strings.enable, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, _ in
                        service.syncWithPreferences()
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: "arrow.uturn.backward.square",
                            title: strings.frontmostTitle,
                            caption: frontmostBehaviorCaption) {
                    EmptyView()
                }
                HStack(spacing: 8) {
                    behaviorChip(.hide, title: strings.frontmostHide, symbol: "eye.slash")
                    behaviorChip(.cycleWindows, title: strings.frontmostCycleWindows,
                                 symbol: "arrow.triangle.2.circlepath")
                    behaviorChip(.keepFrontmost, title: strings.frontmostKeep, symbol: "macwindow")
                }
                .padding(.leading, settingsRowTextInset)
            }
            .disabled(!enabled)
        }
    }

    private func behaviorChip(_ behavior: AppHotkeyFrontmostBehavior,
                              title: String,
                              symbol: String) -> some View {
        let selected = frontmostBehavior == behavior
        return Button {
            frontmostBehaviorBinding.wrappedValue = behavior.rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Application Shortcuts List

    private var applicationsCard: some View {
        let activeCount = AppHotkeysSupport.activeShortcuts(in: service.entries).count
        return SettingsCard {
            HStack(spacing: 10) {
                Text(strings.appsSectionTitle)
                    .font(.headline)
                if activeCount > 0 {
                    Text(String(format: strings.activeCountFormat, activeCount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(enabled ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                        )
                }
                Spacer()
                Button {
                    statusBanner = nil
                    let added = service.importDockApps()
                    if added > 0 {
                        statusBanner = (String(format: strings.dockImportedFormat, added), false)
                    } else if service.entries.count >= AppHotkeysSupport.limit {
                        statusBanner = (String(format: strings.limitReachedFormat, AppHotkeysSupport.limit), true)
                    } else {
                        statusBanner = (strings.dockImportEmpty, false)
                    }
                } label: {
                    Label(strings.importDockButton, systemImage: "dock.rectangle")
                }
                .controlSize(.small)

                Button {
                    statusBanner = nil
                    if service.entries.count >= AppHotkeysSupport.limit {
                        statusBanner = (String(format: strings.limitReachedFormat, AppHotkeysSupport.limit), true)
                    } else {
                        showingAppPicker = true
                    }
                } label: {
                    Label(strings.addAppButton, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let banner = statusBanner {
                HStack(spacing: 6) {
                    Image(systemName: banner.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(banner.isWarning ? Color.orange : Color.green)
                    Text(banner.text)
                        .font(.caption)
                        .foregroundStyle(banner.isWarning ? Color.orange : Color.secondary)
                    Spacer()
                    Button {
                        statusBanner = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(l10n.s.menuClose)
                }
            }

            if service.entries.count >= 5 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(strings.searchPlaceholder, text: $filterQuery)
                        .textFieldStyle(.plain)
                        .accessibilityLabel(strings.searchPlaceholder)
                    if !filterQuery.isEmpty {
                        Button {
                            filterQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(l10n.s.shortcutClear)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if service.entries.isEmpty {
                emptyStateView
            } else if filteredEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(FeatureStrings.commandBar(l10n.language).noResultsTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.vertical, 6)
                        }
                        AppHotkeyRowView(
                            entry: entry,
                            appName: service.displayName(for: entry),
                            isRunning: service.runningBundleIDs.contains(entry.bundleID),
                            isFeatureEnabled: enabled,
                            isRegistrationRefused: service.refusedBundleIDs.contains(entry.bundleID),
                            canMoveUp: !isFiltering && service.entries.first?.id != entry.id,
                            canMoveDown: !isFiltering && service.entries.last?.id != entry.id,
                            showsSuperKeyAlternative: superKey.isRunning,
                            superKeyModifiers: superKey.modifiers,
                            strings: strings
                        )
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: AppFeature.appHotkeys.symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(strings.emptyTitle)
                .font(.subheadline.weight(.semibold))
            Text(strings.emptyCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var appPickerSheet: some View {
        let excluded = Set(service.entries.map(\.bundleID)).union(AppHotkeysSupport.excludedSystemBundleIDs)
        return AppPickerView(canBrowseApplications: true, acceptsExecutables: false) {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            handleAddResult(service.addApp(bundleID: bundleID, name: name))
        } onSelectApp: { app in
            showingAppPicker = false
            guard let bundleID = app.bundleID else { return }
            handleAddResult(service.addApp(bundleID: bundleID, name: app.name))
        } loadApps: {
            InstalledApps.installedBundleApplications(
                excluding: excluded,
                includeRunningApplications: true,
                acceptsExecutables: false
            )
        }
    }

    private func handleAddResult(_ result: AppHotkeysSupport.AddAppResult) {
        if case .limitReached = result {
            statusBanner = (String(format: strings.limitReachedFormat, AppHotkeysSupport.limit), true)
        }
    }
}

private struct AppHotkeyRowView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    let entry: AppHotkeyEntry
    let appName: String
    let isRunning: Bool
    let isFeatureEnabled: Bool
    let isRegistrationRefused: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let showsSuperKeyAlternative: Bool
    let superKeyModifiers: GlobalShortcutModifiers
    let strings: AppHotkeysFeatureStrings

    @State private var errorText: String?
    @State private var isRecording = false
    @State private var pendingTakeOver: GlobalShortcut?

    private var service: AppHotkeysService { .shared }
    private var resolvedShortcut: GlobalShortcut? { entry.resolvedShortcut }
    private var storageKey: String { AppHotkeysSupport.storageKey(for: entry.bundleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(nsImage: InstalledApps.icon(for: entry.bundleID))
                    .resizable()
                    .frame(width: 26, height: 26)
                    .opacity(entry.isEnabled ? 1 : 0.5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(appName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(entry.isEnabled ? .primary : .secondary)
                            .lineLimit(1)
                        if isRunning {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text(strings.runningBadge)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text(entry.bundleID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 6) {
                        if isRegistrationRefused {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(l10n.s.shortcutUnavailable)
                                .accessibilityLabel(l10n.s.shortcutUnavailable)
                        }

                        ShortcutRecorderButton(
                            shortcut: pendingTakeOver ?? resolvedShortcut ?? .commandBarDefault,
                            isEnabled: isFeatureEnabled && entry.isEnabled,
                            waitingTitle: l10n.s.shortcutPressKeys,
                            emptyTitle: pendingTakeOver == nil && resolvedShortcut == nil
                                ? strings.recordShortcut : nil,
                            clearAction: clearShortcut,
                            notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                            recordingChanged: { recording in
                                isRecording = recording
                                if recording {
                                    errorText = nil
                                    pendingTakeOver = nil
                                }
                            },
                            invalidAction: { errorText = l10n.s.shortcutInvalid },
                            captureAction: saveShortcut
                        )
                        .frame(width: 132)
                        .accessibilityLabel("\(appName): \(strings.recordShortcut)")

                        Button {
                            clearShortcut()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvedShortcut == nil && pendingTakeOver == nil)
                        .opacity(resolvedShortcut == nil && pendingTakeOver == nil ? 0.3 : 1)
                        .help(l10n.s.shortcutClear)
                        .accessibilityLabel("\(appName): \(l10n.s.shortcutClear)")

                        Toggle(strings.enable, isOn: Binding(
                            get: { entry.isEnabled },
                            set: { service.setAppEnabled($0, for: entry.bundleID) }
                        ))
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("\(appName): \(strings.enable)")

                        if canMoveUp || canMoveDown {
                            HStack(spacing: 2) {
                                Button {
                                    service.moveEntry(bundleID: entry.bundleID, direction: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10, weight: .semibold))
                                        .frame(width: 18, height: 20)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .disabled(!canMoveUp)
                                .opacity(canMoveUp ? 1 : 0.25)
                                .help(strings.moveUpLabel)
                                .accessibilityLabel("\(appName): \(strings.moveUpLabel)")

                                Button {
                                    service.moveEntry(bundleID: entry.bundleID, direction: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .frame(width: 18, height: 20)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .disabled(!canMoveDown)
                                .opacity(canMoveDown ? 1 : 0.25)
                                .help(strings.moveDownLabel)
                                .accessibilityLabel("\(appName): \(strings.moveDownLabel)")
                            }
                        }

                        Button {
                            service.removeApp(bundleID: entry.bundleID)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(strings.removeAppLabel)
                        .accessibilityLabel("\(appName): \(strings.removeAppLabel)")
                    }

                    if let alternative = superKeyAlternative {
                        Text(String(format: FeatureStrings.shortcuts(l10n.language).superKeyAlternativeFormat,
                                    alternative))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(alternative)
                    }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: resolvedShortcut != nil))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let pendingTakeOver {
                SystemShortcutTakeOverOffer(
                    shortcut: pendingTakeOver,
                    onAccept: {
                        service.saveShortcut(pendingTakeOver,
                                             for: entry.bundleID,
                                             takenOverSystemShortcut: true)
                        self.pendingTakeOver = nil
                    },
                    onDismiss: {
                        self.pendingTakeOver = nil
                        errorText = String(format: l10n.s.shortcutConflictFormat, "macOS")
                    }
                )
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private var superKeyAlternative: String? {
        guard showsSuperKeyAlternative, entry.isEnabled, let resolvedShortcut else { return nil }
        return resolvedShortcut.superKeyAlternative(
            sourceLabel: FeatureStrings.superKey(l10n.language).sourceLabel(superKey.source),
            superKeyModifiers: superKeyModifiers
        )
    }

    private func clearShortcut() {
        errorText = nil
        pendingTakeOver = nil
        service.saveShortcut(nil, for: entry.bundleID, takenOverSystemShortcut: false)
    }

    private func saveShortcut(_ shortcut: GlobalShortcut) {
        if let issue = service.validationError(for: shortcut, bundleID: entry.bundleID) {
            errorText = issue
            return
        }
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut),
            takenOver: SystemShortcutTakeover.isTakenOver(storageKey),
            current: resolvedShortcut
        ) {
        case .offer:
            pendingTakeOver = shortcut
            errorText = nil
        case .save(let clearTakeOver):
            errorText = nil
            let keepTakeOver = !clearTakeOver && SystemShortcutTakeover.isTakenOver(storageKey)
            service.saveShortcut(shortcut, for: entry.bundleID, takenOverSystemShortcut: keepTakeOver)
        }
    }
}
