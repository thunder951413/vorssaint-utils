// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DispatchComposerView: View {
    @ObservedObject var store: DispatchHubStore
    let preferredBrowserBundleID: String?
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var scheme

    private var text: DispatchHubFeatureStrings { FeatureStrings.dispatchHub(l10n.language) }

    private var hasInvalidURL: Bool {
        !store.isInputEmpty && store.parsedURL == nil
    }

    private func targetDisplayName(_ target: DispatchTargetID) -> String {
        switch target {
        case .shizhi: return text.shizhiName
        case .teams: return text.teamsName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // URL Row
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hasInvalidURL ? PanelMetricColor.red(for: scheme) : .secondary)
                    TextField(text.urlPlaceholder, text: $store.urlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit { store.submitCurrent() }
                    if !store.urlInput.isEmpty {
                        Button {
                            store.urlInput = ""
                            store.titleHint = ""
                            store.browserErrorCaption = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PanelSurface.controlFill(for: scheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    hasInvalidURL
                                        ? PanelMetricColor.red(for: scheme).opacity(0.7)
                                        : PanelSurface.border(for: scheme),
                                    lineWidth: 1
                                )
                        )
                )

                Button {
                    store.pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(PanelSurface.controlFill(for: scheme)))
                .help(text.pasteButton)

                Button {
                    store.grabBrowserURL(preferredBundleID: preferredBrowserBundleID)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(PanelSurface.controlFill(for: scheme)))
                .help("\(text.browserURLButton) (⌘B)")
            }

            // Inline hint (prefill / invalid URL / browser permission error)
            if hasInvalidURL {
                Text(text.invalidURLHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelMetricColor.red(for: scheme))
            } else if !store.browserErrorCaption.isEmpty {
                Text(store.browserErrorCaption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelMetricColor.orange(for: scheme))
                    .lineLimit(2)
            } else if !store.prefillCaption.isEmpty {
                Text(store.prefillCaption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelMetricColor.green(for: scheme))
                    .transition(.opacity)
            }

            // Optional Note / Context Row
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField(text.notePlaceholder, text: $store.noteInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .onSubmit { store.submitCurrent() }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(PanelSurface.controlFill(for: scheme).opacity(0.75))
            )

            // Route + Reason + Send Row
            HStack(spacing: 6) {
                Text(text.routeLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Menu {
                    Button {
                        store.manualTarget = nil
                    } label: {
                        Label(
                            "\(text.routeAuto) · \(targetDisplayName(store.autoMatch?.target ?? .shizhi))",
                            systemImage: store.manualTarget == nil ? "checkmark" : "wand.and.stars"
                        )
                    }
                    Divider()
                    ForEach(DispatchTargetID.allCases) { target in
                        let configured = DispatchHubSettings.isConfigured(target)
                        Button {
                            if configured {
                                store.manualTarget = target
                            } else {
                                store.openSettings(focus: target)
                            }
                        } label: {
                            let label = configured
                                ? targetDisplayName(target)
                                : "\(targetDisplayName(target))（\(text.configureServicePrefix)）"
                            Label(label, systemImage: store.manualTarget == target ? "checkmark" : (target == .shizhi ? "books.vertical" : "bubble.left.and.text.bubble.right"))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.effectiveTarget == .shizhi ? "books.vertical" : "bubble.left.and.text.bubble.right")
                            .font(.system(size: 10))
                        Text(
                            store.manualTarget == nil
                                ? "\(text.routeAuto)·\(targetDisplayName(store.effectiveTarget))"
                                : targetDisplayName(store.effectiveTarget)
                        )
                        .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PanelSurface.controlFill(for: scheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        store.manualTarget != nil ? Color.accentColor.opacity(0.65) : PanelSurface.border(for: scheme),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if store.manualTarget != nil {
                    Button {
                        store.manualTarget = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(text.routeResetAuto)
                }

                if store.effectiveTarget == .teams {
                    HStack(spacing: 2) {
                        ForEach(TeamsTriageMode.allCases) { mode in
                            let active = store.teamsMode == mode
                            Button {
                                store.teamsMode = mode
                            } label: {
                                Text(mode.label)
                                    .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? Color.accentColor : .secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(active ? Color.accentColor.opacity(0.16) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PanelSurface.controlFill(for: scheme))
                    )
                } else if let reason = store.autoMatch?.reason, store.manualTarget == nil {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                if !store.effectiveTargetConfigured && store.parsedURL != nil {
                    Button("\(text.configureServicePrefix) \(targetDisplayName(store.effectiveTarget))…") {
                        store.openSettings(focus: store.effectiveTarget)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        store.submitCurrent()
                    } label: {
                        HStack(spacing: 4) {
                            if store.isSubmitting {
                                ProgressView()
                                    .controlSize(.mini)
                                Text(text.sendingButton)
                            } else if store.submitJustSucceeded {
                                Image(systemName: "checkmark")
                                Text(text.sendButton)
                            } else {
                                Text("\(text.sendButton) ⌘↩")
                            }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.parsedURL == nil || store.isSubmitting)
                }
            }
        }
        .padding(10)
        .panelCard()
    }
}
