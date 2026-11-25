// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TeamsTriageClient {
    private struct AnalyzeBody: Encodable {
        let url: String
        let note: String?
        let me: String?
        let mode: String
    }

    private struct RefreshBody: Encodable {
        let note: String?
        let me: String?
        let mode: String?
    }

    private struct RefineBody: Encodable {
        let note: String
        let me: String?
        let mode: String?
    }

    private struct StatusBody: Encodable {
        let status: String
    }

    private struct DeleteResponse: Decodable {
        let deleted: Bool
    }

    private static func headers(token: String? = nil) -> [String: String] {
        var result: [String: String] = ["x-orchestrator-request": "1"]
        let raw = (token ?? DispatchHubSettings.token(for: .teams))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            result["x-steward-token"] = raw
        }
        return result
    }

    /// Supports base URLs with or without trailing `/orchestrator/api` or `/api`.
    private static func apiPath(_ baseURL: String, _ suffix: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/orchestrator/api") || trimmed.hasSuffix("/api") {
            return suffix
        }
        return "/orchestrator/api" + suffix
    }

    static func list() async throws -> TeamsTriageListResponse {
        guard DispatchHubSettings.isConfigured(.teams) else {
            throw DispatchError.unconfigured(.teams)
        }
        let baseURL = DispatchHubSettings.teamsURL
        return try await DispatchHTTP.request(
            target: .teams,
            baseURL: baseURL,
            path: apiPath(baseURL, "/library/teams-triage"),
            method: "GET",
            headers: headers()
        )
    }

    static func analyze(url: String, note: String = "", mode: TeamsTriageMode = .triage) async throws -> TeamsTriageCard {
        guard DispatchHubSettings.isConfigured(.teams) else {
            throw DispatchError.unconfigured(.teams)
        }
        let baseURL = DispatchHubSettings.teamsURL
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMe = DispatchHubSettings.teamsMe.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = try JSONEncoder().encode(AnalyzeBody(
            url: url,
            note: cleanNote.isEmpty ? nil : cleanNote,
            me: cleanMe.isEmpty ? nil : cleanMe,
            mode: mode.rawValue
        ))
        let resp: TeamsTriageCardResponse = try await DispatchHTTP.request(
            target: .teams,
            baseURL: baseURL,
            path: apiPath(baseURL, "/library/teams-triage/analyze"),
            method: "POST",
            headers: headers(),
            body: body,
            longTimeout: true
        )
        return resp.card
    }

    static func refresh(id: String, note: String = "", mode: TeamsTriageMode? = nil) async throws -> TeamsTriageCard {
        guard DispatchHubSettings.isConfigured(.teams) else {
            throw DispatchError.unconfigured(.teams)
        }
        let baseURL = DispatchHubSettings.teamsURL
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMe = DispatchHubSettings.teamsMe.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = try JSONEncoder().encode(RefreshBody(
            note: cleanNote.isEmpty ? nil : cleanNote,
            me: cleanMe.isEmpty ? nil : cleanMe,
            mode: mode?.rawValue
        ))
        let resp: TeamsTriageCardResponse = try await DispatchHTTP.request(
            target: .teams,
            baseURL: baseURL,
            path: apiPath(baseURL, "/library/teams-triage/\(id)/refresh"),
            method: "POST",
            headers: headers(),
            body: body,
            longTimeout: true
        )
        return resp.card
    }

    static func refine(id: String, note: String, mode: TeamsTriageMode? = nil) async throws -> TeamsTriageCard {
        guard DispatchHubSettings.isConfigured(.teams) else {
            throw DispatchError.unconfigured(.teams)
        }
        let baseURL = DispatchHubSettings.teamsURL
        let cleanMe = DispatchHubSettings.teamsMe.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = try JSONEncoder().encode(RefineBody(
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            me: cleanMe.isEmpty ? nil : cleanMe,
            mode: mode?.rawValue
        ))
        let resp: TeamsTriageCardResponse = try await DispatchHTTP.request(
            target: .teams,
            baseURL: baseURL,
            path: apiPath(baseURL, "/library/teams-triage/\(id)/refine"),
            method: "POST",
            headers: headers(),
            body: body,
            longTimeout: true
        )
        return resp.card
    }

    static func setStatus(id: String, status: String) async throws -> TeamsTriageCard {
        guard DispatchHubSettings.isConfigured(.teams) else {
            throw DispatchError.unconfigured(.teams)
        }
        let baseURL = DispatchHubSettings.teamsURL
        let body = try JSONEncoder().encode(StatusBody(status: status))
        let resp: TeamsTriageCardResponse = try await DispatchHTTP.request(
            target: .teams,
            baseURL: baseURL,
            path: apiPath(baseURL, "/library/teams-triage/\(id)/status"),
            method: "POST",
            headers: headers(),
            body: body
        )
        return resp.card
    }

    static func delete(id: String) async throws {
        guard DispatchHubSettings.isConfigured(.teams) else {
            throw DispatchError.unconfigured(.teams)
        }
        let baseURL = DispatchHubSettings.teamsURL
        let _: DeleteResponse = try await DispatchHTTP.request(
            target: .teams,
            baseURL: baseURL,
            path: apiPath(baseURL, "/library/teams-triage/\(id)/delete"),
            method: "POST",
            headers: headers(),
            body: Data("{}".utf8)
        )
    }

    static func testConnection(baseURL: String, token: String) async throws -> (latencyMs: Int, me: String?) {
        let start = CFAbsoluteTimeGetCurrent()
        let resp: TeamsTriageListResponse = try await DispatchHTTP.request(
            target: .teams,
            baseURL: baseURL,
            path: apiPath(baseURL, "/library/teams-triage"),
            method: "GET",
            headers: headers(token: token)
        )
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        return (ms, resp.me)
    }
}
