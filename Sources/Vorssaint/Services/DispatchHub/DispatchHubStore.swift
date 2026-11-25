// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

@MainActor
final class DispatchHubStore: ObservableObject {
    @Published var urlInput: String = ""
    @Published var titleHint: String = ""
    @Published var noteInput: String = ""
    @Published var manualTarget: DispatchTargetID? = nil
    @Published var teamsMode: TeamsTriageMode = .summary
    @Published var prefillCaption: String = ""
    @Published var browserErrorCaption: String = ""

    @Published var filter: DispatchFilter = .all
    @Published var expandedItemID: String? = nil
    @Published var selectedItemID: String? = nil

    @Published private(set) var shizhiItems: [ShizhiItemPayload] = []
    @Published private(set) var teamsCards: [TeamsTriageCard] = []
    @Published private(set) var failedItems: [LocalFailedDispatch] = []
    @Published private(set) var busyCardIDs: Set<String> = []
    @Published private(set) var cardErrors: [String: String] = [:]

    @Published private(set) var isSubmitting = false
    @Published private(set) var submitJustSucceeded = false
    @Published private(set) var isSyncingTeams = false
    @Published var banner: DispatchBannerState? = nil
    @Published var shizhiConnection: DispatchConnectionState = .unknown
    @Published var teamsConnection: DispatchConnectionState = .unknown

    @Published var showSettings = false
    @Published var settingsFocusTarget: DispatchTargetID? = nil

    var isPanelVisible: Bool = false {
        didSet {
            if isPanelVisible {
                restartPollingIfNeeded(resetInterval: true)
            }
        }
    }

    private let clipboardPrefill = ClipboardURLPrefill()
    private var pollTask: Task<Void, Never>?
    private var prefillClearTask: Task<Void, Never>?
    private var consecutivePollErrors = 0

    init() {
        shizhiItems = DispatchHubSettings.loadShizhiItems()
        refreshConnectionStatesFromConfig()
    }

    func refreshConnectionStatesFromConfig() {
        if !DispatchHubSettings.isConfigured(.shizhi) {
            shizhiConnection = .unconfigured
        } else if case .unconfigured = shizhiConnection {
            shizhiConnection = .unknown
        }
        if !DispatchHubSettings.isConfigured(.teams) {
            teamsConnection = .unconfigured
        } else if case .unconfigured = teamsConnection {
            teamsConnection = .unknown
        }
    }

    // MARK: - Routing

    var parsedURL: URL? {
        DispatchRouter.parseURL(urlInput)
    }

    var isInputEmpty: Bool {
        urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var autoMatch: DispatchMatch? {
        guard let url = parsedURL else { return nil }
        return DispatchRouter.route(for: url)
    }

    var effectiveTarget: DispatchTargetID {
        if let manualTarget { return manualTarget }
        return autoMatch?.target ?? .shizhi
    }

    var effectiveTargetConfigured: Bool {
        DispatchHubSettings.isConfigured(effectiveTarget)
    }

    // MARK: - Unified List & Counts

    var allItems: [DispatchItem] {
        var combined: [DispatchItem] = []
        combined.append(contentsOf: shizhiItems.map { .shizhi($0) })
        combined.append(contentsOf: teamsCards.map { .teams($0) })
        combined.append(contentsOf: failedItems.map { .failed($0) })

        return combined.sorted { lhs, rhs in
            if lhs.sortBucket != rhs.sortBucket {
                return lhs.sortBucket < rhs.sortBucket
            }
            if case .teams(let a) = lhs, case .teams(let b) = rhs, !a.isDone && !b.isDone {
                if a.urgency.rank != b.urgency.rank {
                    return a.urgency.rank < b.urgency.rank
                }
            }
            return lhs.sortTimestamp > rhs.sortTimestamp
        }
    }

    var filteredItems: [DispatchItem] {
        switch filter {
        case .all:
            return allItems
        case .active:
            return allItems.filter { $0.isActive }
        case .pendingReply:
            return allItems.filter { $0.isPendingReply }
        case .done:
            return allItems.filter { $0.isDone }
        }
    }

    var allCount: Int { allItems.count }
    var activeCount: Int { allItems.filter { $0.isActive }.count }
    var pendingReplyCount: Int { allItems.filter { $0.isPendingReply }.count }
    var doneCount: Int { allItems.filter { $0.isDone }.count }

    // MARK: - Panel Lifecycle Hooks

    func onPanelShown() {
        isPanelVisible = true
        browserErrorCaption = ""
        refreshConnectionStatesFromConfig()
        if DispatchHubSettings.autoPrefillClipboard && isInputEmpty {
            if let url = clipboardPrefill.consumeNewURL() {
                urlInput = url
                titleHint = ""
                showPrefillHint(FeatureStrings.dispatchHub(L10n.shared.language).prefilledClipboard)
            }
        }
        Task {
            await syncAllOnOpen()
        }
        restartPollingIfNeeded(resetInterval: true)
    }

    func onPanelHidden() {
        isPanelVisible = false
    }

    func stopAllPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func syncAllOnOpen() async {
        if DispatchHubSettings.isConfigured(.teams) {
            await syncTeams(silent: true)
        }
        if DispatchHubSettings.isConfigured(.shizhi) {
            await syncShizhiRecent(silent: true)
        }
    }

    // MARK: - Prefill Helpers

    func pasteFromClipboard() {
        browserErrorCaption = ""
        if let url = clipboardPrefill.readCurrentURL() {
            urlInput = url
            titleHint = ""
            showPrefillHint(FeatureStrings.dispatchHub(L10n.shared.language).prefilledClipboard)
        } else if let raw = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty {
            urlInput = raw
            titleHint = ""
        }
    }

    func grabBrowserURL(preferredBundleID: String?) {
        browserErrorCaption = ""
        switch BrowserURLProvider.fetchFrontBrowserTab(preferredBundleID: preferredBundleID) {
        case .success(let tab):
            urlInput = tab.url
            titleHint = tab.title
            let prefix = FeatureStrings.dispatchHub(L10n.shared.language).prefilledBrowserPrefix
            showPrefillHint("\(prefix)\(tab.browserName)")
        case .failure(let err):
            browserErrorCaption = err.localizedDescription
        }
    }

    private func showPrefillHint(_ text: String) {
        prefillClearTask?.cancel()
        prefillCaption = text
        prefillClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.prefillCaption = ""
        }
    }

    // MARK: - Submit

    func submitCurrent() {
        guard !isSubmitting else { return }
        guard let url = parsedURL else { return }
        let target = effectiveTarget
        guard DispatchHubSettings.isConfigured(target) else {
            openSettings(focus: target)
            return
        }

        let cleanURL = url.absoluteString
        let cleanTitle = titleHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = noteInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let selectedMode = teamsMode
        Task {
            await performSubmit(target: target, url: cleanURL, title: cleanTitle, note: cleanNote, teamsMode: selectedMode)
        }
    }

    func dispatchClipboardSilently() {
        guard let urlText = clipboardPrefill.readCurrentURL(),
              let url = DispatchRouter.parseURL(urlText) else {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: "剪贴板中没有有效链接")
            return
        }
        let target = DispatchRouter.route(for: url).target
        guard DispatchHubSettings.isConfigured(target) else {
            DispatchHubService.shared.show()
            openSettings(focus: target)
            return
        }
        let targetName = target == .shizhi ? "拾知" : "Teams 回复助手"
        QuickToolHUD.show(icon: "paperplane.fill", message: "已发送到\(targetName)")
        Task {
            await performSubmit(target: target, url: url.absoluteString, title: "", note: "")
        }
    }

    private func clearInputsAfterSubmit() {
        urlInput = ""
        titleHint = ""
        noteInput = ""
        manualTarget = nil
        browserErrorCaption = ""
        submitJustSucceeded = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.submitJustSucceeded = false
        }
    }

    private func performSubmit(
        target: DispatchTargetID,
        url: String,
        title: String,
        note: String,
        teamsMode: TeamsTriageMode = .summary
    ) async {
        isSubmitting = true
        banner = nil
        defer { isSubmitting = false }

        do {
            switch target {
            case .shizhi:
                let resp = try await ShizhiClient.collect(url: url, title: title)
                shizhiConnection = .connected
                upsertShizhiItem(resp.item)
                let id = "shizhi:\(resp.item.id)"
                selectedItemID = id
                expandedItemID = id
                clearInputsAfterSubmit()
                restartPollingIfNeeded(resetInterval: true)
            case .teams:
                let card = try await TeamsTriageClient.analyze(url: url, note: note, mode: teamsMode)
                teamsConnection = .connected
                upsertTeamsCard(card)
                let id = "teams:\(card.id)"
                selectedItemID = id
                expandedItemID = id
                clearInputsAfterSubmit()
            }
        } catch let err as DispatchError {
            handleError(err, target: target)
            // Keep a local failed card so the user's input is never lost
            let failed = LocalFailedDispatch(
                id: UUID().uuidString,
                target: target,
                url: url,
                title: title,
                note: note,
                errorMessage: err.localizedDescription,
                createdAt: Date()
            )
            failedItems.insert(failed, at: 0)
            let id = "failed:\(failed.id)"
            selectedItemID = id
            expandedItemID = id
        } catch {
            banner = DispatchBannerState(target: target, isUnauthorized: false, message: error.localizedDescription)
        }
    }

    func retryFailed(_ item: LocalFailedDispatch) {
        failedItems.removeAll { $0.id == item.id }
        Task {
            await performSubmit(target: item.target, url: item.url, title: item.title, note: item.note)
        }
    }

    func removeFailed(_ id: String) {
        failedItems.removeAll { $0.id == id }
    }

    // MARK: - Shizhi Sync & Polling

    func syncShizhiRecent(silent: Bool = false) async {
        guard DispatchHubSettings.isConfigured(.shizhi) else {
            shizhiConnection = .unconfigured
            return
        }
        do {
            let recent = try await ShizhiClient.fetchRecent(limit: 20)
            shizhiConnection = .connected
            // Merge server recent items with local list, preserving order by updatedAt
            var byID = Dictionary(uniqueKeysWithValues: shizhiItems.map { ($0.id, $0) })
            for item in recent {
                byID[item.id] = item
            }
            shizhiItems = Array(byID.values)
                .sorted {
                    (DispatchDateParser.parse($0.updatedAt) ?? .distantPast)
                        > (DispatchDateParser.parse($1.updatedAt) ?? .distantPast)
                }
            DispatchHubSettings.saveShizhiItems(shizhiItems)
            restartPollingIfNeeded(resetInterval: false)
        } catch let err as DispatchError {
            if !silent {
                handleError(err, target: .shizhi)
            } else {
                updateConnectionState(for: .shizhi, error: err)
            }
        } catch {
            if !silent {
                banner = DispatchBannerState(target: .shizhi, isUnauthorized: false, message: error.localizedDescription)
            }
        }
    }

    func retryShizhiItem(_ item: ShizhiItemPayload) {
        Task {
            do {
                let updated = try await ShizhiClient.retryItem(id: item.id)
                shizhiConnection = .connected
                upsertShizhiItem(updated)
                restartPollingIfNeeded(resetInterval: true)
            } catch let err as DispatchError {
                handleError(err, target: .shizhi)
            } catch {
                banner = DispatchBannerState(target: .shizhi, isUnauthorized: false, message: error.localizedDescription)
            }
        }
    }

    func removeShizhiItem(_ id: String) {
        shizhiItems.removeAll { $0.id == id }
        DispatchHubSettings.saveShizhiItems(shizhiItems)
    }

    private func upsertShizhiItem(_ item: ShizhiItemPayload) {
        if let idx = shizhiItems.firstIndex(where: { $0.id == item.id }) {
            shizhiItems[idx] = item
        } else {
            shizhiItems.insert(item, at: 0)
        }
        DispatchHubSettings.saveShizhiItems(shizhiItems)
    }

    private func restartPollingIfNeeded(resetInterval: Bool) {
        let hasActive = shizhiItems.contains { $0.isActive }
        guard hasActive, DispatchHubSettings.isConfigured(.shizhi) else {
            stopAllPolling()
            return
        }
        if pollTask != nil && !resetInterval { return }
        pollTask?.cancel()
        consecutivePollErrors = 0
        pollTask = Task { [weak self] in
            var delay: Double = 1.5
            while !Task.isCancelled {
                guard let self else { break }
                let sleepSec = self.isPanelVisible ? delay : 15.0
                try? await Task.sleep(nanoseconds: UInt64(sleepSec * 1_000_000_000))
                if Task.isCancelled { break }
                let activeIDs = self.shizhiItems.filter { $0.isActive }.map { $0.id }
                if activeIDs.isEmpty { break }

                var hadError = false
                for uid in activeIDs {
                    if Task.isCancelled { break }
                    do {
                        let fresh = try await ShizhiClient.fetchItem(id: uid)
                        self.shizhiConnection = .connected
                        self.upsertShizhiItem(fresh)
                    } catch {
                        hadError = true
                    }
                }
                if hadError {
                    self.consecutivePollErrors += 1
                    if self.consecutivePollErrors >= 5 {
                        self.shizhiConnection = .unreachable("轮询连接中断，点击重试")
                        break
                    }
                } else {
                    self.consecutivePollErrors = 0
                }
                delay = min(8.0, delay * 1.5)
            }
            self?.pollTask = nil
        }
    }

    // MARK: - Teams Operations

    func syncTeams(silent: Bool = false) async {
        guard DispatchHubSettings.isConfigured(.teams) else {
            teamsConnection = .unconfigured
            return
        }
        isSyncingTeams = true
        defer { isSyncingTeams = false }
        do {
            let resp = try await TeamsTriageClient.list()
            teamsConnection = .connected
            teamsCards = resp.cards
            if DispatchHubSettings.teamsMe.isEmpty, let serverMe = resp.me, !serverMe.isEmpty {
                DispatchHubSettings.teamsMe = serverMe
            }
        } catch let err as DispatchError {
            if !silent {
                handleError(err, target: .teams)
            } else {
                updateConnectionState(for: .teams, error: err)
            }
        } catch {
            if !silent {
                banner = DispatchBannerState(target: .teams, isUnauthorized: false, message: error.localizedDescription)
            }
        }
    }

    func refreshTeamsCard(_ cardID: String, note: String = "") async {
        let key = "teams:\(cardID)"
        busyCardIDs.insert(key)
        cardErrors[key] = nil
        defer { busyCardIDs.remove(key) }
        do {
            let updated = try await TeamsTriageClient.refresh(id: cardID, note: note)
            teamsConnection = .connected
            upsertTeamsCard(updated)
        } catch {
            cardErrors[key] = "刷新失败：\(error.localizedDescription)"
        }
    }

    func refineTeamsCard(_ cardID: String, note: String) async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = "teams:\(cardID)"
        busyCardIDs.insert(key)
        cardErrors[key] = nil
        defer { busyCardIDs.remove(key) }
        do {
            let updated = try await TeamsTriageClient.refine(id: cardID, note: trimmed)
            teamsConnection = .connected
            upsertTeamsCard(updated)
        } catch {
            cardErrors[key] = "重新生成失败：\(error.localizedDescription)"
        }
    }

    func toggleTeamsStatus(_ card: TeamsTriageCard) async {
        let key = "teams:\(card.id)"
        busyCardIDs.insert(key)
        cardErrors[key] = nil
        defer { busyCardIDs.remove(key) }
        let nextStatus = card.isDone ? "open" : "done"
        do {
            let updated = try await TeamsTriageClient.setStatus(id: card.id, status: nextStatus)
            teamsConnection = .connected
            upsertTeamsCard(updated)
        } catch {
            cardErrors[key] = "更新状态失败：\(error.localizedDescription)"
        }
    }

    func deleteTeamsCard(_ cardID: String) async {
        let key = "teams:\(cardID)"
        busyCardIDs.insert(key)
        cardErrors[key] = nil
        defer { busyCardIDs.remove(key) }
        do {
            try await TeamsTriageClient.delete(id: cardID)
            teamsCards.removeAll { $0.id == cardID }
            if expandedItemID == key { expandedItemID = nil }
            if selectedItemID == key { selectedItemID = nil }
        } catch {
            cardErrors[key] = "删除失败：\(error.localizedDescription)"
        }
    }

    private func upsertTeamsCard(_ card: TeamsTriageCard) {
        teamsCards.removeAll {
            $0.id == card.id || (!card.conversationId.isEmpty && $0.conversationId == card.conversationId)
        }
        teamsCards.insert(card, at: 0)
    }

    // MARK: - List Helpers & Keyboard Navigation

    func clearDoneItems() {
        shizhiItems.removeAll { $0.isDone }
        DispatchHubSettings.saveShizhiItems(shizhiItems)
        failedItems.removeAll()
    }

    func toggleExpand(_ id: String) {
        selectedItemID = id
        expandedItemID = (expandedItemID == id) ? nil : id
    }

    func moveSelection(delta: Int) {
        let list = filteredItems
        guard !list.isEmpty else { return }
        if let current = selectedItemID, let idx = list.firstIndex(where: { $0.id == current }) {
            let next = max(0, min(list.count - 1, idx + delta))
            selectedItemID = list[next].id
        } else {
            selectedItemID = delta >= 0 ? list.first?.id : list.last?.id
        }
    }

    func copySelectedPrimary() -> Bool {
        guard let id = selectedItemID,
              let item = filteredItems.first(where: { $0.id == id }),
              let text = item.primaryCopyText else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        QuickToolHUD.show(icon: "doc.on.doc", message: FeatureStrings.dispatchHub(L10n.shared.language).copied)
        return true
    }

    func openSelectedURL() -> Bool {
        guard let id = selectedItemID,
              let item = filteredItems.first(where: { $0.id == id }),
              let url = item.openableURL else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    func openSettings(focus: DispatchTargetID? = nil) {
        settingsFocusTarget = focus
        showSettings = true
    }

    // MARK: - Error Mapping

    private func updateConnectionState(for target: DispatchTargetID, error: DispatchError) {
        let state: DispatchConnectionState
        switch error {
        case .unconfigured:
            state = .unconfigured
        case .unreachable(let msg), .invalidBaseURL(let msg):
            state = .unreachable(msg)
        case .unauthorized:
            state = .unreachable("Token 无效")
        case .server, .decoding:
            state = .connected
        }
        if target == .shizhi {
            shizhiConnection = state
        } else {
            teamsConnection = state
        }
    }

    private func handleError(_ error: DispatchError, target: DispatchTargetID) {
        updateConnectionState(for: target, error: error)
        switch error {
        case .unauthorized:
            banner = DispatchBannerState(target: target, isUnauthorized: true, message: error.localizedDescription)
        default:
            banner = DispatchBannerState(target: target, isUnauthorized: false, message: error.localizedDescription)
        }
    }
}
