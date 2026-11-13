// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var cloudSync = ClipboardCloudSyncCoordinator.shared
    @ObservedObject private var pastePlain = PastePlainService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.pastePlainEnabled) private var pastePlainEnabled = false
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardHistoryLimit) private var limit = 50
    @AppStorage(DefaultsKey.clipboardHistorySkipSensitive) private var skipSensitive = true
    @AppStorage(DefaultsKey.clipboardHistoryIncludeImagesFiles) private var includeImagesFiles = true
    @AppStorage(DefaultsKey.clipboardHistoryShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.clipboardHistoryMenuBarPreview) private var menuBarPreview = false
    @AppStorage(DefaultsKey.clipboardHistoryMenuBarPreviewLength)
    private var menuBarPreviewLength = Defaults.defaultClipboardMenuBarPreviewLength
    @AppStorage(DefaultsKey.panelUtilityClipboard) private var showInPanel = true
    @AppStorage(DefaultsKey.finderPasteImageAsFile) private var pasteImageAsFile = false
    @AppStorage(DefaultsKey.clipboardAutoClearOnDelay) private var autoClearOnDelay = false
    @AppStorage(DefaultsKey.clipboardAutoClearDelay)
    private var autoClearDelay = Defaults.defaultClipboardAutoClearDelay
    @AppStorage(DefaultsKey.clipboardAutoClearOnSleep) private var autoClearOnSleep = false
    @AppStorage(DefaultsKey.clipboardAutoClearOnDisplaySleep) private var autoClearOnDisplaySleep = false
    @AppStorage(DefaultsKey.clipboardAutoClearOnScreenLock) private var autoClearOnScreenLock = false
    @AppStorage(DefaultsKey.clipboardCloudSyncEnabled) private var cloudSyncEnabled = false
    @AppStorage(DefaultsKey.clipboardCloudSyncFolder) private var cloudSyncFolder = "YTools"
    @AppStorage(DefaultsKey.clipboardCloudSyncPropagateDeletes) private var cloudSyncPropagateDeletes = true
    @State private var showingCloudCredentialsSheet = false

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    var body: some View {
        Form {
            if AppFeature.clipboardHistory.isAvailable {
                Section {
                    Toggle(text.enable, isOn: $enabled)
                        .onChange(of: enabled) { _, _ in
                            ClipboardHistoryService.shared.syncWithPreferences()
                        }
                    Text(text.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(text.localNote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if enabled, history.isRunning {
                        Label(text.active, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .settingsSectionAnchor(.clipboardHistory)

                clipboardShortcutSection
                clipboardMenuBarPreviewSection

                Section {
                    Toggle(text.includeImagesFiles, isOn: $includeImagesFiles)
                        .disabled(!enabled)
                    Text(text.includeImagesFilesCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(text.skipSensitive, isOn: $skipSensitive)
                        .disabled(!enabled)
                    Text(text.skipSensitiveCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ClipboardIgnoredAppsList()
                        .disabled(!enabled)
                    Picker(text.limit, selection: $limit) {
                        ForEach(Defaults.allowedClipboardHistoryLimits, id: \.self) { value in
                            Text(value == 0 ? text.limitUnlimited : "\(value)").tag(value)
                        }
                    }
                    .disabled(!enabled)
                }

                // Its own section because it is the one setting here that keeps
                // working with capture off: the panel entry stays, saying so,
                // and still opens the saved items. Sitting among the disabled
                // rows it read as one that had been missed.
                Section {
                    Toggle(text.showInPanel, isOn: $showInPanel)
                }

                clipboardCloudSyncSection

                clipboardAutoClearSection
            }

            if AppFeature.finderCutPaste.isAvailable {
                Section {
                    Toggle(text.pasteImageAsFile, isOn: $pasteImageAsFile)
                        .onChange(of: pasteImageAsFile) { _, _ in
                            FinderCutPaste.shared.syncWithPreferences()
                        }
                    Text(text.pasteImageAsFileCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if pasteImageAsFile, !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                }
            }

            if AppFeature.pastePlain.isAvailable {
                Section {
                    Toggle(l10n.s.pastePlainName, isOn: $pastePlainEnabled)
                        .onChange(of: pastePlainEnabled) { _, _ in
                            PastePlainService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.pastePlainCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ShortcutPreferenceRow(role: .pastePlain,
                                          isEnabled: pastePlainEnabled) {
                        PastePlainService.shared.syncWithPreferences()
                    }
                    if pastePlainEnabled, pastePlain.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if pastePlainEnabled, !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                } header: {
                    Text(l10n.s.pastePlainName)
                }
                .settingsSectionAnchor(.pastePlain)
            }

            if AppFeature.clipboardHistory.isAvailable {
                clipboardStatsSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            limit = Defaults.sanitizedClipboardHistoryLimit(limit)
            autoClearDelay = Defaults.sanitizedClipboardAutoClearDelay(autoClearDelay)
            menuBarPreviewLength = Defaults.sanitizedClipboardMenuBarPreviewLength(menuBarPreviewLength)
        }
        .onChange(of: limit) { _, value in
            let sanitized = Defaults.sanitizedClipboardHistoryLimit(value)
            if sanitized != value { limit = sanitized }
            ClipboardHistoryService.shared.trimToLimit()
        }
        // No syncWithPreferences() here, unlike the auto-clear toggles: the
        // running poll reads this value from UserDefaults on every tick, so a
        // new delay takes effect on the next one. Syncing would just tear the
        // timer down and restart the wait.
        .onChange(of: autoClearDelay) { _, value in
            let sanitized = Defaults.sanitizedClipboardAutoClearDelay(value)
            if sanitized != value { autoClearDelay = sanitized }
        }
        .onChange(of: menuBarPreviewLength) { _, value in
            let sanitized = Defaults.sanitizedClipboardMenuBarPreviewLength(value)
            if sanitized != value { menuBarPreviewLength = sanitized }
        }
    }

    @ViewBuilder
    private var clipboardShortcutSection: some View {
        Section(text.shortcut) {
            Toggle(text.shortcut, isOn: $shortcutEnabled)
                .onChange(of: shortcutEnabled) { _, _ in
                    ClipboardHistoryService.shared.syncHotkey()
                }
                .disabled(!enabled)
            ShortcutPreferenceRow(role: .clipboard,
                                  isEnabled: enabled && shortcutEnabled,
                                  additionalConflict: WindowLayoutService.shared.shortcutConflictTitle) {
                ClipboardHistoryService.shared.syncHotkey()
            }
            if enabled, shortcutEnabled, history.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(text.shortcutCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                ClipboardHistoryService.shared.showHistoryWindow()
            } label: {
                Label(text.shortcut, systemImage: "doc.on.clipboard")
            }
            .disabled(history.entries.isEmpty)
        }
    }

    @ViewBuilder
    private var clipboardMenuBarPreviewSection: some View {
        Section {
            Toggle(text.menuBarPreview, isOn: $menuBarPreview)
                .disabled(!enabled)
            HStack {
                Text(text.menuBarPreviewLength)
                Spacer()
                TextField("", value: $menuBarPreviewLength, formatter: Self.menuBarPreviewLengthFormatter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                Text(text.menuBarPreviewLengthSuffix)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled || !menuBarPreview)
            Text(text.menuBarPreviewCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let menuBarPreviewLengthFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: Defaults.allowedClipboardMenuBarPreviewLengthRange.lowerBound)
        formatter.maximum = NSNumber(value: Defaults.allowedClipboardMenuBarPreviewLengthRange.upperBound)
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    // Never disabled by the capture toggle, unlike the sections above it:
    // emptying the pasteboard is a security setting in its own right, and
    // someone who keeps no history is exactly who reaches for it.
    @ViewBuilder
    private var clipboardAutoClearSection: some View {
        Section {
            HStack {
                Toggle(text.autoClearEnable, isOn: $autoClearOnDelay)
                    .onChange(of: autoClearOnDelay) { _, _ in
                        ClipboardAutoClearService.shared.syncWithPreferences()
                    }
                TextField("", value: $autoClearDelay, formatter: Self.delayFieldFormatter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .disabled(!autoClearOnDelay)
                Text(text.autoClearSecondsSuffix)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Toggle(text.autoClearOnSleep, isOn: $autoClearOnSleep)
                .onChange(of: autoClearOnSleep) { _, _ in
                    ClipboardAutoClearService.shared.syncWithPreferences()
                }
            Toggle(text.autoClearOnDisplaySleep, isOn: $autoClearOnDisplaySleep)
                .onChange(of: autoClearOnDisplaySleep) { _, _ in
                    ClipboardAutoClearService.shared.syncWithPreferences()
                }
            Toggle(text.autoClearOnScreenLock, isOn: $autoClearOnScreenLock)
                .onChange(of: autoClearOnScreenLock) { _, _ in
                    ClipboardAutoClearService.shared.syncWithPreferences()
                }
            Text(text.autoClearCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let delayFieldFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: Defaults.allowedClipboardAutoClearDelayRange.lowerBound)
        formatter.maximum = NSNumber(value: Defaults.allowedClipboardAutoClearDelayRange.upperBound)
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    @ViewBuilder
    private var clipboardCloudSyncSection: some View {
        Section {
            Toggle(YToolsStrings.syncEnableToggle, isOn: $cloudSyncEnabled)
                .disabled(!enabled)
                .onChange(of: cloudSyncEnabled) { _, _ in
                    ClipboardCloudSyncCoordinator.shared.syncWithPreferences()
                }
            Text(YToolsStrings.syncCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(YToolsStrings.syncFolderLabel)
                Spacer()
                TextField(YToolsStrings.syncFolderPlaceholder, text: $cloudSyncFolder)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .disabled(!enabled || !cloudSyncEnabled)
            }

            Toggle(YToolsStrings.syncPropagateDeletes, isOn: $cloudSyncPropagateDeletes)
                .disabled(!enabled || !cloudSyncEnabled)
            Text(YToolsStrings.syncPropagateDeletesCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(cloudSync.hasCredentials
                       ? YToolsStrings.syncUpdateCredentials
                       : YToolsStrings.syncConfigureCredentials) {
                    showingCloudCredentialsSheet = true
                }
                .disabled(!enabled)

                Button(YToolsStrings.syncNowButton) {
                    cloudSync.syncNow()
                }
                .disabled(!enabled || !cloudSyncEnabled || !cloudSync.hasCredentials || cloudSync.isSyncing)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(cloudSync.hasCredentials
                         ? "\(YToolsStrings.syncCredentialsConfigured) · Device \(cloudSync.deviceShortID)"
                         : YToolsStrings.syncCredentialsMissing)
                        .font(.caption)
                        .foregroundStyle(cloudSync.hasCredentials ? Color.secondary : Color.orange)
                    Text(cloudSync.pendingUploads > 0
                         ? "\(cloudSync.statusMessage) · \(cloudSync.pendingUploads) queued"
                         : cloudSync.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text(YToolsStrings.syncSectionTitle)
        }
        .sheet(isPresented: $showingCloudCredentialsSheet) {
            ClipboardCloudCredentialsSheet(
                initialUsername: cloudSync.accountEmail ?? "",
                onDismiss: { showingCloudCredentialsSheet = false }
            )
        }
    }

    private var clipboardStatsSection: some View {
            Section {
                HStack {
                    Text("\(history.pinnedEntries.count)")
                    Text(text.pinned)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(history.recentEntries.count)")
                    Text(text.recent)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(text.clearRecent) {
                        history.clearRecent()
                    }
                    .disabled(history.recentEntries.isEmpty)
                    Button(text.clearAll) {
                        history.clearAll()
                    }
                    .disabled(history.recentEntries.isEmpty)
                }
            }
    }
}


private struct ClipboardCloudCredentialsSheet: View {
    @State var username: String
    @State private var appPassword = ""
    @State private var passphrase = ""
    @State private var errorMessage: String?
    let onDismiss: () -> Void

    init(initialUsername: String, onDismiss: @escaping () -> Void) {
        _username = State(initialValue: initialUsername)
        self.onDismiss = onDismiss
    }

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appPassword.isEmpty
            && passphrase.count >= 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(YToolsStrings.syncModalTitle)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(YToolsStrings.syncAccountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("you@example.com", text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(YToolsStrings.syncAppPasswordLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Jianguoyun WebDAV app password", text: $appPassword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(YToolsStrings.syncPassphraseLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(passphrase.count)/12+ chars")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(passphrase.count >= 12 ? Color.secondary : Color.orange)
                }
                SecureField("Shared E2EE passphrase", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                Text(YToolsStrings.syncPassphraseHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(YToolsStrings.syncCancelButton, action: onDismiss)
                Button(YToolsStrings.syncSaveButton) {
                    Task {
                        if let err = await ClipboardCloudSyncCoordinator.shared.saveCredentials(
                            username: username,
                            appPassword: appPassword,
                            syncPassphrase: passphrase
                        ) {
                            errorMessage = err
                        } else {
                            onDismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
