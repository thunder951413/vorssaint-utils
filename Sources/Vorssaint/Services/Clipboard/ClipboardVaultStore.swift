// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation
import Security

/// Device-bound 256-bit master key stored in the macOS login Keychain.
/// Never leaves this Mac and never participates in Settings backups.
struct ClipboardKeychainKeyAccessor: Sendable {
    enum AccessError: LocalizedError {
        case missing(String)
        case keychain(OSStatus)
        case randomGeneration

        var errorDescription: String? {
            switch self {
            case let .missing(message):
                return message
            case let .keychain(status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "Keychain unavailable: \(detail)"
            case .randomGeneration:
                return "Unable to generate a 256-bit random vault key."
            }
        }
    }

    let service: String
    let account: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.vorssaint.utils") + ".ytools.vault",
         account: String = "clipboard-cloud-master-key-v1") {
        self.service = service
        self.account = account
    }

    func key(createIfMissing: Bool) throws -> Data {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return data
        }
        guard status == errSecItemNotFound else {
            throw AccessError.keychain(status)
        }
        guard createIfMissing else {
            throw AccessError.missing("Vault key is missing from login Keychain; existing ciphertext was preserved read-only.")
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AccessError.randomGeneration
        }
        let data = Data(bytes)
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw AccessError.keychain(insertStatus)
        }
        return data
    }
}

/// Fail-closed AES-256-GCM Codable store inside PrivateFileStore (0700 / 0600).
/// Authentication or decoding failures lock writes so corrupted ciphertext is
/// never silently overwritten with empty state.
final class SecureVaultCodableStore: @unchecked Sendable {
    enum LoadResult<Value> {
        case loaded(Value)
        case missing
        case unavailable(String)
        case corrupted(String)
    }

    private let magic = Data("VSYTVLT1".utf8)
    private let name: String
    private let keyAccessor: ClipboardKeychainKeyAccessor
    private let lock = NSLock()
    private var writeLocked = false

    init(name: String, keyAccessor: ClipboardKeychainKeyAccessor = ClipboardKeychainKeyAccessor()) {
        self.name = name
        self.keyAccessor = keyAccessor
    }

    private var fileURL: URL? {
        guard let root = PrivateFileStore.containerURL?
            .appendingPathComponent("ytools-vault", isDirectory: true)
        else { return nil }
        guard PrivateFileStore.createDirectory(at: root) else { return nil }
        return root.appendingPathComponent("\(name).v1.enc", isDirectory: false)
    }

    func load<Value: Decodable>(_ type: Value.Type) -> LoadResult<Value> {
        lock.lock()
        defer { lock.unlock() }

        guard let url = fileURL else {
            return .unavailable("Application Support container is unavailable.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        do {
            let encrypted = try Data(contentsOf: url)
            guard encrypted.count > magic.count + 28,
                  encrypted.prefix(magic.count) == magic else {
                writeLocked = true
                return .corrupted("Vault header mismatch; store locked read-only.")
            }
            let rawKey = try keyAccessor.key(createIfMissing: false)
            let sealed = try AES.GCM.SealedBox(combined: encrypted.dropFirst(magic.count))
            let clear = try AES.GCM.open(sealed, using: SymmetricKey(data: rawKey))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(Value.self, from: clear)
            return .loaded(decoded)
        } catch let error as ClipboardKeychainKeyAccessor.AccessError {
            writeLocked = true
            return .unavailable(error.localizedDescription)
        } catch {
            writeLocked = true
            return .corrupted("Vault authentication failed; existing ciphertext preserved.")
        }
    }

    @discardableResult
    func save<Value: Encodable>(_ value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !writeLocked, let url = fileURL else { return false }
        let exists = FileManager.default.fileExists(atPath: url.path)
        do {
            let rawKey = try keyAccessor.key(createIfMissing: !exists)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let clear = try encoder.encode(value)
            let box = try AES.GCM.seal(clear, using: SymmetricKey(data: rawKey))
            guard let combined = box.combined else { return false }
            return PrivateFileStore.write(magic + combined, to: url)
        } catch {
            return false
        }
    }
}
