// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CommonCrypto
import CryptoKit
import Foundation

/// Pure batch-size and byte-budget limiter shared with YTools YTCE2 sync.
enum CloudBatchBudget {
    static let maxUploadEvents = 50
    static let maxPullEvents = 200
    static let maxBatchBytes = 16 * 1024 * 1024
    static let maxSingleEventBytes = 8 * 1024 * 1024
    static let maxHeadBytes = 4 * 1024

    static func fitsInBatch(currentCount: Int,
                            currentBytes: Int,
                            nextBytes: Int,
                            maxCount: Int) -> Bool {
        guard currentCount < maxCount, nextBytes <= maxSingleEventBytes else {
            return false
        }
        if currentCount == 0 {
            return nextBytes <= maxBatchBytes
        }
        return currentBytes + nextBytes <= maxBatchBytes
    }

    static func sanitizedRemoteFolder(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = trimmed.isEmpty ? "YTools" : trimmed
        let segments = target.split(separator: "/").map(String.init)
        guard !segments.isEmpty,
              segments.allSatisfy({ segment in
                  !segment.isEmpty
                      && segment != "."
                      && segment != ".."
                      && !segment.contains("\\")
                      && segment.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
              })
        else { return nil }
        return segments.joined(separator: "/")
    }
}

/// Wire-identical YTCE2 envelope shared with YTools (macOS & Windows):
/// 5-byte "YTCE2" magic + 16-byte random salt + AES-256-GCM combined sealed box
/// keyed via PBKDF2-HMAC-SHA256 (600,000 iterations).
enum YTCE2Cryptography {
    private static let magic = Data("YTCE2".utf8)
    static let iterations: UInt32 = 600_000

    enum CryptoError: LocalizedError {
        case invalidEnvelope
        case keyDerivationFailed

        var errorDescription: String? {
            switch self {
            case .invalidEnvelope:
                return "Invalid YTCE2 ciphertext envelope or wrong sync passphrase."
            case .keyDerivationFailed:
                return "Failed to derive PBKDF2-SHA256 sync key."
            }
        }
    }

    static func seal(_ clear: Data, passphrase: String) throws -> Data {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        let salt = Data(saltBytes)
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let box = try AES.GCM.seal(clear, using: SymmetricKey(data: key))
        guard let combined = box.combined else { throw CryptoError.invalidEnvelope }
        return magic + salt + combined
    }

    static func open(_ encrypted: Data, passphrase: String) throws -> Data {
        guard encrypted.count >= magic.count + 16 + 28,
              encrypted.prefix(magic.count) == magic else {
            throw CryptoError.invalidEnvelope
        }
        let salt = encrypted.subdata(in: magic.count..<(magic.count + 16))
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(magic.count + 16))
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    private static func deriveKey(passphrase: String, salt: Data) throws -> Data {
        var key = [UInt8](repeating: 0, count: 32)
        let password = Array(passphrase.utf8)
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    password.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &key,
                    key.count
                )
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return Data(key)
    }
}

/// Safe WebDAV PROPFIND XML href parser with external entity resolution disabled.
final class WebDAVHrefParser: NSObject, XMLParserDelegate {
    private var values: [String] = []
    private var reading = false
    private var current = ""

    static func hrefs(in data: Data) throws -> [String] {
        let parser = XMLParser(data: data)
        let delegate = WebDAVHrefParser()
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        return delegate.values
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "href",
           namespaceURI == "DAV:" || namespaceURI == nil || namespaceURI == "" {
            reading = true
            current = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if reading { current += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if reading,
           elementName == "href",
           namespaceURI == "DAV:" || namespaceURI == nil || namespaceURI == "" {
            values.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            reading = false
        }
    }
}
