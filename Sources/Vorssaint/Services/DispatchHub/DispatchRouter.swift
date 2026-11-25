// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DispatchMatch: Equatable {
    let target: DispatchTargetID
    let score: Int
    let reason: String
}

protocol DispatchRouteHandler {
    var target: DispatchTargetID { get }
    var symbol: String { get }
    func match(_ url: URL) -> DispatchMatch?
}

struct TeamsRouteHandler: DispatchRouteHandler {
    let target: DispatchTargetID = .teams
    let symbol = "bubble.left.and.text.bubble.right"

    func match(_ url: URL) -> DispatchMatch? {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "msteams" {
            return DispatchMatch(target: .teams, score: 100, reason: "msteams:// 协议")
        }
        guard scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return nil
        }
        if host == "teams.microsoft.com"
            || host == "teams.live.com"
            || host == "teams.cloud.microsoft"
            || host.hasSuffix(".teams.microsoft.us")
            || host.hasSuffix(".teams.microsoft.com") {
            return DispatchMatch(target: .teams, score: 100, reason: host)
        }
        return nil
    }
}

struct ShizhiRouteHandler: DispatchRouteHandler {
    let target: DispatchTargetID = .shizhi
    let symbol = "books.vertical"

    func match(_ url: URL) -> DispatchMatch? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard (scheme == "http" || scheme == "https"), let host = url.host?.lowercased() else {
            return nil
        }
        return DispatchMatch(target: .shizhi, score: 10, reason: host)
    }
}

enum DispatchRouter {
    static let handlers: [DispatchRouteHandler] = [
        TeamsRouteHandler(),
        ShizhiRouteHandler(),
    ]

    static func parseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = URL(string: trimmed), isSupportedScheme(direct) {
            return direct
        }
        return extractFirstURL(from: trimmed)
    }

    static func extractFirstURL(from text: String) -> URL? {
        let pattern = #"(?:https?|msteams)://[^\s<>\"'\]\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        let candidate = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?。，；！？"))
        guard let url = URL(string: candidate), isSupportedScheme(url) else { return nil }
        return url
    }

    static func isSupportedScheme(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "msteams" { return true }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    static func route(for url: URL) -> DispatchMatch {
        let best = handlers
            .compactMap { $0.match(url) }
            .max { $0.score < $1.score }
        return best ?? DispatchMatch(target: .shizhi, score: 0, reason: url.host ?? "默认")
    }
}
