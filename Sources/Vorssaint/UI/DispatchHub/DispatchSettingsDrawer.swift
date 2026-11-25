// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DispatchSettingsDrawer: View {
    @ObservedObject var store: DispatchHubStore
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var scheme

    @AppStorage(DefaultsKey.dispatchHubShizhiEnabled) private var shizhiEnabled = true
    @AppStorage(DefaultsKey.dispatchHubShizhiURL) private var shizhiURL = "http://127.0.0.1:8767"
    @AppStorage(DefaultsKey.dispatchHubTeamsEnabled) private var teamsEnabled = false
    @AppStorage(DefaultsKey.dispatchHubTeamsURL) private var teamsURL = ""
    @AppStorage(DefaultsKey.dispatchHubTeamsMe) private var teamsMe = ""
    @AppStorage(DefaultsKey.dispatchHubAutoPrefill) private var autoPrefill = true
    @AppStorage(DefaultsKey.dispatchHubCloseOnClickOutside) private var closeOnClickOutside = true
    @AppStorage(DefaultsKey.dispatchHubShortcutEnabled) private var shortcutEnabled = false

    @State private var shizhiToken = ""
    @State private var teamsToken = ""
    @State private var showShizhiToken = false
    @State private var showTeamsToken = false
    @State private var shizhiTestResult: (ok: Bool, message: String)? = nil
    @State private var teamsTestResult: (ok: Bool, message: String)? = nil
    @State private var testingShizhi = false
    @State private var testingTeams = false

    private var text: DispatchHubFeatureStrings { FeatureStrings.dispatchHub(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(text.settingsTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button {
                        store.showSettings = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Shizhi section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(text.shizhiName, systemImage: "books.vertical")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: $shizhiEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    fieldRow(text.serviceURLLabel) {
                        TextField("http://127.0.0.1:8767", text: $shizhiURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                    }

                    tokenRow(
                        label: text.tokenLabel,
                        placeholder: "留空时将自动从本机拾知获取",
                        value: $shizhiToken,
                        revealed: $showShizhiToken
                    ) {
                        DispatchHubSettings.setToken(shizhiToken, for: .shizhi)
                    }

                    HStack(spacing: 8) {
                        Button(testingShizhi ? text.testingConnection : text.testConnection) {
                            testShizhi()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(testingShizhi || shizhiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let res = shizhiTestResult {
                            Text(res.message)
                                .font(.system(size: 10.5))
                                .foregroundStyle(res.ok ? PanelMetricColor.green(for: scheme) : PanelMetricColor.red(for: scheme))
                                .lineLimit(2)
                        }
                    }
                }
                .padding(10)
                .panelCard()

                // Teams Triage section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(text.teamsName, systemImage: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: $teamsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    fieldRow(text.serviceURLLabel) {
                        TextField("https://your-steward.example.com", text: $teamsURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                    }

                    tokenRow(
                        label: text.tokenLabel,
                        placeholder: text.tokenOptionalPlaceholder,
                        value: $teamsToken,
                        revealed: $showTeamsToken
                    ) {
                        DispatchHubSettings.setToken(teamsToken, for: .teams)
                    }

                    fieldRow(text.teamsMeLabel) {
                        TextField(text.teamsMePlaceholder, text: $teamsMe)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                    }

                    HStack(spacing: 8) {
                        Button(testingTeams ? text.testingConnection : text.testConnection) {
                            testTeams()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(testingTeams || teamsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let res = teamsTestResult {
                            Text(res.message)
                                .font(.system(size: 10.5))
                                .foregroundStyle(res.ok ? PanelMetricColor.green(for: scheme) : PanelMetricColor.red(for: scheme))
                                .lineLimit(2)
                        }
                    }
                }
                .padding(10)
                .panelCard()

                // Behavior section
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle(text.behaviorSection)
                    Toggle(text.autoPrefillClipboard, isOn: $autoPrefill)
                        .font(.system(size: 11.5))
                    Toggle(text.closeOnClickOutside, isOn: $closeOnClickOutside)
                        .font(.system(size: 11.5))
                    Toggle(text.shortcutLabel, isOn: $shortcutEnabled)
                        .font(.system(size: 11.5))
                        .onChange(of: shortcutEnabled) { _, _ in
                            DispatchHubService.shared.syncWithPreferences()
                        }
                    ShortcutPreferenceRow(role: .dispatchHub, isEnabled: shortcutEnabled) {
                        DispatchHubService.shared.syncWithPreferences()
                    }
                }
                .padding(10)
                .panelCard()
            }
            .padding(10)
        }
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(scheme == .dark ? 0.94 : 0.96)
        )
        .onAppear {
            shizhiToken = DispatchHubSettings.token(for: .shizhi)
            teamsToken = DispatchHubSettings.token(for: .teams)
        }
        .onChange(of: shizhiEnabled) { _, _ in store.refreshConnectionStatesFromConfig() }
        .onChange(of: shizhiURL) { _, _ in store.refreshConnectionStatesFromConfig() }
        .onChange(of: teamsEnabled) { _, _ in store.refreshConnectionStatesFromConfig() }
        .onChange(of: teamsURL) { _, _ in store.refreshConnectionStatesFromConfig() }
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func tokenRow(
        label: String,
        placeholder: String,
        value: Binding<String>,
        revealed: Binding<Bool>,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Group {
                    if revealed.wrappedValue {
                        TextField(placeholder, text: value)
                    } else {
                        SecureField(placeholder, text: value)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .onChange(of: value.wrappedValue) { _, _ in onCommit() }

                Button {
                    revealed.wrappedValue.toggle()
                } label: {
                    Image(systemName: revealed.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func testShizhi() {
        testingShizhi = true
        shizhiTestResult = nil
        let url = shizhiURL
        let tok = shizhiToken
        Task {
            defer { testingShizhi = false }
            do {
                let res = try await ShizhiClient.testConnection(baseURL: url, token: tok)
                if shizhiToken.isEmpty && !res.resolvedToken.isEmpty {
                    shizhiToken = res.resolvedToken
                    DispatchHubSettings.setToken(res.resolvedToken, for: .shizhi)
                }
                store.shizhiConnection = .connected
                shizhiTestResult = (true, "连接成功 · \(res.latencyMs)ms")
            } catch {
                store.shizhiConnection = .unreachable(error.localizedDescription)
                shizhiTestResult = (false, error.localizedDescription)
            }
        }
    }

    private func testTeams() {
        testingTeams = true
        teamsTestResult = nil
        let url = teamsURL
        let tok = teamsToken
        Task {
            defer { testingTeams = false }
            do {
                let res = try await TeamsTriageClient.testConnection(baseURL: url, token: tok)
                if teamsMe.isEmpty, let serverMe = res.me, !serverMe.isEmpty {
                    teamsMe = serverMe
                }
                store.teamsConnection = .connected
                teamsTestResult = (true, "连接成功 · \(res.latencyMs)ms")
            } catch {
                store.teamsConnection = .unreachable(error.localizedDescription)
                teamsTestResult = (false, error.localizedDescription)
            }
        }
    }
}
