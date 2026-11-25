// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DispatchError: LocalizedError, Equatable {
    case unconfigured(DispatchTargetID)
    case invalidBaseURL(String)
    case unreachable(String)
    case unauthorized(DispatchTargetID)
    case server(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unconfigured(let target):
            return target == .shizhi ? "拾知服务未配置或已关闭" : "研发管家服务未配置或已关闭"
        case .invalidBaseURL(let url):
            return "服务地址无效：\(url)"
        case .unreachable(let msg):
            return msg
        case .unauthorized(let target):
            return target == .shizhi ? "拾知 Token 无效或缺失" : "研发管家 Token 无效或缺失"
        case .server(_, let msg):
            return msg
        case .decoding(let msg):
            return "响应解析失败：\(msg)"
        }
    }
}

enum DispatchHTTP {
    private static let fastSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private static let aiSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 90
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    static func normalizedBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            throw DispatchError.invalidBaseURL(raw)
        }
        return url
    }

    static func request<T: Decodable>(
        target: DispatchTargetID,
        baseURL: String,
        path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        longTimeout: Bool = false
    ) async throws -> T {
        let base = try normalizedBaseURL(baseURL)
        let fullString = base.absoluteString + (path.hasPrefix("/") ? path : "/\(path)")
        guard let url = URL(string: fullString) else {
            throw DispatchError.invalidBaseURL(fullString)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let session = longTimeout ? aiSession : fastSession
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let err as URLError {
            let host = base.host ?? baseURL
            if let port = base.port {
                throw DispatchError.unreachable("无法连接服务（\(host):\(port)）：\(err.localizedDescription)")
            }
            throw DispatchError.unreachable("无法连接服务（\(host)）：\(err.localizedDescription)")
        } catch {
            throw DispatchError.unreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DispatchError.unreachable("未收到有效的 HTTP 响应")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw DispatchError.unauthorized(target)
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = extractServerMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw DispatchError.server(http.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DispatchError.decoding(error.localizedDescription)
        }
    }

    private static func extractServerMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = obj["detail"] as? String, !detail.isEmpty { return detail }
            if let error = obj["error"] as? String, !error.isEmpty { return error }
            if let message = obj["message"] as? String, !message.isEmpty { return message }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? String(raw!.prefix(200)) : nil
    }
}
