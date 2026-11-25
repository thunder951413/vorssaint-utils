// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for Dispatch Hub, the unified capture & reply floating panel.
struct DispatchHubFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let quickCollectClipboardTitle: String
    let urlPlaceholder: String
    let notePlaceholder: String
    let pasteButton: String
    let browserURLButton: String
    let routeLabel: String
    let routeAuto: String
    let routeResetAuto: String
    let sendButton: String
    let sendingButton: String
    let configureServicePrefix: String
    let prefilledClipboard: String
    let prefilledBrowserPrefix: String
    let invalidURLHint: String
    let filterAll: String
    let filterActive: String
    let filterPendingReply: String
    let filterDone: String
    let syncTeams: String
    let clearDone: String
    let emptyUnconfiguredTitle: String
    let emptyUnconfiguredAction: String
    let emptyConfiguredTitle: String
    let emptyFilteredTitle: String
    let shizhiName: String
    let teamsName: String
    let statusConnected: String
    let statusUnconfigured: String
    let statusUnreachable: String
    let settingsTitle: String
    let enableLabel: String
    let serviceURLLabel: String
    let tokenLabel: String
    let tokenOptionalPlaceholder: String
    let teamsMeLabel: String
    let teamsMePlaceholder: String
    let testConnection: String
    let testingConnection: String
    let behaviorSection: String
    let autoPrefillClipboard: String
    let closeOnClickOutside: String
    let shortcutLabel: String
    let summarySection: String
    let keyPointsSection: String
    let missingInfoSection: String
    let suggestedReplySection: String
    let noSuggestedReply: String
    let copySummary: String
    let copyReply: String
    let copied: String
    let openInShizhi: String
    let openOriginalURL: String
    let refreshAction: String
    let markDone: String
    let reopenAction: String
    let deleteAction: String
    let retryAction: String
    let removeFromList: String
    let refinePlaceholder: String
    let refineButton: String
    let mediaWarning: String
    let sourcesTitlePrefix: String
    let openSettingsAction: String
    let pinTooltip: String
    let unpinTooltip: String
    let closeTooltip: String
    let settingsTooltip: String
    let deleteConfirmTitle: String
    let deleteConfirmMessage: String
    let cancel: String
    let expandMore: String
    let collapse: String
}

extension FeatureStrings {
    static func dispatchHub(_ language: AppLanguage) -> DispatchHubFeatureStrings {
        switch language {
        case .zhHans, .zhTW, .zhHK:
            return .zhHans
        default:
            return .enUS
        }
    }
}

private extension DispatchHubFeatureStrings {
    static let zhHans = DispatchHubFeatureStrings(
        pageTitle: "智能采集与回复",
        hubDescription: "统一浮窗：粘贴或读取链接，自动识别路由到拾知或 Teams 找我分析，原地查看进度、摘要与回复草稿。",
        panelCaption: "统一采集链接、查看整理摘要与 Teams 回复草稿",
        openButton: "打开智能采集与回复",
        quickCollectClipboardTitle: "采集剪贴板链接",
        urlPlaceholder: "粘贴网页、视频或 Teams 链接…",
        notePlaceholder: "备注 / 补充上下文（可选，一句话）",
        pasteButton: "粘贴",
        browserURLButton: "获取前台浏览器链接",
        routeLabel: "路由",
        routeAuto: "自动",
        routeResetAuto: "恢复自动",
        sendButton: "发送",
        sendingButton: "发送中…",
        configureServicePrefix: "去配置",
        prefilledClipboard: "已从剪贴板填入",
        prefilledBrowserPrefix: "已获取当前标签页：",
        invalidURLHint: "请输入有效的 http(s) 或 msteams:// 链接",
        filterAll: "全部",
        filterActive: "进行中",
        filterPendingReply: "待回复",
        filterDone: "已完成",
        syncTeams: "同步 Teams",
        clearDone: "清除已完成",
        emptyUnconfiguredTitle: "复制一个链接，呼出面板即可自动识别并分发处理",
        emptyUnconfiguredAction: "配置服务",
        emptyConfiguredTitle: "粘贴链接开始采集；Teams 链接会自动生成待办与回复草稿",
        emptyFilteredTitle: "此分类暂无内容",
        shizhiName: "拾知",
        teamsName: "Teams 回复助手",
        statusConnected: "已连接",
        statusUnconfigured: "未配置",
        statusUnreachable: "不可达",
        settingsTitle: "服务与行为设置",
        enableLabel: "启用",
        serviceURLLabel: "服务地址",
        tokenLabel: "安全令牌 (Token)",
        tokenOptionalPlaceholder: "可选，存在本机钥匙串中",
        teamsMeLabel: "我的名字 (me)",
        teamsMePlaceholder: "可选，用于识别谁在找你",
        testConnection: "测试连接",
        testingConnection: "测试中…",
        behaviorSection: "浮窗行为",
        autoPrefillClipboard: "唤起时自动读取剪贴板中的新链接",
        closeOnClickOutside: "点击面板外部自动隐藏（未钉住时）",
        shortcutLabel: "全局呼出快捷键",
        summarySection: "摘要",
        keyPointsSection: "核心要点",
        missingInfoSection: "还缺信息（点击填入下方补充框）",
        suggestedReplySection: "建议回复",
        noSuggestedReply: "暂无建议回复草稿",
        copySummary: "复制摘要",
        copyReply: "复制回复",
        copied: "已复制",
        openInShizhi: "在拾知打开",
        openOriginalURL: "打开原链接",
        refreshAction: "刷新",
        markDone: "标记已处理",
        reopenAction: "重新打开",
        deleteAction: "删除",
        retryAction: "重试",
        removeFromList: "移出列表",
        refinePlaceholder: "补充上下文后重新生成回复…",
        refineButton: "重新生成",
        mediaWarning: "原消息包含图片或附件，AI 未能直接读取，请结合原会话核对。",
        sourcesTitlePrefix: "参考依据",
        openSettingsAction: "打开设置",
        pinTooltip: "固定在最前（点击外部不隐藏）",
        unpinTooltip: "取消固定",
        closeTooltip: "关闭 (Esc)",
        settingsTooltip: "服务设置 (⌘,)",
        deleteConfirmTitle: "删除这条 Teams 卡片？",
        deleteConfirmMessage: "将从研发管家服务端移除该待办卡片，原 Teams 会话不受影响。",
        cancel: "取消",
        expandMore: "展开全部",
        collapse: "收起"
    )

    static let enUS = DispatchHubFeatureStrings(
        pageTitle: "Dispatch Hub",
        hubDescription: "Unified floating panel to route links to Shizhi or Teams Triage, track progress, and copy reply drafts.",
        panelCaption: "Route links, inspect summaries, and copy Teams reply drafts",
        openButton: "Open Dispatch Hub",
        quickCollectClipboardTitle: "Dispatch Clipboard Link",
        urlPlaceholder: "Paste webpage, video, or Teams link…",
        notePlaceholder: "Optional note or context (one line)",
        pasteButton: "Paste",
        browserURLButton: "Grab front browser URL",
        routeLabel: "Route",
        routeAuto: "Auto",
        routeResetAuto: "Auto",
        sendButton: "Send",
        sendingButton: "Sending…",
        configureServicePrefix: "Configure",
        prefilledClipboard: "Prefilled from clipboard",
        prefilledBrowserPrefix: "Grabbed tab from ",
        invalidURLHint: "Enter a valid http(s) or msteams:// URL",
        filterAll: "All",
        filterActive: "Active",
        filterPendingReply: "Needs Reply",
        filterDone: "Done",
        syncTeams: "Sync Teams",
        clearDone: "Clear Done",
        emptyUnconfiguredTitle: "Copy a link and summon Dispatch Hub to route and process it.",
        emptyUnconfiguredAction: "Configure Services",
        emptyConfiguredTitle: "Paste any link to collect; Teams links generate actionable reply drafts.",
        emptyFilteredTitle: "Nothing in this filter",
        shizhiName: "Shizhi",
        teamsName: "Teams Triage",
        statusConnected: "Connected",
        statusUnconfigured: "Not set",
        statusUnreachable: "Unreachable",
        settingsTitle: "Services & Behavior",
        enableLabel: "Enabled",
        serviceURLLabel: "Service URL",
        tokenLabel: "Token",
        tokenOptionalPlaceholder: "Optional, stored in Keychain",
        teamsMeLabel: "My Name (me)",
        teamsMePlaceholder: "Optional display name for triage",
        testConnection: "Test",
        testingConnection: "Testing…",
        behaviorSection: "Panel Behavior",
        autoPrefillClipboard: "Auto-prefill new clipboard link on open",
        closeOnClickOutside: "Hide on click outside (when unpinned)",
        shortcutLabel: "Global shortcut",
        summarySection: "Summary",
        keyPointsSection: "Key Points",
        missingInfoSection: "Missing Info (click to fill context)",
        suggestedReplySection: "Suggested Reply",
        noSuggestedReply: "No suggested reply yet",
        copySummary: "Copy Summary",
        copyReply: "Copy Reply",
        copied: "Copied",
        openInShizhi: "Open in Shizhi",
        openOriginalURL: "Open Link",
        refreshAction: "Refresh",
        markDone: "Mark Done",
        reopenAction: "Reopen",
        deleteAction: "Delete",
        retryAction: "Retry",
        removeFromList: "Remove",
        refinePlaceholder: "Add context to regenerate reply…",
        refineButton: "Regenerate",
        mediaWarning: "Original messages contain images or attachments not read by AI.",
        sourcesTitlePrefix: "Sources",
        openSettingsAction: "Open Settings",
        pinTooltip: "Pin panel on top",
        unpinTooltip: "Unpin panel",
        closeTooltip: "Close (Esc)",
        settingsTooltip: "Settings (⌘,)",
        deleteConfirmTitle: "Delete this Teams card?",
        deleteConfirmMessage: "This removes the triage card from the server. The Teams chat itself is untouched.",
        cancel: "Cancel",
        expandMore: "Show all",
        collapse: "Show less"
    )
}
