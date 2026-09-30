// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security
import CryptoKit

enum FanControlIdentifiers {
    static let teamID = "3D485NHW29"

    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.vorssaint.utils.dev"
    #else
    static let appBundleID = "com.vorssaint.utils"
    #endif

    static let helperID = "\(appBundleID).fan-control"
    static let plistName = "\(helperID).plist"

    /// Trust the actual signer, including a stable local certificate. An ad-hoc
    /// identifier is forgeable and must never authorize privileged fan writes.
    static var appCodeRequirement: String {
        codeRequirement(identifier: appBundleID, team: signingTeamID,
                        certificateHash: signingCertificateHash)
    }

    static var helperCodeRequirement: String {
        codeRequirement(identifier: helperID, team: signingTeamID,
                        certificateHash: signingCertificateHash)
    }

    static var hasTrustedSignature: Bool { signingTeamID != nil || signingCertificateHash != nil }

    static func codeRequirement(identifier: String, team: String?, certificateHash: String?) -> String {
        if let team, !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(identifier)\""
        }
        if let certificateHash, certificateHash.count == 40,
           certificateHash.allSatisfy({ $0.isHexDigit }) {
            return "certificate leaf = H\"\(certificateHash)\" and identifier \"\(identifier)\""
        }
        return "never"
    }

    static var signingTeamID: String? {
        guard let team = signingInfo?[kSecCodeInfoTeamIdentifier] as? String,
              !team.isEmpty else { return nil }
        return team
    }

    private static var signingCertificateHash: String? {
        guard let certificates = signingInfo?[kSecCodeInfoCertificates] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        // Code requirement certificate hashes use SHA-1 as a certificate
        // fingerprint; this pins the signer rather than hashing executable data.
        return Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data)
            .map { String(format: "%02x", $0) }.joined()
    }

    private static let signingInfo: NSDictionary? = {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &info
              ) == errSecSuccess,
              let info else { return nil }
        return info as NSDictionary
    }()
}

@objc protocol FanControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func startMaximumCooling(withReply reply: @escaping (Data) -> Void)
    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreAutomatic(withReply reply: @escaping (Data) -> Void)
}

enum FanControlIPC {
    static func encode(_ response: FanControlResponse) -> Data {
        // Every value in this closed response model is JSON encodable. Keeping
        // one deterministic fallback avoids ever violating the XPC reply shape.
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"fans":[],"isCooling":false},"error":"controlFailed"}"#.utf8)
    }

    static func decode(_ data: Data) -> FanControlResponse? {
        try? JSONDecoder().decode(FanControlResponse.self, from: data)
    }

    static func encode(_ configuration: FanControlConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration)
    }

    static func decodeConfiguration(_ data: Data) -> FanControlConfiguration? {
        guard let configuration = try? JSONDecoder().decode(FanControlConfiguration.self,
                                                              from: data),
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}
