// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DispatchStatusDot: View {
    let state: DispatchConnectionState
    let label: String
    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        switch state {
        case .connected: return PanelMetricColor.green(for: scheme)
        case .unconfigured: return PanelMetricColor.yellow(for: scheme)
        case .unreachable: return PanelMetricColor.red(for: scheme)
        case .unknown: return .secondary
        }
    }

    private var statusWord: String {
        let s = FeatureStrings.dispatchHub(L10n.shared.language)
        switch state {
        case .connected: return s.statusConnected
        case .unconfigured: return s.statusUnconfigured
        case .unreachable: return s.statusUnreachable
        case .unknown: return "—"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label) \(statusWord)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct DispatchBannerView: View {
    let banner: DispatchBannerState
    let onOpenSettings: (DispatchTargetID?) -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let text = FeatureStrings.dispatchHub(L10n.shared.language)
        let red = PanelMetricColor.red(for: scheme)
        HStack(spacing: 8) {
            Image(systemName: banner.isUnauthorized ? "key.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(red)
            Text(banner.message)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(text.openSettingsAction) {
                onOpenSettings(banner.target)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(red.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(red.opacity(0.28), lineWidth: 1)
                )
        )
    }
}
