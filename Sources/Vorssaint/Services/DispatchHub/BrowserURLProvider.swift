// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

struct BrowserTabInfo {
    let browserName: String
    let url: String
    let title: String
}

enum BrowserURLError: LocalizedError {
    case noBrowser
    case permissionDenied(String)
    case emptyTab(String)

    var errorDescription: String? {
        switch self {
        case .noBrowser:
            return "未检测到支持读取标签页的前台浏览器"
        case .permissionDenied(let app):
            return "需要在 系统设置 › 隐私与安全性 › 自动化 中允许 Vorssaint 控制 \(app)"
        case .emptyTab(let app):
            return "未能从 \(app) 读取到有效网页链接"
        }
    }
}

enum BrowserURLProvider {
    private struct BrowserSpec {
        let bundleID: String
        let displayName: String
        let script: String
    }

    private static let specs: [BrowserSpec] = [
        BrowserSpec(
            bundleID: "com.apple.Safari",
            displayName: "Safari",
            script: #"tell application "Safari" to if (count of windows) > 0 then return (URL of current tab of front window) & linefeed & (name of current tab of front window)"#
        ),
        BrowserSpec(
            bundleID: "com.google.Chrome",
            displayName: "Google Chrome",
            script: #"tell application "Google Chrome" to if (count of windows) > 0 then return (URL of active tab of front window) & linefeed & (title of active tab of front window)"#
        ),
        BrowserSpec(
            bundleID: "company.thebrowser.Browser",
            displayName: "Arc",
            script: #"tell application "Arc" to if (count of windows) > 0 then return (URL of active tab of front window) & linefeed & (title of active tab of front window)"#
        ),
        BrowserSpec(
            bundleID: "com.microsoft.edgemac",
            displayName: "Microsoft Edge",
            script: #"tell application "Microsoft Edge" to if (count of windows) > 0 then return (URL of active tab of front window) & linefeed & (title of active tab of front window)"#
        ),
        BrowserSpec(
            bundleID: "com.brave.Browser",
            displayName: "Brave Browser",
            script: #"tell application "Brave Browser" to if (count of windows) > 0 then return (URL of active tab of front window) & linefeed & (title of active tab of front window)"#
        ),
    ]

    /// Grabs the active tab URL from the previously active browser (or any running supported browser).
    static func fetchFrontBrowserTab(preferredBundleID: String? = nil) -> Result<BrowserTabInfo, BrowserURLError> {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let ordered: [BrowserSpec]
        if let preferred = preferredBundleID, let matched = specs.first(where: { $0.bundleID == preferred }) {
            ordered = [matched]
        } else {
            ordered = specs.filter { running.contains($0.bundleID) }
        }
        guard !ordered.isEmpty else { return .failure(.noBrowser) }

        var lastError: BrowserURLError = .noBrowser
        for spec in ordered {
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: spec.script) else { continue }
            let output = script.executeAndReturnError(&errorInfo)
            if let err = errorInfo {
                let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -1743 {
                    return .failure(.permissionDenied(spec.displayName))
                }
                lastError = .emptyTab(spec.displayName)
                continue
            }
            let raw = output.stringValue ?? ""
            let parts = raw.components(separatedBy: .newlines)
            let urlText = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let titleText = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if let valid = DispatchRouter.parseURL(urlText) {
                return .success(BrowserTabInfo(
                    browserName: spec.displayName,
                    url: valid.absoluteString,
                    title: titleText
                ))
            }
            lastError = .emptyTab(spec.displayName)
        }
        return .failure(lastError)
    }
}
