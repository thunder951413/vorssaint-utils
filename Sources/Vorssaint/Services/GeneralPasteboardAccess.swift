// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import AppKit

/// Serializes every access the app makes to the general pasteboard.
/// NSPasteboard keeps a mutable type cache on its shared instance, so reading
/// it from two queues at once can race inside AppKit, and a read has no time
/// limit: content can be promised and rendered only on demand, so an app that
/// stops answering leaves the reader hanging. Hence one serial lane, off the
/// main thread, and no way to wait for it — a caller waiting on the main
/// thread is a frozen app (issue #887).
final class GeneralPasteboardAccess {
    static let shared = GeneralPasteboardAccess()

    typealias DeadlineScheduler = (_ delay: TimeInterval,
                                   _ action: @escaping () -> Void) -> (() -> Void)

    private let queue: DispatchQueue
    private let now: () -> TimeInterval
    private let scheduleDeadline: DeadlineScheduler
    private let pasteboard: () -> any ClipboardHistoryPasteboard

    init(label: String = "Vorssaint.Pasteboard.general",
         now: @escaping () -> TimeInterval = {
             TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
         },
         scheduleDeadline: DeadlineScheduler? = nil,
         pasteboard: @escaping () -> any ClipboardHistoryPasteboard = { NSPasteboard.general }) {
        queue = DispatchQueue(label: label, qos: .utility)
        self.now = now
        self.pasteboard = pasteboard
        self.scheduleDeadline = scheduleDeadline ?? { delay, action in
            let item = DispatchWorkItem(block: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        }
    }

    /// User actions expire while queued instead of unexpectedly overwriting
    /// the clipboard when a previously hung provider eventually returns.
    func copyString(_ value: String, completion: @escaping (Bool) -> Void = { _ in }) {
        async(timeout: 2, { isExpired in
            ClipboardHistoryWrite.text(value).write(to: self.pasteboard(), isExpired: isExpired)?.succeeded
        }, then: { completion($0 == true) })
    }

    func readString(completion: @escaping (String?) -> Void) {
        async(timeout: 2, { _ in NSPasteboard.general.string(forType: .string) ?? "" }, then: completion)
    }

    func perform<T>(timeout: TimeInterval = 2,
                    _ work: @escaping (_ isExpired: () -> Bool) -> T?) async -> T? {
        let cancellation = PasteboardCancellation()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                async(timeout: timeout, { isExpired in
                    guard !isExpired(), !cancellation.isCancelled else { return nil }
                    let result = work { isExpired() || cancellation.isCancelled }
                    return isExpired() || cancellation.isCancelled ? nil : result
                }, then: { continuation.resume(returning: $0) })
            }
        }, onCancel: { cancellation.cancel() })
    }

    func writeObjects(_ objects: [NSPasteboardWriting],
                      expectedChangeCount: Int? = nil) async -> Bool {
        let succeeded: Bool? = await perform { isExpired in
            let pasteboard = self.pasteboard()
            guard !isExpired(), expectedChangeCount == nil || pasteboard.changeCount == expectedChangeCount else {
                return false
            }
            guard !isExpired() else { return false }
            _ = pasteboard.clearContents()
            guard !isExpired() else { return false }
            return pasteboard.writeObjects(objects)
        }
        return succeeded == true
    }

    func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    /// Runs `work` on the lane and hands its result to `completion` on the
    /// main queue. The caller returns immediately: a wedged lane delays the
    /// completion, it never blocks whoever asked.
    func async<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// A deadline limits result delivery and prevents expired queued work
    /// from starting. It cannot interrupt an AppKit call already in progress.
    /// `didFinish` runs on main only when the actual queue operation ends,
    /// even if `completion` already received nil at the deadline. Callers use
    /// it to keep admission bounded while a provider is unresponsive.
    func async<T>(timeout: TimeInterval,
                   _ work: @escaping (_ isExpired: () -> Bool) -> T?,
                   then completion: @escaping (T?) -> Void,
                   didFinish: @escaping (T?) -> Void = { _ in }) {
        let deadline = now() + timeout
        let delivery = PasteboardResultDelivery(completion)
        let cancelDeadline = scheduleDeadline(timeout) { delivery.complete(nil) }
        queue.async {
            let isExpired = { self.now() >= deadline }
            let value = isExpired() ? nil : work(isExpired)
            DispatchQueue.main.async {
                cancelDeadline()
                didFinish(value)
                delivery.complete(isExpired() ? nil : value)
            }
        }
    }
}

final class PasteboardCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// Both deadline and queue completion deliver on main. Clearing the callback
/// before invoking it also makes reentrant callers safe.
private final class PasteboardResultDelivery<Value> {
    private var completion: ((Value?) -> Void)?

    init(_ completion: @escaping (Value?) -> Void) {
        self.completion = completion
    }

    func complete(_ value: Value?) {
        precondition(Thread.isMainThread)
        let callback = completion
        completion = nil
        callback?(value)
    }
}
