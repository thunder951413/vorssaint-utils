// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import Foundation

/// Offline macOS CoreServices Dictionary (`define` / `dict`) and NSSpellChecker (`spell`)
/// ported from YTools with zero bundled dictionary file overhead.
enum CommandBarDictionarySupport {
    struct LookupRequest: Equatable {
        let word: String
        let isExplicit: Bool
    }

    static func parseDictionaryQuery(_ query: String) -> LookupRequest? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in ["define ", "dict "] where lowered.hasPrefix(prefix) {
            let word = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return word.isEmpty ? nil : LookupRequest(word: word, isExplicit: true)
        }
        let isSingleWord = trimmed.range(
            of: #"^[A-Za-z][A-Za-z'-]{2,40}$"#,
            options: .regularExpression
        ) != nil
        return isSingleWord ? LookupRequest(word: trimmed, isExplicit: false) : nil
    }

    static func parseSpellQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("spell ") else { return nil }
        let word = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        return word.isEmpty ? nil : word
    }

    static func systemDefinition(for word: String) -> String? {
        let cfWord = word as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cfWord))
        guard let unmanaged = DCSCopyTextDefinition(nil, cfWord, range) else { return nil }
        let text = (unmanaged.takeRetainedValue() as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func condensedSummary(_ definition: String, limit: Int = 84) -> String {
        let singleLine = definition
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit)) + "…"
    }

    static func spellingSuggestions(for word: String) -> [String] {
        guard Thread.isMainThread else { return [] }
        return MainActor.assumeIsolated {
            let checker = NSSpellChecker.shared
            let nsRange = NSRange(location: 0, length: (word as NSString).length)
            let misspelled = checker.checkSpelling(of: word, startingAt: 0)
            if misspelled.location == NSNotFound {
                return [word]
            }
            let guesses = checker.guesses(forWordRange: nsRange,
                                          in: word,
                                          language: checker.language(),
                                          inSpellDocumentWithTag: 0) ?? []
            return Array(guesses.prefix(5))
        }
    }
}
