// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

/// Interactive `/` and `~` directory browser + multi-file buffer + atomic no-overwrite
/// copy/move engine ported from YTools (`FileNavigationModule` & `FileOperationService`).
enum CommandBarDirectoryNav {
    struct ParsedPathQuery {
        let directoryURL: URL
        let filterPrefix: String
    }

    static func parsePathQuery(_ raw: String) -> ParsedPathQuery? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed == "~" else {
            return nil
        }
        if trimmed == "~" {
            return ParsedPathQuery(
                directoryURL: FileManager.default.homeDirectoryForCurrentUser,
                filterPrefix: ""
            )
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if trimmed.hasSuffix("/"),
           FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir),
           isDir.boolValue {
            return ParsedPathQuery(directoryURL: URL(fileURLWithPath: expanded, isDirectory: true),
                                   filterPrefix: "")
        }
        let candidateURL = URL(fileURLWithPath: expanded)
        let parentURL = candidateURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        return ParsedPathQuery(directoryURL: parentURL, filterPrefix: candidateURL.lastPathComponent)
    }

    static func entries(for rawQuery: String,
                        onNavigateIntoFolder: @escaping (String) -> Void) -> [CommandBarEntry] {
        guard let parsed = parsePathQuery(rawQuery) else { return [] }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        guard let urls = try? fm.contentsOfDirectory(
            at: parsed.directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants]
        ) else { return [] }

        let showDotfiles = parsed.filterPrefix.hasPrefix(".")
        let needle = CommandBarSearch.normalized(parsed.filterPrefix)
        let home = fm.homeDirectoryForCurrentUser.path

        let filtered = urls.filter { url in
            let name = url.lastPathComponent
            if !showDotfiles && name.hasPrefix(".") { return false }
            guard !needle.isEmpty else { return true }
            let foldedName = CommandBarSearch.normalized(name)
            let pinyin = CommandBarSearch.pinyinKeywords(name)
            return foldedName.contains(needle) || pinyin.contains(needle)
        }
        .sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
        .prefix(24)

        return filtered.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = (values?.isDirectory == true) && (values?.isPackage != true)
            let displayPath = abbreviate(url.path, home: home)
            let nextQuery = displayPath.hasSuffix("/") ? displayPath : displayPath + "/"
            return CommandBarEntry(
                id: "dirnav.\(url.path)",
                stableKey: "dirnav.\(url.path)",
                title: url.lastPathComponent,
                subtitle: isFolder
                    ? "\(displayPath) · \(YToolsStrings.folderBrowserSubtitle)"
                    : displayPath,
                keywords: CommandBarSearch.pinyinKeywords(url.lastPathComponent),
                icon: .filePath(url.path),
                shortcut: nil,
                menuShortcut: nil,
                isActive: false,
                trouble: nil,
                numericRange: nil,
                numericIsOptional: false,
                confirmationPrompt: nil,
                answerValue: nil,
                isAnswer: false,
                countsUsage: false,
                matchTitle: url.lastPathComponent,
                keepsBarOpen: isFolder,
                takesArgument: false,
                revealPath: url.path,
                uninstallAppURL: nil,
                run: { _ in
                    if isFolder {
                        onNavigateIntoFolder(nextQuery)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        }
    }

    private static func abbreviate(_ path: String, home: String) -> String {
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

/// Multi-file staging buffer + safe non-overwriting file copy/move (renamex_np RENAME_EXCL).
final class SafeFileTransferCoordinator: @unchecked Sendable {
    static let shared = SafeFileTransferCoordinator()
    private let lock = NSLock()
    private var _bufferedPaths: [String] = []

    var bufferedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _bufferedPaths
    }

    func addToBuffer(_ path: String) {
        let count: Int
        lock.lock()
        if !_bufferedPaths.contains(path) {
            _bufferedPaths.append(path)
        }
        count = _bufferedPaths.count
        lock.unlock()
        QuickToolHUD.show(icon: "tray.and.arrow.down",
                          message: "\(count) buffered")
    }

    func clearBuffer() {
        lock.lock()
        _bufferedPaths.removeAll()
        lock.unlock()
        QuickToolHUD.show(icon: "tray", message: "Buffer cleared")
    }

    @MainActor
    func chooseDestinationAndTransfer(sources: [String], move: Bool) {
        let validSources = sources.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validSources.isEmpty else {
            NSSound.beep()
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = move ? "Move Here" : "Copy Here"
        guard panel.runModal() == .OK, let destinationDir = panel.url else { return }

        Task.detached(priority: .userInitiated) {
            do {
                for src in validSources {
                    try Self.transferSingleItem(source: src, destinationDirectory: destinationDir, move: move)
                }
                await MainActor.run {
                    QuickToolHUD.show(icon: "checkmark.circle",
                                      message: move ? "Safe move complete" : "Safe copy complete")
                }
            } catch {
                await MainActor.run {
                    NSSound.beep()
                    QuickToolHUD.show(icon: "exclamationmark.triangle",
                                      message: error.localizedDescription)
                }
            }
        }
    }

    private static func transferSingleItem(source: URL,
                                           destinationDirectory: URL,
                                           move: Bool) throws {
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true else {
            throw NSError(domain: "SafeFileTransfer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Symbolic links are refused for safety."])
        }
        guard let srcReal = realpath(source.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(srcReal) }
        guard let dstReal = realpath(destinationDirectory.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(dstReal) }

        let canonicalSource = URL(fileURLWithPath: String(cString: srcReal))
        let canonicalDir = URL(fileURLWithPath: String(cString: dstReal))
        if values.isDirectory == true,
           canonicalDir.path == canonicalSource.path
               || canonicalDir.path.hasPrefix(canonicalSource.path + "/") {
            throw NSError(domain: "SafeFileTransfer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot copy or move a folder into itself."])
        }

        let finalTarget = canonicalDir.appendingPathComponent(canonicalSource.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: finalTarget.path) else {
            throw NSError(domain: "SafeFileTransfer", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Target already exists; refusing to overwrite."])
        }

        var srcStat = stat()
        var dstStat = stat()
        let sameVol = Darwin.lstat(canonicalSource.path, &srcStat) == 0
            && Darwin.lstat(canonicalDir.path, &dstStat) == 0
            && srcStat.st_dev == dstStat.st_dev

        if move && sameVol {
            guard renamex_np(canonicalSource.path, finalTarget.path, UInt32(RENAME_EXCL)) == 0 else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }

        let stage = canonicalDir.appendingPathComponent(".vorssaint-transfer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: canonicalSource, to: stage)
        _ = copyfile(canonicalSource.path, stage.path, nil, copyfile_flags_t(COPYFILE_METADATA))
        guard renamex_np(stage.path, finalTarget.path, UInt32(RENAME_EXCL)) == 0 else {
            throw CocoaError(.fileWriteFileExists)
        }
        if move {
            try FileManager.default.removeItem(at: canonicalSource)
        }
    }
}
