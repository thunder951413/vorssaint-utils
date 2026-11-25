// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct DispatchHubView: View {
    @ObservedObject var service: DispatchHubService
    @ObservedObject var store: DispatchHubStore
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var scheme

    @State private var deleteTargetCard: TeamsTriageCard? = nil

    private var text: DispatchHubFeatureStrings { FeatureStrings.dispatchHub(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            ZStack(alignment: .top) {
                VStack(spacing: 8) {
                    DispatchComposerView(
                        store: store,
                        preferredBrowserBundleID: service.previousFrontmostBundleID
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 8)

                    if let banner = store.banner {
                        DispatchBannerView(
                            banner: banner,
                            onOpenSettings: { target in
                                store.banner = nil
                                store.openSettings(focus: target)
                            },
                            onDismiss: { store.banner = nil }
                        )
                        .padding(.horizontal, 10)
                    }

                    filterBar
                        .padding(.horizontal, 10)

                    contentList
                }

                if store.showSettings {
                    DispatchSettingsDrawer(store: store)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(.easeOut(duration: 0.18), value: store.showSettings)

            Divider().opacity(0.4)
            footer
        }
        .frame(minWidth: 380, minHeight: 420)
        .background(HUDBackdrop(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .alert(
            text.deleteConfirmTitle,
            isPresented: Binding(
                get: { deleteTargetCard != nil },
                set: { if !$0 { deleteTargetCard = nil } }
            )
        ) {
            Button(text.cancel, role: .cancel) { deleteTargetCard = nil }
            Button(text.deleteAction, role: .destructive) {
                if let card = deleteTargetCard {
                    deleteTargetCard = nil
                    Task { await store.deleteTeamsCard(card.id) }
                }
            }
        } message: {
            Text(text.deleteConfirmMessage)
        }
    }

    // MARK: - Header (34pt)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(text.pageTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Button {
                service.toggleWideMode()
            } label: {
                Image(systemName: service.isWideMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11.5))
                    .foregroundStyle(service.isWideMode ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(service.isWideMode ? "恢复标准尺寸 (⌘E)" : "切换宽屏阅读模式 (⌘E)")

            Button {
                store.showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(store.showSettings ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(text.settingsTooltip)

            Button {
                service.togglePin()
            } label: {
                Image(systemName: service.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11.5))
                    .foregroundStyle(service.isPinned ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(service.isPinned ? text.unpinTooltip : text.pinTooltip)

            Button {
                service.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(text.closeTooltip)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(DispatchWindowDragArea())
    }

    // MARK: - Filter Bar (24pt)

    private var filterBar: some View {
        HStack(spacing: 5) {
            filterChip(.all, label: text.filterAll, count: store.allCount)
            filterChip(.active, label: text.filterActive, count: store.activeCount)
            filterChip(.pendingReply, label: text.filterPendingReply, count: store.pendingReplyCount)
            filterChip(.done, label: text.filterDone, count: store.doneCount)
            Spacer(minLength: 4)
            if DispatchHubSettings.isConfigured(.teams) {
                Button {
                    Task { await store.syncTeams(silent: false) }
                } label: {
                    HStack(spacing: 3) {
                        if store.isSyncingTeams {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                        }
                        Text(text.syncTeams)
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(store.isSyncingTeams)
            }
        }
        .frame(height: 24)
    }

    private func filterChip(_ f: DispatchFilter, label: String, count: Int) -> some View {
        let active = store.filter == f
        return Button {
            store.filter = f
        } label: {
            HStack(spacing: 3) {
                Text(label)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .opacity(0.8)
                }
            }
            .font(.system(size: 10.5, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(active ? Color.accentColor.opacity(0.14) : PanelSurface.controlFill(for: scheme).opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content List

    private var contentList: some View {
        let items = store.filteredItems
        return Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { item in
                                cardView(for: item)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                    .onChange(of: store.selectedItemID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cardView(for item: DispatchItem) -> some View {
        let expanded = store.expandedItemID == item.id
        let selected = store.selectedItemID == item.id
        switch item {
        case .shizhi(let payload):
            ShizhiCardView(
                item: payload,
                isExpanded: expanded,
                isSelected: selected,
                onToggleExpand: { store.toggleExpand(item.id) },
                onRetry: { store.retryShizhiItem(payload) },
                onRemove: { store.removeShizhiItem(payload.id) }
            )
        case .teams(let card):
            TeamsCardView(
                card: card,
                isExpanded: expanded,
                isSelected: selected,
                isBusy: store.busyCardIDs.contains(item.id),
                inlineError: store.cardErrors[item.id],
                onToggleExpand: { store.toggleExpand(item.id) },
                onRefresh: { Task { await store.refreshTeamsCard(card.id) } },
                onRefine: { note in Task { await store.refineTeamsCard(card.id, note: note) } },
                onToggleStatus: { Task { await store.toggleTeamsStatus(card) } },
                onRequestDelete: { deleteTargetCard = card }
            )
        case .failed(let failed):
            failedCardView(failed, isSelected: selected)
        }
    }

    private func failedCardView(_ failed: LocalFailedDispatch, isSelected: Bool) -> some View {
        let red = PanelMetricColor.red(for: scheme)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(red)
                Text(failed.title.isEmpty ? failed.url : failed.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(failed.target == .shizhi ? text.shizhiName : text.teamsName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(failed.errorMessage)
                .font(.system(size: 11))
                .foregroundStyle(red)
                .lineLimit(2)
            HStack(spacing: 6) {
                Button {
                    store.retryFailed(failed)
                } label: {
                    Label(text.retryAction, systemImage: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Button(text.removeFromList) {
                    store.removeFailed(failed.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .panelCard()
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : red.opacity(0.3), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        let noneConfigured = !DispatchHubSettings.isConfigured(.shizhi) && !DispatchHubSettings.isConfigured(.teams)
        return VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(
                noneConfigured
                    ? text.emptyUnconfiguredTitle
                    : (store.filter == .all ? text.emptyConfiguredTitle : text.emptyFilteredTitle)
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)

            if noneConfigured {
                Button(text.emptyUnconfiguredAction) {
                    store.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer (36pt)

    private var footer: some View {
        HStack(spacing: 10) {
            DispatchStatusDot(state: store.shizhiConnection, label: text.shizhiName)
            DispatchStatusDot(state: store.teamsConnection, label: text.teamsName)
            Spacer()
            if store.doneCount > 0 || !store.failedItems.isEmpty {
                Button(text.clearDone) {
                    store.clearDoneItems()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}

/// Allows dragging the borderless floating NSPanel by its header strip.
private struct DispatchWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
