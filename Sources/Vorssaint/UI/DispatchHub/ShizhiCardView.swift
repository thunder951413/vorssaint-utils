// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ShizhiCardView: View {
    let item: ShizhiItemPayload
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpand: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false
    @State private var showAllPoints = false
    @State private var isHovered = false

    private var text: DispatchHubFeatureStrings { FeatureStrings.dispatchHub(l10n.language) }

    private var statusColor: Color {
        if item.status == "ready" { return PanelMetricColor.green(for: scheme) }
        if item.status == "awaiting_ai" { return PanelMetricColor.yellow(for: scheme) }
        if item.status == "failed" || item.status == "cancelled" { return PanelMetricColor.red(for: scheme) }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Header
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PanelMetricColor.mint(for: scheme).opacity(0.16))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "books.vertical")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PanelMetricColor.mint(for: scheme))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? 3 : 2)
                    HStack(spacing: 4) {
                        Text(item.source)
                        if item.segmentCount > 0 {
                            Text("· \(item.segmentCount) 段")
                        }
                        let rel = DispatchDateParser.relativeString(from: item.updatedAt.isEmpty ? item.createdAt : item.updatedAt)
                        if !rel.isEmpty {
                            Text("· \(rel)")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.stageLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(statusColor.opacity(0.14))
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            // Active progress bar + 5 stage dots
            if item.isActive {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(0 ..< 5, id: \.self) { idx in
                            Circle()
                                .fill(idx <= item.stageIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 5, height: 5)
                        }
                        if !item.message.isEmpty {
                            Text(item.message)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.accentColor.opacity(0.15))
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(12, geo.size.width * min(1, max(0.06, item.progress / 100.0))))
                        }
                    }
                    .frame(height: 3)
                }
            } else if item.status == "failed" {
                Text(item.error.isEmpty ? item.message : item.error)
                    .font(.system(size: 11))
                    .foregroundStyle(PanelMetricColor.red(for: scheme))
                    .lineLimit(isExpanded ? 4 : 2)
            } else if !item.summary.isEmpty {
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle(text.summarySection)
                        Text(item.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)

                        if !item.keyPoints.isEmpty {
                            sectionTitle(text.keyPointsSection)
                            let shown = showAllPoints ? item.keyPoints : Array(item.keyPoints.prefix(5))
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(shown.enumerated()), id: \.offset) { _, pt in
                                    HStack(alignment: .top, spacing: 5) {
                                        Text("•")
                                            .foregroundStyle(.secondary)
                                        Text(pt)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(.primary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            if item.keyPoints.count > 5 {
                                Button(showAllPoints ? text.collapse : "\(text.expandMore) (\(item.keyPoints.count))") {
                                    showAllPoints.toggle()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                } else {
                    Text(item.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if !item.message.isEmpty {
                Text(item.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Action row (shown when expanded, selected, hovered, or failed)
            if isExpanded || isSelected || isHovered || item.status == "failed" {
                HStack(spacing: 6) {
                    if !item.summary.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.markdownSummary, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                        } label: {
                            Label(copied ? text.copied : text.copySummary, systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    if item.status == "failed" {
                        Button {
                            onRetry()
                        } label: {
                            Label(text.retryAction, systemImage: "arrow.clockwise")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }

                    if let openURL = URL(string: item.openURL), !item.openURL.isEmpty {
                        Button {
                            NSWorkspace.shared.open(openURL)
                        } label: {
                            Label(text.openInShizhi, systemImage: "arrow.up.right.square")
                                .font(.system(size: 10.5))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Spacer(minLength: 4)

                    Menu {
                        if let raw = URL(string: item.url) {
                            Button(text.openOriginalURL) { NSWorkspace.shared.open(raw) }
                        }
                        Button("复制链接") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.url, forType: .string)
                        }
                        Divider()
                        Button(text.removeFromList, role: .destructive) { onRemove() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(10)
        .panelCard()
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .onHover { isHovered = $0 }
    }
}
