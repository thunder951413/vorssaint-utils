// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DispatchTargetID: String, Codable, CaseIterable, Identifiable {
    case shizhi
    case teams

    var id: String { rawValue }
}

enum DispatchFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case pendingReply
    case done

    var id: String { rawValue }
}

enum DispatchConnectionState: Equatable {
    case unknown
    case unconfigured
    case connected
    case unreachable(String)
}

struct DispatchBannerState: Identifiable, Equatable {
    let id = UUID()
    let target: DispatchTargetID?
    let isUnauthorized: Bool
    let message: String
}

// MARK: - Shizhi Models

struct ShizhiItemPayload: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var source: String
    var kind: String
    var status: String
    var progress: Double
    var message: String
    var error: String
    var archived: Bool
    var url: String
    var segmentCount: Int
    var hasNote: Bool
    var summary: String
    var keyPoints: [String]
    var tags: [String]
    var createdAt: String
    var updatedAt: String
    var openURL: String

    enum CodingKeys: String, CodingKey {
        case id, title, source, kind, status, progress, message, error, archived, url
        case segmentCount = "segment_count"
        case hasNote = "has_note"
        case summary
        case keyPoints = "key_points"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case openURL = "open_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "等待获取标题"
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "网页"
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "article"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "queued"
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        error = try c.decodeIfPresent(String.self, forKey: .error) ?? ""
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        segmentCount = try c.decodeIfPresent(Int.self, forKey: .segmentCount) ?? 0
        hasNote = try c.decodeIfPresent(Bool.self, forKey: .hasNote) ?? false
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        openURL = try c.decodeIfPresent(String.self, forKey: .openURL) ?? ""
    }

    var isActive: Bool {
        ["queued", "downloading", "extracting", "transcribing", "organizing"].contains(status)
    }

    var isDone: Bool {
        status == "ready" || archived
    }

    var stageIndex: Int {
        switch status {
        case "queued": return 0
        case "downloading": return 1
        case "extracting": return 2
        case "transcribing": return 3
        case "organizing": return 4
        case "ready": return 5
        default: return 0
        }
    }

    var stageLabel: String {
        switch status {
        case "queued": return "排队"
        case "downloading": return "下载"
        case "extracting": return "提取"
        case "transcribing": return "转写"
        case "organizing": return "AI 整理"
        case "awaiting_ai": return "待 AI"
        case "ready": return "已整理"
        case "failed": return "失败"
        case "cancelled": return "已停止"
        default: return status
        }
    }

    var markdownSummary: String {
        var lines: [String] = []
        if !title.isEmpty { lines.append("# \(title)") }
        if !summary.isEmpty { lines.append(summary) }
        if !keyPoints.isEmpty {
            lines.append("")
            for pt in keyPoints {
                lines.append("- \(pt)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct ShizhiCollectResponse: Codable {
    let ok: Bool
    let created: Bool
    let item: ShizhiItemPayload
    let openURL: String

    enum CodingKeys: String, CodingKey {
        case ok, created, item
        case openURL = "open_url"
    }
}

struct ShizhiRecentResponse: Codable {
    let items: [ShizhiItemPayload]
}

// MARK: - Teams Triage Models

enum TeamsTriageMode: String, Codable, CaseIterable, Identifiable {
    case summary
    case triage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary: return "对话总结"
        case .triage: return "回复助手"
        }
    }
}

enum TeamsTriageVerdict: String, Codable {
    case replyReady = "reply_ready"
    case needInfo = "need_info"
    case needAction = "need_action"
    case noAction = "no_action"

    var label: String {
        switch self {
        case .replyReady: return "可直接回复"
        case .needInfo: return "需补充信息"
        case .needAction: return "需要行动"
        case .noAction: return "无需处理"
        }
    }
}

enum TeamsTriageUrgency: String, Codable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }

    var rank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

struct TeamsTriageSource: Codable, Equatable, Identifiable {
    let n: Int
    let id: String
    let title: String
    let url: String?
    let sourceType: String
}

struct TeamsTriageCard: Codable, Equatable, Identifiable {
    let id: String
    var mode: TeamsTriageMode
    var status: String // "open" | "done"
    var conversationId: String
    var url: String
    var title: String
    var who: String
    var summary: String
    var keyPoints: [String]
    var urgency: TeamsTriageUrgency
    var verdict: TeamsTriageVerdict
    var action: String
    var missingInfo: [String]
    var suggestedReply: String
    var hasMediaWarning: Bool
    var note: String?
    var sources: [TeamsTriageSource]
    var messageCount: Int
    var latestMessageAt: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, mode, status, conversationId, url, title, who, summary, keyPoints, urgency, verdict, action
        case missingInfo, suggestedReply, hasMediaWarning, note, sources, messageCount
        case latestMessageAt, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        mode = try c.decodeIfPresent(TeamsTriageMode.self, forKey: .mode) ?? .triage
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Teams 会话"
        who = try c.decodeIfPresent(String.self, forKey: .who) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        urgency = try c.decodeIfPresent(TeamsTriageUrgency.self, forKey: .urgency) ?? .medium
        verdict = try c.decodeIfPresent(TeamsTriageVerdict.self, forKey: .verdict) ?? .needAction
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        missingInfo = try c.decodeIfPresent([String].self, forKey: .missingInfo) ?? []
        suggestedReply = try c.decodeIfPresent(String.self, forKey: .suggestedReply) ?? ""
        hasMediaWarning = try c.decodeIfPresent(Bool.self, forKey: .hasMediaWarning) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
        sources = try c.decodeIfPresent([TeamsTriageSource].self, forKey: .sources) ?? []
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        latestMessageAt = try c.decodeIfPresent(String.self, forKey: .latestMessageAt) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    var isDone: Bool { status == "done" }
    var isSummaryMode: Bool { mode == .summary }

    var needsReply: Bool {
        !isDone && !isSummaryMode && verdict != .noAction
    }

    var markdownSummary: String {
        var lines: [String] = []
        if !title.isEmpty { lines.append("# \(title)") }
        if !summary.isEmpty { lines.append(summary) }
        if !keyPoints.isEmpty {
            lines.append("")
            for pt in keyPoints {
                lines.append("- \(pt)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct TeamsTriageListResponse: Codable {
    let me: String?
    let cards: [TeamsTriageCard]
}

struct TeamsTriageCardResponse: Codable {
    let card: TeamsTriageCard
}

// MARK: - Unified Dispatch Item

struct LocalFailedDispatch: Codable, Equatable, Identifiable {
    let id: String
    let target: DispatchTargetID
    let url: String
    let title: String
    let note: String
    let errorMessage: String
    let createdAt: Date
}

enum DispatchItem: Equatable, Identifiable {
    case shizhi(ShizhiItemPayload)
    case teams(TeamsTriageCard)
    case failed(LocalFailedDispatch)

    var id: String {
        switch self {
        case .shizhi(let item): return "shizhi:\(item.id)"
        case .teams(let card): return "teams:\(card.id)"
        case .failed(let f): return "failed:\(f.id)"
        }
    }

    var target: DispatchTargetID {
        switch self {
        case .shizhi: return .shizhi
        case .teams: return .teams
        case .failed(let f): return f.target
        }
    }

    var urlString: String {
        switch self {
        case .shizhi(let item): return item.url
        case .teams(let card): return card.url
        case .failed(let f): return f.url
        }
    }

    var primaryCopyText: String? {
        switch self {
        case .shizhi(let item):
            let md = item.markdownSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            return md.isEmpty ? item.url : md
        case .teams(let card):
            if card.isSummaryMode {
                let md = card.markdownSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                return md.isEmpty ? card.url : md
            }
            let reply = card.suggestedReply.trimmingCharacters(in: .whitespacesAndNewlines)
            return reply.isEmpty ? card.summary : reply
        case .failed(let f):
            return f.url
        }
    }

    var openableURL: URL? {
        switch self {
        case .shizhi(let item):
            return URL(string: item.openURL.isEmpty ? item.url : item.openURL)
        case .teams(let card):
            return URL(string: card.url)
        case .failed(let f):
            return URL(string: f.url)
        }
    }

    var isActive: Bool {
        switch self {
        case .shizhi(let item): return item.isActive
        case .teams, .failed: return false
        }
    }

    var isPendingReply: Bool {
        switch self {
        case .teams(let card): return card.needsReply
        case .shizhi, .failed: return false
        }
    }

    var isDone: Bool {
        switch self {
        case .shizhi(let item): return item.isDone
        case .teams(let card): return card.isDone
        case .failed: return false
        }
    }

    var sortTimestamp: Date {
        switch self {
        case .shizhi(let item):
            return DispatchDateParser.parse(item.updatedAt)
                ?? DispatchDateParser.parse(item.createdAt)
                ?? .distantPast
        case .teams(let card):
            return DispatchDateParser.parse(card.latestMessageAt)
                ?? DispatchDateParser.parse(card.updatedAt)
                ?? .distantPast
        case .failed(let f):
            return f.createdAt
        }
    }

    /// Sorting priority: active > failed > open teams (urgency) > shizhi ready > done
    var sortBucket: Int {
        switch self {
        case .shizhi(let item):
            if item.isActive { return 0 }
            if item.status == "failed" { return 1 }
            return item.isDone ? 4 : 3
        case .failed:
            return 1
        case .teams(let card):
            return card.isDone ? 5 : 2
        }
    }
}

enum DispatchDateParser {
    private static let isoWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        return isoWithFrac.date(from: raw) ?? isoPlain.date(from: raw)
    }

    static func relativeString(from raw: String, now: Date = Date()) -> String {
        guard let date = parse(raw) else { return "" }
        return relativeString(from: date, now: now)
    }

    static func relativeString(from date: Date, now: Date = Date()) -> String {
        let sec = Int(now.timeIntervalSince(date))
        if sec < 60 { return "刚刚" }
        if sec < 3600 { return "\(sec / 60) 分钟前" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return "今天 \(fmt.string(from: date))"
        }
        if cal.isDateInYesterday(date) {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return "昨天 \(fmt.string(from: date))"
        }
        let days = max(1, sec / 86400)
        if days <= 7 { return "\(days) 天前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: date)
    }
}
