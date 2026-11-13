// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CryptoKit
import Foundation

/// Wire-compatible YTCE2 Jianguoyun WebDAV clipboard sync actor.
/// Shares exact JSON keys ("Version", "DeviceId", "LastSequence", "Sequence",
/// "Kind", "Item", "DeletedIds") and compact 32-hex device UUID paths with YTools.Windows.
actor ClipboardCloudSyncActor {
    struct Credentials: Codable, Sendable {
        let username: String
        let appPassword: String
        let syncPassphrase: String
    }

    struct Head: Codable, Sendable {
        let version: Int
        let deviceID: UUID
        let lastSequence: Int64
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case version = "Version"
            case deviceID = "DeviceId"
            case lastSequence = "LastSequence"
            case updatedAt = "UpdatedAt"
        }
    }

    enum EventKind: Int, Codable, Sendable {
        case upsert = 0
        case delete = 1
    }

    struct Record: Codable, Sendable {
        let id: UUID
        let kind: Int // 0 = text, 1 = files, 2 = image
        let payload: [String]
        let createdAt: Date
        let updatedAt: Date
        let sourceApplication: String?
        let binaryData: Data?
        let contentHash: String?
        let isPinned: Bool

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case kind = "Kind"
            case payload = "Payload"
            case createdAt = "CreatedAt"
            case updatedAt = "UpdatedAt"
            case sourceApplication = "SourceApplication"
            case binaryData = "BinaryData"
            case contentHash = "ContentHash"
            case isPinned = "IsPinned"
        }
    }

    struct Event: Codable, Sendable {
        let sequence: Int64
        let deviceID: UUID
        let kind: EventKind
        let timestamp: Date
        let item: Record?
        let deletedIDs: [UUID]

        enum CodingKeys: String, CodingKey {
            case sequence = "Sequence"
            case deviceID = "DeviceId"
            case kind = "Kind"
            case timestamp = "Timestamp"
            case item = "Item"
            case deletedIDs = "DeletedIds"
        }
    }

    private struct PersistentState: Codable {
        var deviceID: UUID
        var scopeBinding: String?
        var nextSequence: Int64 = 1
        var publishedSequence: Int64 = 0
        var cursors: [String: Int64] = [:]
        var pending: [Event] = []
        var inbox: [Event] = []
        var tombstones: [UUID: Date] = [:]
    }

    struct SyncOutcome: Sendable {
        let success: Bool
        let message: String
        let pulledEvents: [Event]
        let pendingUploads: Int
        let deviceIDShort: String
    }

    private static let endpoint = URL(string: "https://dav.jianguoyun.com/dav/")!
    private let credentialStore = SecureVaultCodableStore(name: "clipboard-cloud-credentials")
    private let stateStore = SecureVaultCodableStore(name: "clipboard-cloud-state")
    private let session: URLSession
    private var state = PersistentState(deviceID: UUID())
    private var loaded = false

    init() {
        let delegate = ZeroRedirectSessionDelegate()
        self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    var hasCredentials: Bool {
        if case .loaded = credentialStore.load(Credentials.self) { return true }
        return false
    }

    func maskedAccount() -> String? {
        guard case let .loaded(creds) = credentialStore.load(Credentials.self) else { return nil }
        return creds.username
    }

    func saveCredentials(username: String, appPassword: String, syncPassphrase: String) -> String? {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty, !appPassword.isEmpty, syncPassphrase.count >= 12 else {
            return "Enter your Jianguoyun email, WebDAV app password, and a passphrase of at least 12 characters."
        }
        guard credentialStore.save(Credentials(username: cleanUser,
                                               appPassword: appPassword,
                                               syncPassphrase: syncPassphrase)) else {
            return "Could not store credentials in the Keychain-backed vault."
        }
        return nil
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        switch stateStore.load(PersistentState.self) {
        case let .loaded(saved):
            state = saved
            loaded = true
        case .missing:
            state = PersistentState(deviceID: UUID())
            guard stateStore.save(state) else {
                throw NSError(domain: "ClipboardCloudSync", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Unable to initialize encrypted sync state."])
            }
            loaded = true
        case let .unavailable(msg), let .corrupted(msg):
            throw NSError(domain: "ClipboardCloudSync", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    func enqueueUpsert(_ record: Record) -> Int {
        guard (try? ensureLoaded()) != nil else { return state.pending.count }
        let seq = state.nextSequence
        state.nextSequence += 1
        state.pending.removeAll { $0.kind == .upsert && $0.item?.id == record.id }
        state.pending.append(Event(sequence: seq,
                                   deviceID: state.deviceID,
                                   kind: .upsert,
                                   timestamp: record.updatedAt,
                                   item: record,
                                   deletedIDs: []))
        _ = stateStore.save(state)
        return state.pending.count
    }

    func enqueueDelete(_ ids: [UUID]) -> Int {
        guard !ids.isEmpty, (try? ensureLoaded()) != nil else { return state.pending.count }
        let now = Date()
        for id in ids { state.tombstones[id] = now }
        let seq = state.nextSequence
        state.nextSequence += 1
        state.pending.append(Event(sequence: seq,
                                   deviceID: state.deviceID,
                                   kind: .delete,
                                   timestamp: now,
                                   item: nil,
                                   deletedIDs: ids))
        _ = stateStore.save(state)
        return state.pending.count
    }

    func acknowledgeInbox() {
        guard loaded, !state.inbox.isEmpty else { return }
        state.inbox.removeAll()
        _ = stateStore.save(state)
    }

    func pendingCount() -> Int {
        _ = try? ensureLoaded()
        return state.pending.count
    }

    func deviceShortID() -> String {
        _ = try? ensureLoaded()
        return String(compactUUID(state.deviceID).prefix(8))
    }

    func syncNow(rawFolder: String, pullRemote: Bool) async -> SyncOutcome {
        do {
            try ensureLoaded()
        } catch {
            return SyncOutcome(success: false,
                               message: error.localizedDescription,
                               pulledEvents: [],
                               pendingUploads: state.pending.count,
                               deviceIDShort: String(compactUUID(state.deviceID).prefix(8)))
        }

        guard let folder = CloudBatchBudget.sanitizedRemoteFolder(rawFolder) else {
            return SyncOutcome(success: false,
                               message: "Remote WebDAV folder name contains unsupported characters.",
                               pulledEvents: [],
                               pendingUploads: state.pending.count,
                               deviceIDShort: String(compactUUID(state.deviceID).prefix(8)))
        }
        guard case let .loaded(creds) = credentialStore.load(Credentials.self) else {
            return SyncOutcome(success: false,
                               message: "Jianguoyun credentials are not configured yet.",
                               pulledEvents: [],
                               pendingUploads: state.pending.count,
                               deviceIDShort: String(compactUUID(state.deviceID).prefix(8)))
        }

        let deviceHex = compactUUID(state.deviceID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            // Ensure remote folder hierarchy: <folder>/, <folder>/heads/, <folder>/events/, <folder>/events/<deviceHex>/
            for path in [folder, "\(folder)/heads", "\(folder)/events", "\(folder)/events/\(deviceHex)"] {
                try await ensureCollection(path: path, creds: creds)
            }

            // 1. Upload bounded batch of pending local events
            var uploadedCount = 0
            var uploadedBytes = 0
            var highestUploadedSeq = state.publishedSequence
            var remaining: [Event] = []

            for (idx, event) in state.pending.enumerated() {
                let clear = try encoder.encode(event)
                let sealed = try YTCE2Cryptography.seal(clear, passphrase: creds.syncPassphrase)
                if CloudBatchBudget.fitsInBatch(currentCount: uploadedCount,
                                                currentBytes: uploadedBytes,
                                                nextBytes: sealed.count,
                                                maxCount: CloudBatchBudget.maxUploadEvents) {
                    let seqName = String(format: "%016lld.ytce2", event.sequence)
                    let eventPath = "\(folder)/events/\(deviceHex)/\(seqName)"
                    try await putBytes(sealed, to: eventPath, contentType: "application/octet-stream", creds: creds)
                    uploadedCount += 1
                    uploadedBytes += sealed.count
                    highestUploadedSeq = max(highestUploadedSeq, event.sequence)
                } else {
                    remaining.append(contentsOf: state.pending[idx...])
                    break
                }
            }

            if uploadedCount > 0 {
                let head = Head(version: 2,
                                deviceID: state.deviceID,
                                lastSequence: highestUploadedSeq,
                                updatedAt: Date())
                let headData = try encoder.encode(head)
                try await putBytes(headData,
                                   to: "\(folder)/heads/\(deviceHex).json",
                                   contentType: "application/json",
                                   creds: creds)
                state.publishedSequence = highestUploadedSeq
                state.pending = remaining
                _ = stateStore.save(state)
            }

            // 2. Pull remote heads & new encrypted events if requested
            if pullRemote && state.inbox.isEmpty {
                let headHrefs = try await propfindHrefs(path: "\(folder)/heads/", creds: creds)
                var pulledCount = 0
                var pulledBytes = 0
                var incoming: [Event] = []

                for href in headHrefs {
                    guard let fileName = href.split(separator: "/").last.map(String.init),
                          fileName.hasSuffix(".json") else { continue }
                    let peerHex = String(fileName.dropLast(5)).lowercased()
                    guard peerHex != deviceHex, peerHex.count == 32 else { continue }

                    let headBytes = try await getBytes(from: "\(folder)/heads/\(fileName)",
                                                       maxBytes: CloudBatchBudget.maxHeadBytes,
                                                       creds: creds)
                    let peerHead = try decoder.decode(Head.self, from: headBytes)
                    let cursor = state.cursors[peerHex] ?? 0
                    guard peerHead.lastSequence > cursor else { continue }

                    var seq = cursor + 1
                    while seq <= peerHead.lastSequence {
                        let seqName = String(format: "%016lld.ytce2", seq)
                        let encrypted = try await getBytes(
                            from: "\(folder)/events/\(peerHex)/\(seqName)",
                            maxBytes: CloudBatchBudget.maxSingleEventBytes,
                            creds: creds
                        )
                        guard CloudBatchBudget.fitsInBatch(currentCount: pulledCount,
                                                           currentBytes: pulledBytes,
                                                           nextBytes: encrypted.count,
                                                           maxCount: CloudBatchBudget.maxPullEvents) else {
                            break
                        }
                        let clear = try YTCE2Cryptography.open(encrypted, passphrase: creds.syncPassphrase)
                        let event = try decoder.decode(Event.self, from: clear)
                        incoming.append(event)
                        pulledCount += 1
                        pulledBytes += encrypted.count
                        state.cursors[peerHex] = seq
                        seq += 1
                    }
                }

                if !incoming.isEmpty {
                    state.inbox = incoming
                    _ = stateStore.save(state)
                }
            }

            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let summary = "Synced at \(formatter.string(from: Date()))"
            return SyncOutcome(success: true,
                               message: summary,
                               pulledEvents: state.inbox,
                               pendingUploads: state.pending.count,
                               deviceIDShort: String(deviceHex.prefix(8)))
        } catch {
            return SyncOutcome(success: false,
                               message: error.localizedDescription,
                               pulledEvents: [],
                               pendingUploads: state.pending.count,
                               deviceIDShort: String(deviceHex.prefix(8)))
        }
    }

    private func compactUUID(_ uuid: UUID) -> String {
        uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func authorizedRequest(path: String, method: String, creds: Credentials) -> URLRequest {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = Self.endpoint.appendingPathComponent(clean)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        let token = Data("\(creds.username):\(creds.appPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func ensureCollection(path: String, creds: Credentials) async throws {
        let req = authorizedRequest(path: path, method: "MKCOL", creds: creds)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              [200, 201, 204, 301, 405].contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "ClipboardCloudSync", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "WebDAV MKCOL returned HTTP \(code)."])
        }
    }

    private func putBytes(_ data: Data, to path: String, contentType: String, creds: Credentials) async throws {
        var req = authorizedRequest(path: path, method: "PUT", creds: creds)
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "ClipboardCloudSync", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "WebDAV PUT returned HTTP \(code)."])
        }
    }

    private func getBytes(from path: String, maxBytes: Int, creds: Credentials) async throws -> Data {
        let req = authorizedRequest(path: path, method: "GET", creds: creds)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "ClipboardCloudSync", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "WebDAV GET returned HTTP \(code)."])
        }
        guard data.count <= maxBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        return data
    }

    private func propfindHrefs(path: String, creds: Credentials) async throws -> [String] {
        var req = authorizedRequest(path: path, method: "PROPFIND", creds: creds)
        req.setValue("1", forHTTPHeaderField: "Depth")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, [200, 207].contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "ClipboardCloudSync", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "WebDAV PROPFIND returned HTTP \(code)."])
        }
        return try WebDAVHrefParser.hrefs(in: data)
    }
}

private final class ZeroRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Main-thread coordinator bridging Vorssaint's ClipboardHistoryService with YTCE2 Cloud Sync.
@MainActor
final class ClipboardCloudSyncCoordinator: ObservableObject {
    static let shared = ClipboardCloudSyncCoordinator()

    @Published private(set) var hasCredentials = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var statusMessage = "Idle"
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingUploads = 0
    @Published private(set) var deviceShortID = "—"

    private let actor = ClipboardCloudSyncActor()
    private var pollTimer: Timer?
    private var isApplyingRemote = false

    private init() {
        Task { await refreshVaultMetadata() }
    }

    private var isSyncEnabled: Bool {
        AppFeature.clipboardHistory.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.clipboardCloudSyncEnabled)
    }

    private var remoteFolder: String {
        UserDefaults.standard.string(forKey: DefaultsKey.clipboardCloudSyncFolder) ?? "YTools"
    }

    func refreshVaultMetadata() async {
        hasCredentials = await actor.hasCredentials
        accountEmail = await actor.maskedAccount()
        pendingUploads = await actor.pendingCount()
        deviceShortID = await actor.deviceShortID()
    }

    func saveCredentials(username: String, appPassword: String, syncPassphrase: String) async -> String? {
        let error = await actor.saveCredentials(username: username,
                                                appPassword: appPassword,
                                                syncPassphrase: syncPassphrase)
        await refreshVaultMetadata()
        if error == nil && isSyncEnabled {
            syncNow()
        }
        return error
    }

    func syncWithPreferences() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard isSyncEnabled else { return }
        // Poll 4 KB per-device heads every 15 minutes, identical to YTools.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
        Task {
            await refreshVaultMetadata()
            if hasCredentials { syncNow() }
        }
    }

    func recordLocalUpsert(_ entry: ClipboardHistoryEntry) {
        guard isSyncEnabled, !isApplyingRemote,
              let record = Self.makeRecord(from: entry) else { return }
        Task {
            pendingUploads = await actor.enqueueUpsert(record)
            await performSync(pullRemote: false)
        }
    }

    func recordLocalDelete(_ ids: [UUID]) {
        guard isSyncEnabled, !isApplyingRemote, !ids.isEmpty,
              UserDefaults.standard.bool(forKey: DefaultsKey.clipboardCloudSyncPropagateDeletes)
        else { return }
        Task {
            pendingUploads = await actor.enqueueDelete(ids)
            await performSync(pullRemote: false)
        }
    }

    func syncNow() {
        Task { await performSync(pullRemote: true) }
    }

    private func performSync(pullRemote: Bool) async {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = "Syncing…"
        let folder = remoteFolder
        let outcome = await actor.syncNow(rawFolder: folder, pullRemote: pullRemote)
        pendingUploads = outcome.pendingUploads
        deviceShortID = outcome.deviceIDShort

        if outcome.success, !outcome.pulledEvents.isEmpty {
            isApplyingRemote = true
            ClipboardHistoryService.shared.applyCloudEvents(outcome.pulledEvents)
            isApplyingRemote = false
            await actor.acknowledgeInbox()
        }
        statusMessage = outcome.message
        isSyncing = false
    }

    static func makeRecord(from entry: ClipboardHistoryEntry) -> ClipboardCloudSyncActor.Record? {
        switch entry.kind {
        case .text:
            let hash = SHA256.hash(data: Data(entry.text.utf8)).map { String(format: "%02x", $0) }.joined()
            return ClipboardCloudSyncActor.Record(
                id: entry.id,
                kind: 0,
                payload: [entry.text],
                createdAt: entry.copiedAt,
                updatedAt: entry.copiedAt,
                sourceApplication: nil,
                binaryData: nil,
                contentHash: hash,
                isPinned: entry.isPinned
            )
        case .files:
            return ClipboardCloudSyncActor.Record(
                id: entry.id,
                kind: 1,
                payload: entry.filePaths,
                createdAt: entry.copiedAt,
                updatedAt: entry.copiedAt,
                sourceApplication: nil,
                binaryData: nil,
                contentHash: nil,
                isPinned: entry.isPinned
            )
        case .image:
            guard let name = entry.imageFile,
                  let png = ClipboardImageStore.imageData(named: name),
                  png.count <= CloudBatchBudget.maxSingleEventBytes else { return nil }
            return ClipboardCloudSyncActor.Record(
                id: entry.id,
                kind: 2,
                payload: [],
                createdAt: entry.copiedAt,
                updatedAt: entry.copiedAt,
                sourceApplication: nil,
                binaryData: png,
                contentHash: entry.imageHash,
                isPinned: entry.isPinned
            )
        }
    }
}
