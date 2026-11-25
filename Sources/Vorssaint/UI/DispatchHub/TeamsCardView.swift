// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct TeamsCardView: View {
    let card: TeamsTriageCard
    let isExpanded: Bool
    let isSelected: Bool
    let isBusy: Bool
    let inlineError: String?
    let onToggleExpand: () -> Void
    let onRefresh: () -> Void
    let onRefine: (String) -> Void
    let onToggleStatus: () -> Void
    let onRequestDelete: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false
    @State private var refineText = ""
    @State private var showSources = false
    @State private var isHovered = false

    private var text: DispatchHubFeatureStrings { FeatureStrings.dispatchHub(l10n.language) }

    private var urgencyColor: Color {
        if card.isDone { return .secondary }
        switch card.urgency {
        case .high: return PanelMetricColor.red(for: scheme)
        case .medium: return PanelMetricColor.orange(for: scheme)
        case .low: return .secondary
        }
    }

    private var verdictColor: Color {
        switch card.verdict {
        case .replyReady: return PanelMetricColor.green(for: scheme)
        case .needInfo: return PanelMetricColor.yellow(for: scheme)
        case .needAction: return PanelMetricColor.orange(for: scheme)
        case .noAction: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PanelMetricColor.cyan(for: scheme).opacity(0.16))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PanelMetricColor.cyan(for: scheme))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? 3 : 2)
                    HStack(spacing: 4) {
                        if !card.who.isEmpty {
                            Text(card.who)
                        }
                        let rel = DispatchDateParser.relativeString(from: card.latestMessageAt.isEmpty ? card.updatedAt : card.latestMessageAt)
                        if !rel.isEmpty {
                            Text(card.who.isEmpty ? rel : "· \(rel)")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else if card.isSummaryMode {
                    Text("对话总结")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PanelMetricColor.cyan(for: scheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(PanelMetricColor.cyan(for: scheme).opacity(0.14)))
                } else {
                    Text(card.isDone ? "已处理" : card.urgency.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(urgencyColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(urgencyColor.opacity(0.14)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            // Verdict + Action bar (triage mode) or status caption (summary mode)
            if card.isSummaryMode {
                if !card.action.isEmpty {
                    Text(card.action)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? 3 : 1)
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Text(card.verdict.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(verdictColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(verdictColor.opacity(0.14)))
                        .fixedSize()
                    if !card.action.isEmpty {
                        Text(card.action)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? 4 : 1)
                    }
                }
            }

            if let inlineError, !inlineError.isEmpty {
                Text(inlineError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelMetricColor.red(for: scheme))
            }

            // Collapsed preview vs Expanded full details
            if !isExpanded {
                if !card.summary.isEmpty {
                    Text(card.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else if card.isSummaryMode {
                VStack(alignment: .leading, spacing: 8) {
                    if !card.summary.isEmpty {
                        HStack {
                            sectionTitle(text.summarySection)
                            Spacer()
                            Button {
                                copySummary()
                            } label: {
                                Label(copied ? text.copied : text.copySummary, systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                        Text(card.summary)
                            .font(.system(size: 13))
                            .lineSpacing(3.5)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(PanelSurface.controlFill(for: scheme))
                            )
                    }

                    if !card.keyPoints.isEmpty {
                        sectionTitle(text.keyPointsSection)
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(card.keyPoints.enumerated()), id: \.offset) { _, pt in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(PanelMetricColor.cyan(for: scheme))
                                    Text(pt)
                                        .font(.system(size: 12.5))
                                        .lineSpacing(3)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    HStack(spacing: 6) {
                        TextField("输入关注重点，重新总结对话…", text: $refineText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(PanelSurface.controlFill(for: scheme).opacity(0.75))
                            )
                            .onSubmit { triggerRefine() }

                        Button {
                            triggerRefine()
                        } label: {
                            Label("重新总结", systemImage: "sparkles")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy || refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if card.hasMediaWarning {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 11))
                            Text(text.mediaWarning)
                                .font(.system(size: 10.5))
                        }
                        .foregroundStyle(PanelMetricColor.yellow(for: scheme))
                    }
                }
            } else {
                if !card.summary.isEmpty {
                    Text(card.summary)
                        .font(.system(size: 13))
                        .lineSpacing(3.5)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                // Missing info (clickable to fill refine context)
                if !card.missingInfo.isEmpty {
                    let yellow = PanelMetricColor.yellow(for: scheme)
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle(text.missingInfoSection)
                        ForEach(Array(card.missingInfo.enumerated()), id: \.offset) { _, info in
                            Button {
                                if refineText.isEmpty {
                                    refineText = "\(info)："
                                } else {
                                    refineText += "；\(info)："
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(yellow)
                                    Text(info)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 5)
                    .padding(.trailing, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(yellow.opacity(0.08))
                    )
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(yellow)
                            .frame(width: 2.5)
                    }
                }

                // Primary Suggested Reply block
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        sectionTitle(text.suggestedReplySection)
                        Spacer()
                        if !card.suggestedReply.isEmpty {
                            Button {
                                copyReply()
                            } label: {
                                Label(copied ? text.copied : text.copyReply, systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }

                    if card.suggestedReply.isEmpty {
                        Text(text.noSuggestedReply)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(PanelSurface.controlFill(for: scheme).opacity(0.6))
                            )
                    } else {
                        Text(card.suggestedReply)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(PanelSurface.controlFill(for: scheme))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(PanelSurface.border(for: scheme), lineWidth: 1)
                                    )
                            )
                    }
                }

                // Inline context refine input
                HStack(spacing: 6) {
                    TextField(text.refinePlaceholder, text: $refineText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(PanelSurface.controlFill(for: scheme).opacity(0.75))
                        )
                        .onSubmit { triggerRefine() }

                    Button {
                        triggerRefine()
                    } label: {
                        Label(text.refineButton, systemImage: "sparkles")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy || refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Media warning
                if card.hasMediaWarning {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 11))
                        Text(text.mediaWarning)
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(PanelMetricColor.yellow(for: scheme))
                }

                // Sources
                if !card.sources.isEmpty {
                    DisclosureGroup("\(text.sourcesTitlePrefix) (\(card.sources.count))", isExpanded: $showSources) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(card.sources) { src in
                                HStack(spacing: 5) {
                                    Text("[\(src.n)]")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    if let raw = src.url, let url = URL(string: raw) {
                                        Button(src.title) {
                                            NSWorkspace.shared.open(url)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.accentColor)
                                        .lineLimit(1)
                                    } else {
                                        Text(src.title)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }

            // Action row
            if isExpanded || isSelected || isHovered {
                HStack(spacing: 6) {
                    if !isExpanded && !card.isSummaryMode && !card.suggestedReply.isEmpty {
                        Button {
                            copyReply()
                        } label: {
                            Label(copied ? text.copied : text.copyReply, systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    } else if !isExpanded && card.isSummaryMode && !card.summary.isEmpty {
                        Button {
                            copySummary()
                        } label: {
                            Label(copied ? text.copied : text.copySummary, systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Button {
                        onRefresh()
                    } label: {
                        Label(text.refreshAction, systemImage: "arrow.clockwise")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isBusy)

                    if !card.isSummaryMode {
                        Button {
                            onToggleStatus()
                        } label: {
                            Label(card.isDone ? text.reopenAction : text.markDone,
                                  systemImage: card.isDone ? "arrow.uturn.backward" : "checkmark.circle")
                                .font(.system(size: 10.5))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isBusy)
                    }

                    Spacer(minLength: 4)

                    if let url = URL(string: card.url), !card.url.isEmpty {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                                .frame(width: 22, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(text.openOriginalURL)
                    }

                    Menu {
                        if let url = URL(string: card.url), !card.url.isEmpty {
                            Button(text.openOriginalURL) { NSWorkspace.shared.open(url) }
                        }
                        Button("复制链接") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(card.url, forType: .string)
                        }
                        Divider()
                        Button(text.deleteAction, role: .destructive) { onRequestDelete() }
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
        .opacity(card.isDone ? 0.62 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .onHover { isHovered = $0 }
    }

    private func copyReply() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.suggestedReply, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.markdownSummary, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func triggerRefine() {
        let trimmed = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        onRefine(trimmed)
        refineText = ""
    }
}
