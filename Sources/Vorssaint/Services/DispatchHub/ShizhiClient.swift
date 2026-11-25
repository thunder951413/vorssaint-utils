// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShizhiClient {
    private struct InfoResponse: Decodable {
        let token: String
    }

    private struct CollectBody: Encodable {
        let url: String
        let title: String
    }

    private static func headers(token: String) -> [String: String] {
        token.isEmpty ? [:] : ["X-Shizhi-Token": token]
    }

    /// If Shizhi is running locally and no token has been saved yet, fetch it once from /api/clipper/info.
    private static func resolveToken(baseURL: String, explicitToken: String? = nil) async throws -> String {
        let candidate = (explicitToken ?? DispatchHubSettings.token(for: .shizhi))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty { return candidate }
        let info: InfoResponse = try await DispatchHTTP.request(
            target: .shizhi,
            baseURL: baseURL,
            path: "/api/clipper/info",
            method: "GET"
        )
        let fetched = info.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fetched.isEmpty && explicitToken == nil {
            DispatchHubSettings.setToken(fetched, for: .shizhi)
        }
        return fetched
    }

    static func collect(url: String, title: String = "") async throws -> ShizhiCollectResponse {
        guard DispatchHubSettings.isConfigured(.shizhi) else {
            throw DispatchError.unconfigured(.shizhi)
        }
        let baseURL = DispatchHubSettings.shizhiURL
        let token = try await resolveToken(baseURL: baseURL)
        let body = try JSONEncoder().encode(CollectBody(url: url, title: title))
        return try await DispatchHTTP.request(
            target: .shizhi,
            baseURL: baseURL,
            path: "/api/clipper/collect",
            method: "POST",
            headers: headers(token: token),
            body: body
        )
    }

    static func fetchItem(id: String) async throws -> ShizhiItemPayload {
        guard DispatchHubSettings.isConfigured(.shizhi) else {
            throw DispatchError.unconfigured(.shizhi)
        }
        let baseURL = DispatchHubSettings.shizhiURL
        let token = try await resolveToken(baseURL: baseURL)
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await DispatchHTTP.request(
            target: .shizhi,
            baseURL: baseURL,
            path: "/api/clipper/items/\(encodedID)",
            method: "GET",
            headers: headers(token: token)
        )
    }

    static func retryItem(id: String) async throws -> ShizhiItemPayload {
        guard DispatchHubSettings.isConfigured(.shizhi) else {
            throw DispatchError.unconfigured(.shizhi)
        }
        let baseURL = DispatchHubSettings.shizhiURL
        let token = try await resolveToken(baseURL: baseURL)
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await DispatchHTTP.request(
            target: .shizhi,
            baseURL: baseURL,
            path: "/api/clipper/items/\(encodedID)/retry",
            method: "POST",
            headers: headers(token: token),
            body: Data("{}".utf8)
        )
    }

    static func fetchRecent(limit: Int = 15) async throws -> [ShizhiItemPayload] {
        guard DispatchHubSettings.isConfigured(.shizhi) else {
            throw DispatchError.unconfigured(.shizhi)
        }
        let baseURL = DispatchHubSettings.shizhiURL
        let token = try await resolveToken(baseURL: baseURL)
        let resp: ShizhiRecentResponse = try await DispatchHTTP.request(
            target: .shizhi,
            baseURL: baseURL,
            path: "/api/clipper/recent?limit=\(max(1, min(50, limit)))",
            method: "GET",
            headers: headers(token: token)
        )
        return resp.items
    }

    static func testConnection(baseURL: String, token: String) async throws -> (latencyMs: Int, resolvedToken: String) {
        let start = CFAbsoluteTimeGetCurrent()
        let effectiveToken = try await resolveToken(
            baseURL: baseURL,
            explicitToken: token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : token
        )
        let _: ShizhiRecentResponse = try await DispatchHTTP.request(
            target: .shizhi,
            baseURL: baseURL,
            path: "/api/clipper/recent?limit=1",
            method: "GET",
            headers: headers(token: effectiveToken)
        )
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        return (ms, effectiveToken)
    }
}
