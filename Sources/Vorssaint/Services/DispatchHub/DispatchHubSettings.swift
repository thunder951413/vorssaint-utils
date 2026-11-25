// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// Local settings and Keychain-backed token storage for Dispatch Hub.
/// Tokens are never stored in UserDefaults or exported in settings backups.
enum DispatchHubSettings {
    private static let keychainService = "com.vorssaint.dispatchhub"

    static var shizhiEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.dispatchHubShizhiEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.dispatchHubShizhiEnabled) }
    }

    static var shizhiURL: String {
        get { UserDefaults.standard.string(forKey: DefaultsKey.dispatchHubShizhiURL) ?? "http://127.0.0.1:8767" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.dispatchHubShizhiURL) }
    }

    static var teamsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.dispatchHubTeamsEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.dispatchHubTeamsEnabled) }
    }

    static var teamsURL: String {
        get { UserDefaults.standard.string(forKey: DefaultsKey.dispatchHubTeamsURL) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.dispatchHubTeamsURL) }
    }

    static var teamsMe: String {
        get { UserDefaults.standard.string(forKey: DefaultsKey.dispatchHubTeamsMe) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.dispatchHubTeamsMe) }
    }

    static var autoPrefillClipboard: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.dispatchHubAutoPrefill) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.dispatchHubAutoPrefill) }
    }

    static var closeOnClickOutside: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.dispatchHubCloseOnClickOutside) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.dispatchHubCloseOnClickOutside) }
    }

    static func isConfigured(_ target: DispatchTargetID) -> Bool {
        switch target {
        case .shizhi:
            return shizhiEnabled && !shizhiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .teams:
            return teamsEnabled && !teamsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Keychain Tokens

    static func token(for target: DispatchTargetID) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: target.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func setToken(_ value: String, for target: DispatchTargetID) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: target.rawValue,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Persisted Local Shizhi Items (capped at 50)

    static func loadShizhiItems() -> [ShizhiItemPayload] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.dispatchHubShizhiItems),
              let items = try? JSONDecoder().decode([ShizhiItemPayload].self, from: data) else {
            return []
        }
        return items
    }

    static func saveShizhiItems(_ items: [ShizhiItemPayload]) {
        let capped = Array(items.prefix(50))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.dispatchHubShizhiItems)
        }
    }

    // MARK: - Window Frame

    static func loadFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: DefaultsKey.dispatchHubFrame) else {
            return nil
        }
        let rect = NSRectFromString(raw)
        return rect.width >= 380 && rect.height >= 420 ? rect : nil
    }

    static func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: DefaultsKey.dispatchHubFrame)
    }
}
