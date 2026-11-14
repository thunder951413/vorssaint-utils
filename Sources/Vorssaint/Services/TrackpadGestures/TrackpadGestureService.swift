// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import Darwin
import Foundation
import IOKit

private func multitouchHubContactCallback(_ device: UnsafeMutableRawPointer?,
                                          _ touches: UnsafeMutableRawPointer?,
                                          _ count: Int32,
                                          _ timestamp: Double,
                                          _ frame: Int32) -> Int32 {
    MultitouchDeviceHub.shared.dispatchFrame(
        device: device,
        touches: touches,
        count: Int(count),
        timestamp: timestamp
    )
    return 0
}

private func multitouchHubContactCallbackWithRefcon(_ device: UnsafeMutableRawPointer?,
                                                    _ touches: UnsafeMutableRawPointer?,
                                                    _ count: Int32,
                                                    _ timestamp: Double,
                                                    _ frame: Int32,
                                                    _ refcon: UnsafeMutableRawPointer?) -> Int32 {
    MultitouchDeviceHub.shared.dispatchFrame(
        device: device,
        touches: touches,
        count: Int(count),
        timestamp: timestamp
    )
    return 0
}

/// Shared MultitouchSupport multiplexer so `MiddleClickService` and
/// `TrackpadGestureService` coexist in the same process across all connected
/// trackpads (built-in + Magic Trackpad) with automatic wake/hotplug recovery.
final class MultitouchDeviceHub: @unchecked Sendable {
    static let shared = MultitouchDeviceHub()

    typealias FrameConsumer = (UnsafeMutableRawPointer?, Int, Double) -> Void
    typealias DeviceFrameConsumer = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, Double) -> Void

    private typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias ContactCallbackWithRefcon = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32, UnsafeMutableRawPointer?
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback?) -> Void
    private typealias RegisterRefconFn = @convention(c) (
        UnsafeMutableRawPointer, ContactCallbackWithRefcon?, UnsafeMutableRawPointer?
    ) -> Void
    private typealias UnregisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback?) -> Void
    private typealias UnregisterRefconFn = @convention(c) (UnsafeMutableRawPointer, ContactCallbackWithRefcon?) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private static let handle: UnsafeMutableRawPointer? = {
        let paths = [
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/Current/MultitouchSupport",
        ]
        for path in paths {
            if let loaded = dlopen(path, RTLD_NOW) {
                return loaded
            }
        }
        return nil
    }()

    private static let createListFn: CreateListFn? = symbol("MTDeviceCreateList")
    private static let registerFn: RegisterFn? = symbol("MTRegisterContactFrameCallback")
    private static let registerRefconFn: RegisterRefconFn? = symbol("MTRegisterContactFrameCallbackWithRefcon")
    private static let unregisterFn: UnregisterFn? = symbol("MTUnregisterContactFrameCallback")
    private static let unregisterRefconFn: UnregisterRefconFn? = symbol("MTUnregisterContactFrameCallback")
    private static let startFn: StartFn? = symbol("MTDeviceStart")
    private static let stopFn: StopFn? = symbol("MTDeviceStop")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    private let lock = NSLock()
    private var consumers: [String: DeviceFrameConsumer] = [:]
    private var deviceList: CFArray?
    private var usesRefconCallback = false
    private var observers: [NSObjectProtocol] = []
    private var hotplugPort: IONotificationPortRef?
    private var hotplugIterator: io_iterator_t = 0
    private(set) var activeDeviceCount = 0

    private init() {}

    var isFrameworkAvailable: Bool {
        Self.createListFn != nil && Self.startFn != nil && (Self.registerFn != nil || Self.registerRefconFn != nil)
    }

    func subscribe(id: String, consumer: @escaping FrameConsumer) {
        subscribeDevice(id: id) { _, touches, count, timestamp in
            consumer(touches, count, timestamp)
        }
    }

    func subscribeDevice(id: String, consumer: @escaping DeviceFrameConsumer) {
        let shouldStart: Bool = lock.withLock {
            let wasEmpty = consumers.isEmpty
            consumers[id] = consumer
            return wasEmpty
        }
        if shouldStart {
            if Thread.isMainThread {
                ensureStartedOnMain()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.ensureStartedOnMain()
                }
            }
        } else {
            ensureStartedIfOnMain()
        }
    }

    func unsubscribe(id: String) {
        let shouldStop: Bool = lock.withLock {
            consumers.removeValue(forKey: id)
            return consumers.isEmpty
        }
        if shouldStop {
            if Thread.isMainThread {
                stopAllOnMain()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stopAllOnMain()
                }
            }
        }
    }

    func restart() {
        if Thread.isMainThread {
            restartOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.restartOnMain()
            }
        }
    }

    fileprivate func dispatchFrame(device: UnsafeMutableRawPointer?,
                                   touches: UnsafeMutableRawPointer?,
                                   count: Int,
                                   timestamp: Double) {
        let snapshot = lock.withLock { Array(consumers.values) }
        for consumer in snapshot {
            consumer(device, touches, count, timestamp)
        }
    }

    private func ensureStartedIfOnMain() {
        guard Thread.isMainThread else { return }
        ensureStartedOnMain()
    }

    private func ensureStartedOnMain() {
        let hasConsumers = lock.withLock { !consumers.isEmpty }
        guard hasConsumers else { return }
        startDevices()
        installObservers()
    }

    private func restartOnMain() {
        let hasConsumers = lock.withLock { !consumers.isEmpty }
        guard hasConsumers else { return }
        stopDevices()
        startDevices()
    }

    private func stopAllOnMain() {
        let hasConsumers = lock.withLock { !consumers.isEmpty }
        guard !hasConsumers else { return }
        stopDevices()
        removeObservers()
    }

    private func startDevices() {
        guard deviceList == nil,
              let createFn = Self.createListFn,
              let startFn = Self.startFn,
              Self.registerFn != nil || Self.registerRefconFn != nil,
              let list = createFn()?.takeRetainedValue(),
              CFArrayGetCount(list) > 0 else {
            lock.withLock { activeDeviceCount = 0 }
            return
        }
        deviceList = list
        usesRefconCallback = (Self.registerFn == nil)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var started = 0
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            if let registerFn = Self.registerFn {
                registerFn(dev, multitouchHubContactCallback)
            } else {
                Self.registerRefconFn?(dev, multitouchHubContactCallbackWithRefcon, refcon)
            }
            startFn(dev, 0)
            started += 1
        }
        lock.withLock { activeDeviceCount = started }
    }

    private func stopDevices() {
        guard let list = deviceList else {
            lock.withLock { activeDeviceCount = 0 }
            return
        }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            Self.stopFn?(dev)
            if usesRefconCallback {
                Self.unregisterRefconFn?(dev, multitouchHubContactCallbackWithRefcon)
            } else if let unregisterFn = Self.unregisterFn {
                unregisterFn(dev, multitouchHubContactCallback)
            } else {
                Self.registerFn?(dev, nil)
            }
        }
        deviceList = nil
        lock.withLock { activeDeviceCount = 0 }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.restartOnMain()
        })
        guard hotplugPort == nil,
              let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var iterator: io_iterator_t = 0
        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("AppleMultitouchDevice"),
            { context, iterator in
                guard let context else { return }
                while case let entry = IOIteratorNext(iterator), entry != 0 {
                    IOObjectRelease(entry)
                }
                let hub = Unmanaged<MultitouchDeviceHub>.fromOpaque(context).takeUnretainedValue()
                hub.restartOnMain()
            },
            context,
            &iterator
        )
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            IOObjectRelease(entry)
        }
        hotplugPort = port
        hotplugIterator = iterator
    }

    private func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        if hotplugIterator != 0 {
            IOObjectRelease(hotplugIterator)
            hotplugIterator = 0
        }
        if let hotplugPort {
            IONotificationPortDestroy(hotplugPort)
            self.hotplugPort = nil
        }
    }
}

// MARK: - Public Compatibility Trackpad Provider (`TrackpadProviders.swift`)

private final class PublicTrackpadGestureProvider {
    var onGesture: ((TrackpadGestureEvent) -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var accumulator = PublicGestureAccumulator()

    @discardableResult
    func start() -> Bool {
        stop()
        let mask: NSEvent.EventTypeMask = [.scrollWheel, .swipe, .magnify]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        return globalMonitor != nil && localMonitor != nil
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        accumulator = PublicGestureAccumulator()
    }

    private func handle(_ event: NSEvent) {
        let gesture: TrackpadGestureEvent?
        switch event.type {
        case .scrollWheel:
            guard event.hasPreciseScrollingDeltas else { return }
            gesture = accumulator.scroll(
                dx: event.scrollingDeltaX / 500,
                dy: event.scrollingDeltaY / 500,
                phase: event.phase,
                momentum: event.momentumPhase
            )
        case .swipe:
            gesture = PublicGestureAccumulator.swipe(dx: event.deltaX / 10, dy: event.deltaY / 10)
        case .magnify:
            gesture = accumulator.magnify(event.magnification, phase: event.phase)
        default:
            return
        }
        if let gesture {
            onGesture?(gesture)
        }
    }

    deinit { stop() }
}

// MARK: - Action Executor & Process Management (`ActionExecutor.swift` + `ManagedProcess.swift`)

private enum GestureManagedProcess {
    static func terminate(_ process: Process, gracePeriod: TimeInterval = 2.0) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + gracePeriod) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

private final class ApplicationLaunchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFailure: String?
    var failure: String? {
        get { lock.withLock { storedFailure } }
        set { lock.withLock { storedFailure = newValue } }
    }
}

final class GestureActionExecutor: @unchecked Sendable {
    private var completionHandler: (@Sendable (String, String?) -> Void)?
    var onCompletion: (@Sendable (String, String?) -> Void)? {
        get {
            condition.lock()
            defer { condition.unlock() }
            return completionHandler
        }
        set {
            condition.lock()
            completionHandler = newValue
            condition.unlock()
        }
    }

    private let queue = DispatchQueue(label: "com.vorssaint.gesture.actions", qos: .userInitiated)
    private let condition = NSCondition()
    private let commandTimeout: TimeInterval
    private let maximumPendingExecutions: Int
    private let myPID: pid_t = getpid()
    private var stopped = false
    private var pendingExecutions = 0
    private var activeProcess: Process?

    init(commandTimeout: TimeInterval = 60, maximumPendingExecutions: Int = 32) {
        self.commandTimeout = commandTimeout.isFinite ? min(60, max(0.05, commandTimeout)) : 60
        self.maximumPendingExecutions = maximumPendingExecutions
    }

    @discardableResult
    func execute(_ actions: [GestureAutomationAction], ruleName: String) -> Bool {
        condition.lock()
        guard !stopped, pendingExecutions < maximumPendingExecutions else {
            condition.unlock()
            return false
        }
        pendingExecutions += 1
        condition.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.condition.lock()
                self.pendingExecutions -= 1
                self.condition.unlock()
            }
            var failure: String?
            for action in actions {
                guard !self.isStopped else { return }
                switch action.kind {
                case .keyboardShortcut:
                    if !self.postCleanKeyboardShortcut(keys: action.keys) {
                        failure = "Failed to synthesize shortcut"
                    }
                case .delay:
                    if !self.wait(milliseconds: action.delayMilliseconds) { return }
                case .openURL:
                    guard let url = URL(string: action.value), url.scheme != nil else {
                        failure = "Invalid URL: \(action.value)"
                        break
                    }
                    let opened = DispatchQueue.main.sync {
                        !self.isStopped && NSWorkspace.shared.open(url)
                    }
                    if !opened { failure = "Unable to open URL" }
                case .launchApplication:
                    failure = self.launchApplication(action.value)
                case .shellScript:
                    failure = self.run(executable: "/bin/zsh", arguments: ["-lc", action.value])
                case .appleScript:
                    failure = self.run(executable: "/usr/bin/osascript", arguments: ["-e", action.value])
                }
                if failure != nil { break }
            }
            guard !self.isStopped else { return }
            self.onCompletion?(ruleName, failure)
        }
        return true
    }

    func cancel() {
        condition.lock()
        stopped = true
        let process = activeProcess
        condition.broadcast()
        condition.unlock()
        if let process {
            GestureManagedProcess.terminate(process)
        }
    }

    private var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopped
    }

    /// Synthesizes key chord via isolated `.privateState` `CGEventSource` so physically
    /// held modifiers (e.g. `Cmd` during `Cmd+J -> Down`) never leak into the target event.
    private func postCleanKeyboardShortcut(keys: [String]) -> Bool {
        let (modifiers, regularKeys) = TrackpadGestureKeyCodec.classifyKeys(keys)
        guard !regularKeys.isEmpty,
              regularKeys.allSatisfy({ TrackpadGestureKeyCodec.keyCodeFor(name: $0) != nil }),
              AXIsProcessTrusted() else {
            return false
        }
        let source = CGEventSource(stateID: .privateState)
        let flags = TrackpadGestureKeyCodec.modifierFlags(for: modifiers)
        var allOK = true
        for key in regularKeys {
            guard let keyCode = TrackpadGestureKeyCodec.keyCodeFor(name: key),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
                allOK = false
                continue
            }
            down.flags = flags
            up.flags = flags
            down.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(myPID))
            up.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(myPID))
            down.post(tap: .cgSessionEventTap)
            usleep(1_200)
            up.post(tap: .cgSessionEventTap)
            usleep(400)
        }
        return allOK
    }

    private func wait(milliseconds: Int) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + Double(max(0, milliseconds)) / 1_000.0
        condition.lock()
        defer { condition.unlock() }
        while !stopped {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { break }
            _ = condition.wait(until: Date(timeIntervalSinceNow: min(remaining, 60)))
        }
        return !stopped
    }

    private func launchApplication(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let completed = DispatchSemaphore(value: 0)
        let result = ApplicationLaunchResultBox()
        DispatchQueue.main.sync {
            guard !isStopped else { completed.signal(); return }
            let url = trimmed.hasPrefix("/")
                ? URL(fileURLWithPath: trimmed)
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
            guard let url else {
                result.failure = "Application not found: \(trimmed)"
                completed.signal()
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                result.failure = error?.localizedDescription
                completed.signal()
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + commandTimeout
        while !isStopped {
            if completed.wait(timeout: .now() + 0.05) == .success {
                return result.failure
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                return "Timed out launching application: \(trimmed)"
            }
        }
        return nil
    }

    private func run(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let completed = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completed.signal() }

        condition.lock()
        guard !stopped else {
            condition.unlock()
            return nil
        }
        do {
            try process.run()
            activeProcess = process
            condition.unlock()
        } catch {
            condition.unlock()
            return "Failed to run command: \(error.localizedDescription)"
        }
        defer {
            condition.lock()
            activeProcess = nil
            condition.unlock()
        }

        let deadline = ProcessInfo.processInfo.systemUptime + commandTimeout
        while !isStopped {
            if completed.wait(timeout: .now() + 0.05) == .success {
                return process.terminationStatus == 0
                    ? nil
                    : "Command exited with status \(process.terminationStatus)"
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                GestureManagedProcess.terminate(process)
                _ = completed.wait(timeout: .now() + 2.5)
                return "Command timed out (\(Int(commandTimeout))s)"
            }
        }
        GestureManagedProcess.terminate(process)
        return nil
    }
}

// MARK: - Bounded Touch Trace Log (`GestureTraceLog.swift`)

final class GestureTraceLog: @unchecked Sendable {
    static let shared: GestureTraceLog = {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Vorssaint", isDirectory: true)
        return GestureTraceLog(directoryURL: logsDir)
    }()

    let url: URL
    private let maximumBytes: Int
    private let queue = DispatchQueue(label: "com.vorssaint.gesture.touch-traces", qos: .utility)

    init(directoryURL: URL, maximumBytes: Int = 5 * 1_024 * 1_024) {
        self.url = directoryURL.appendingPathComponent("touch-traces.jsonl")
        self.maximumBytes = maximumBytes
    }

    func write(_ trace: GestureTrace) {
        queue.async { [url, maximumBytes] in
            struct Record: Encodable {
                let recordedAt: Date
                let trace: GestureTrace
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard var data = try? encoder.encode(Record(recordedAt: Date(), trace: trace)),
                  data.count + 1 <= maximumBytes else { return }
            data.append(0x0A)
            let manager = FileManager.default
            do {
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let attributes = try? manager.attributesOfItem(atPath: url.path)
                let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                if size + data.count > maximumBytes {
                    let old = url.deletingPathExtension().appendingPathExtension("old.jsonl")
                    if manager.fileExists(atPath: old.path) {
                        try manager.removeItem(at: old)
                    }
                    try manager.moveItem(at: url, to: old)
                }
                if !manager.fileExists(atPath: url.path) {
                    manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Best-effort diagnostics; never interrupt gesture execution.
            }
        }
    }

    func flush() {
        queue.sync {}
    }
}

// MARK: - Unified Trackpad & Keyboard Automation Service (`GestureDaemon.swift`)

final class TrackpadGestureService: ObservableObject, @unchecked Sendable {
    static let shared = TrackpadGestureService()

    enum TrackpadBackendState: Equatable {
        case stopped
        case advanced
        case compatible(String)
        case unavailable(String)

        func label(chinese: Bool) -> String {
            switch self {
            case .stopped:
                return chinese ? "未启动" : "Stopped"
            case .advanced:
                return chinese ? "高级模式（原始多指触点 + 掌缘过滤）" : "Advanced (Raw Multi-Touch + Palm Filter)"
            case .compatible(let reason):
                let base = chinese ? "兼容模式（公开 NSEvent）" : "Compatibility (Public NSEvent)"
                return reason.isEmpty ? base : "\(base) · \(reason)"
            case .unavailable(let reason):
                return chinese ? "不可用：\(reason)" : "Unavailable: \(reason)"
            }
        }

        var isRunning: Bool {
            switch self {
            case .advanced, .compatible: return true
            case .stopped, .unavailable: return false
            }
        }
    }

    @Published var configuration: GestureAutomationConfiguration = .defaults
    @Published private(set) var isGestureRunning = false
    @Published private(set) var isChordRunning = false
    @Published private(set) var trackpadBackendState: TrackpadBackendState = .stopped
    @Published private(set) var lastTriggeredSummary = ""
    @Published private(set) var lastTouchObservation = ""
    @Published private(set) var lastGestureObservation = ""
    @Published private(set) var configurationWarnings: [String] = []
    @Published private(set) var errorMessages: [String] = []

    // Recognizer & device isolation state (guarded by `recognizerLock`)
    private let recognizerLock = NSLock()
    private let recognizer = TrackpadGestureRecognizer()
    private var cachedTrackpadRules: [GestureAutomationRule] = []
    private var cachedDebounceSeconds: TimeInterval = 0.15
    private var lastTriggerByRuleID: [UUID: TimeInterval] = [:]
    private var deviceLastTimestamps: [UInt: Double] = [:]
    private var activeTrackpadDeviceID: UInt?
    private var consecutiveInvalidFrames = 0
    private var lastTouchObservationUptime: TimeInterval = 0
    private var lastGestureObservationUptime: TimeInterval = 0

    // Public fallback provider (main thread)
    private var publicGestureProvider: PublicTrackpadGestureProvider?

    // Keyboard Event Tap state (guarded by `tapLock`)
    private let tapLock = NSLock()
    private var chordTap: CFMachPort?
    private var chordRunLoopSource: CFRunLoopSource?
    private let hotkeyMatcher = GestureHotkeyMatcher()
    private var shortcutRecordingActive = false

    // Frontmost app bundle identifier cache (lock-protected so real-time callbacks never block on AppKit)
    private let appScopeLock = NSLock()
    private var cachedFrontmostBundleID: String?
    private var workspaceObserver: NSObjectProtocol?

    // Action execution
    private let executorLock = NSLock()
    private var executor: GestureActionExecutor?
    private var testExecutor: GestureActionExecutor?

    private init() {
        cachedFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            self?.appScopeLock.withLock {
                self?.cachedFrontmostBundleID = bundleID
            }
        }

        loadStoredConfigurationOrMigrate()

        recognizer.onGesture = { [weak self] event in
            self?.handleRecognizedGestureLocked(event) ?? false
        }
        recognizer.onTrace = { [weak self] trace in
            GestureTraceLog.shared.write(trace)
            guard let self else { return }
            if trace.decision == .rejectedIncoherentSwipe {
                let text = "\(trace.fingers)F swipe ignored (incoherent contacts)"
                DispatchQueue.main.async { self.lastGestureObservation = text }
            } else if trace.decision == .ignoredLateContact {
                let text = "Late contact ignored during active \(trace.fingers)F gesture"
                DispatchQueue.main.async { self.lastGestureObservation = text }
            }
        }

        SessionActivity.shared.onChange { [weak self] active in
            if active {
                self?.syncWithPreferences()
            } else {
                self?.suspend()
            }
        }
    }

    var frontmostBundleIdentifier: String? {
        appScopeLock.withLock { cachedFrontmostBundleID }
    }

    var homeGestureConfigURL: URL {
        if let override = ProcessInfo.processInfo.environment["GESTURE_CONFIG_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gesture", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    var traceLogURL: URL {
        GestureTraceLog.shared.url
    }

    func setShortcutRecording(_ recording: Bool) {
        tapLock.withLock {
            shortcutRecordingActive = recording
            if recording {
                hotkeyMatcher.reset()
            }
        }
    }

    // MARK: - Lifecycle & Preference Sync

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let normalizedSettings = configuration.settings.normalized
        if configuration.settings != normalizedSettings {
            configuration.settings = normalizedSettings
        }

        let isChinese = Self.prefersChineseLabels()
        configurationWarnings = GestureConfigurationValidator.warnings(for: configuration, chinese: isChinese)
        errorMessages = []

        let executableTrackpad = configuration.rules.filter {
            $0.category == .trackpad && GestureConfigurationValidator.isExecutable($0)
        }
        let executableKeyboard = configuration.rules.filter {
            $0.category == .keyboard && GestureConfigurationValidator.isExecutable($0)
        }

        recognizerLock.withLock {
            recognizer.tuning = normalizedSettings.recognizerTuning
            cachedDebounceSeconds = TimeInterval(max(0, normalizedSettings.debounceMilliseconds)) / 1_000.0
            cachedTrackpadRules = executableTrackpad
        }
        tapLock.withLock {
            hotkeyMatcher.updateRules(executableKeyboard)
        }

        rebuildExecutorIfNeeded()

        let trusted = AXIsProcessTrusted()
        let activeSession = SessionActivity.shared.isActive
        let wantGestures = defaults.bool(forKey: DefaultsKey.trackpadGesturesEnabled)
            && !executableTrackpad.isEmpty
            && activeSession
            && (trusted || executableTrackpad.allSatisfy { rule in
                !rule.actions.contains { $0.kind == .keyboardShortcut }
            })
        let wantChords = defaults.bool(forKey: DefaultsKey.trackpadChordRemapEnabled)
            && !executableKeyboard.isEmpty
            && trusted
            && activeSession

        stopGestures()
        if wantGestures {
            startGestures(compatibilityMode: normalizedSettings.useCompatibilityTrackpadMode, reason: "")
        }

        if wantChords {
            startChordTap()
        } else {
            stopChordTap()
        }
    }

    func suspend() {
        stopGestures()
        stopChordTap()
        executorLock.withLock {
            executor?.cancel()
            executor = nil
            testExecutor?.cancel()
            testExecutor = nil
        }
    }

    func saveConfiguration() {
        var normalized = configuration
        normalized.settings = normalized.settings.normalized
        configuration = normalized
        if let data = try? TrackpadGestureKeyCodec.encodeAutomationConfiguration(normalized),
           let json = String(data: data, encoding: .utf8) {
            let defaults = UserDefaults.standard
            defaults.set(json, forKey: DefaultsKey.trackpadAutomationConfigJSON)
            defaults.set(normalized.settings.debounceMilliseconds, forKey: DefaultsKey.trackpadGestureDebounceMs)
            defaults.set(normalized.settings.diagonalRejectRatio, forKey: DefaultsKey.trackpadGestureDiagonalRejectRatio)
            defaults.set(normalized.settings.downBiasRatio, forKey: DefaultsKey.trackpadGestureDownBiasRatio)
        }
        syncWithPreferences()
    }

    func testActions(for rule: GestureAutomationRule) {
        guard !rule.actions.isEmpty, rule.actions.allSatisfy(GestureConfigurationValidator.isValid) else {
            appendError("Invalid or empty actions for \"\(rule.name)\"")
            return
        }
        if rule.actions.contains(where: { $0.kind == .keyboardShortcut }) && !AXIsProcessTrusted() {
            appendError("Accessibility permission is required to send shortcuts for \"\(rule.name)\"")
            return
        }
        let targetExecutor: GestureActionExecutor = executorLock.withLock {
            if let existing = executor { return existing }
            if let existingTest = testExecutor { return existingTest }
            let created = makeExecutor()
            testExecutor = created
            return created
        }
        if targetExecutor.execute(rule.actions, ruleName: rule.name) {
            lastTriggeredSummary = "\(rule.name) (Test)"
        }
    }

    @discardableResult
    func importLegacyConfigFromHome() -> Bool {
        importConfiguration(from: homeGestureConfigURL)
    }

    @discardableResult
    func importConfiguration(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let imported = try? TrackpadGestureKeyCodec.decodeAutomationConfiguration(data) else {
            return false
        }
        configuration = imported
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.trackpadGestureLegacyImported)
        defaults.set(true, forKey: DefaultsKey.trackpadAutomationConfigMigrated)
        saveConfiguration()
        return true
    }

    @discardableResult
    func exportConfigurationToHome() -> Bool {
        exportConfiguration(to: homeGestureConfigURL)
    }

    @discardableResult
    func exportConfiguration(to url: URL) -> Bool {
        do {
            let data = try TrackpadGestureKeyCodec.encodeAutomationConfiguration(configuration)
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            appendError("Failed to export gesture configuration: \(error.localizedDescription)")
            return false
        }
    }

    func resetToPresets() {
        configuration = .defaults
        saveConfiguration()
    }

    func resetTuningToDefaults() {
        let defaults = GestureEngineSettings()
        configuration.settings.debounceMilliseconds = defaults.debounceMilliseconds
        configuration.settings.diagonalRejectRatio = defaults.diagonalRejectRatio
        configuration.settings.downBiasRatio = defaults.downBiasRatio
        configuration.settings.spreadThreshold = defaults.spreadThreshold
        configuration.settings.minimumSwipeDistance = defaults.minimumSwipeDistance
        configuration.settings.downBiasMinimumY = defaults.downBiasMinimumY
        configuration.settings.spreadToDistanceRatio = defaults.spreadToDistanceRatio
        configuration.settings.liveTriggerDistance = defaults.liveTriggerDistance
        saveConfiguration()
    }

    // MARK: - Persistence & Migration

    private func loadStoredConfigurationOrMigrate() {
        let defaults = UserDefaults.standard
        let storedV2 = defaults.string(forKey: DefaultsKey.trackpadAutomationConfigJSON) ?? ""
        if !storedV2.isEmpty,
           let data = storedV2.data(using: .utf8),
           let decoded = try? TrackpadGestureKeyCodec.decodeAutomationConfiguration(data) {
            configuration = decoded
            defaults.set(true, forKey: DefaultsKey.trackpadAutomationConfigMigrated)
            return
        }

        // One-time migration: prefer ~/.gesture/config.json (v2 or v1) if present,
        // else migrate existing Vorssaint v1 UserDefaults rules if present, else built-in presets.
        if !defaults.bool(forKey: DefaultsKey.trackpadAutomationConfigMigrated) {
            if let homeData = try? Data(contentsOf: homeGestureConfigURL),
               let fromHome = try? TrackpadGestureKeyCodec.decodeAutomationConfiguration(homeData),
               !fromHome.rules.isEmpty {
                configuration = fromHome
                defaults.set(true, forKey: DefaultsKey.trackpadGestureLegacyImported)
                defaults.set(true, forKey: DefaultsKey.trackpadAutomationConfigMigrated)
                saveConfigurationWithoutSync()
                return
            }

            let storedG = defaults.string(forKey: DefaultsKey.trackpadGestureRulesJSON) ?? ""
            let storedC = defaults.string(forKey: DefaultsKey.trackpadChordRulesJSON) ?? ""
            let decodedG = storedG.data(using: .utf8).flatMap {
                try? JSONDecoder().decode([TrackpadGestureRule].self, from: $0)
            } ?? []
            let decodedC = storedC.data(using: .utf8).flatMap {
                try? JSONDecoder().decode([ChordRemapRule].self, from: $0)
            } ?? []

            if !decodedG.isEmpty || !decodedC.isEmpty {
                let debounce = defaults.object(forKey: DefaultsKey.trackpadGestureDebounceMs) as? Int ?? 150
                let diag = defaults.object(forKey: DefaultsKey.trackpadGestureDiagonalRejectRatio) as? Double ?? 0.95
                let downBias = defaults.object(forKey: DefaultsKey.trackpadGestureDownBiasRatio) as? Double ?? 0.35
                configuration = TrackpadGestureKeyCodec.migrateFromVorssaintLegacy(
                    gestures: decodedG,
                    chords: decodedC,
                    debounceMs: debounce,
                    diagonalRejectRatio: diag,
                    downBiasRatio: downBias
                )
                defaults.set(true, forKey: DefaultsKey.trackpadAutomationConfigMigrated)
                saveConfigurationWithoutSync()
                return
            }

            defaults.set(true, forKey: DefaultsKey.trackpadAutomationConfigMigrated)
        }

        configuration = .defaults
    }

    private func saveConfigurationWithoutSync() {
        if let data = try? TrackpadGestureKeyCodec.encodeAutomationConfiguration(configuration),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: DefaultsKey.trackpadAutomationConfigJSON)
        }
    }

    // MARK: - Trackpad Gesture Pipeline (Advanced + Public Compatibility Fallback)

    private func startGestures(compatibilityMode: Bool, reason: String) {
        guard !isGestureRunning else { return }
        recognizerLock.withLock {
            recognizer.reset()
            deviceLastTimestamps.removeAll()
            activeTrackpadDeviceID = nil
            consecutiveInvalidFrames = 0
        }

        if compatibilityMode {
            startPublicFallback(reason: reason)
            return
        }

        guard MultitouchDeviceHub.shared.isFrameworkAvailable else {
            startPublicFallback(reason: "MultitouchSupport unavailable")
            return
        }

        MultitouchDeviceHub.shared.subscribeDevice(id: "trackpadGestures") { [weak self] device, touches, count, ts in
            self?.handleMultitouchFrame(device: device, touches: touches, count: count, deviceTimestamp: ts)
        }

        if Thread.isMainThread && MultitouchDeviceHub.shared.activeDeviceCount == 0 {
            MultitouchDeviceHub.shared.unsubscribe(id: "trackpadGestures")
            startPublicFallback(reason: "No Multitouch trackpad detected")
            return
        }

        isGestureRunning = true
        trackpadBackendState = .advanced
    }

    private func startPublicFallback(reason: String) {
        MultitouchDeviceHub.shared.unsubscribe(id: "trackpadGestures")
        let provider = PublicTrackpadGestureProvider()
        provider.onGesture = { [weak self] event in
            guard let self else { return }
            _ = self.recognizerLock.withLock {
                self.handleRecognizedGestureLocked(event)
            }
        }
        if provider.start() {
            publicGestureProvider = provider
            isGestureRunning = true
            trackpadBackendState = .compatible(reason)
        } else {
            publicGestureProvider = nil
            isGestureRunning = false
            trackpadBackendState = .unavailable(reason.isEmpty ? "Public event monitor failed" : reason)
            appendError("Trackpad unavailable: \(reason)")
        }
    }

    private func stopGestures() {
        MultitouchDeviceHub.shared.unsubscribe(id: "trackpadGestures")
        publicGestureProvider?.stop()
        publicGestureProvider = nil
        recognizerLock.withLock {
            recognizer.reset()
            deviceLastTimestamps.removeAll()
            activeTrackpadDeviceID = nil
            consecutiveInvalidFrames = 0
        }
        isGestureRunning = false
        trackpadBackendState = .stopped
    }

    private func handleMultitouchFrame(device: UnsafeMutableRawPointer?,
                                       touches: UnsafeMutableRawPointer?,
                                       count: Int,
                                       deviceTimestamp: Double) {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        var fallbackReason: String?
        var touchObservationUpdate: String?

        recognizerLock.withLock {
            let deviceID = device.map { UInt(bitPattern: $0) } ?? 0
            guard deviceTimestamp.isFinite,
                  deviceTimestamp >= 0,
                  deviceTimestamp >= (deviceLastTimestamps[deviceID] ?? 0) else {
                consecutiveInvalidFrames += 1
                if consecutiveInvalidFrames >= 5 {
                    fallbackReason = "Abnormal MTContact timestamp"
                }
                return
            }
            guard count >= 0, count <= 20, count == 0 || touches != nil else {
                consecutiveInvalidFrames += 1
                if consecutiveInvalidFrames >= 5 {
                    fallbackReason = "Abnormal MTContact count (\(count))"
                }
                return
            }

            if count == 0 {
                deviceLastTimestamps[deviceID] = deviceTimestamp
                consecutiveInvalidFrames = 0
                if activeTrackpadDeviceID == deviceID {
                    recognizer.processTouches([], timestamp: nowUptime)
                    activeTrackpadDeviceID = nil
                    touchObservationUpdate = Self.prefersChineseLabels() ? "触点已全部抬起" : "All contacts lifted"
                }
                return
            }

            guard let touches else { return }
            let decodedTouches: [TrackpadActiveTouch]
            do {
                let rawBuffer = UnsafeRawBufferPointer(start: touches, count: count * MTContactDecoder.stride)
                decodedTouches = try MTContactDecoder.decode(rawBuffer, count: count)
            } catch {
                consecutiveInvalidFrames += 1
                if consecutiveInvalidFrames >= 5 {
                    fallbackReason = error.localizedDescription
                }
                return
            }

            consecutiveInvalidFrames = 0
            deviceLastTimestamps[deviceID] = deviceTimestamp
            if activeTrackpadDeviceID == nil {
                activeTrackpadDeviceID = deviceID
            }
            guard activeTrackpadDeviceID == deviceID else { return }

            recognizer.processTouches(decodedTouches, timestamp: nowUptime)

            if nowUptime - lastTouchObservationUptime >= 0.1 {
                lastTouchObservationUptime = nowUptime
                let accepted = recognizer.acceptedTouchCount
                let palms = recognizer.rejectedPalmCount
                if Self.prefersChineseLabels() {
                    var msg = "收到 \(decodedTouches.count) 个触点，手势使用 \(accepted) 指"
                    if palms > 0 { msg += "，已过滤 \(palms) 个掌缘" }
                    touchObservationUpdate = msg
                } else {
                    var msg = "\(decodedTouches.count) raw contacts · \(accepted) active fingers"
                    if palms > 0 { msg += " · \(palms) palm filtered" }
                    touchObservationUpdate = msg
                }
            }
        }

        if let fallbackReason {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isGestureRunning else { return }
                self.stopGestures()
                self.startPublicFallback(reason: fallbackReason)
            }
            return
        }

        if let touchObservationUpdate {
            DispatchQueue.main.async { [weak self] in
                self?.lastTouchObservation = touchObservationUpdate
            }
        }
    }

    private func handleRecognizedGestureLocked(_ event: TrackpadGestureEvent) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let bundleID = frontmostBundleIdentifier
        let matchedRule = TrackpadGestureRecognizer.matchingAutomationRule(
            for: event,
            in: cachedTrackpadRules,
            frontmostBundleID: bundleID
        )

        if now - lastGestureObservationUptime >= 0.2 {
            lastGestureObservationUptime = now
            let chinese = Self.prefersChineseLabels()
            let distStr = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(event.distance))
            let obs = chinese
                ? "\(event.fingers) 指 · \(event.direction.shortTitle(chinese: true)) · 距离 \(distStr)"
                : "\(event.fingers)F · \(event.direction.shortTitle(chinese: false)) · dist \(distStr)"
            DispatchQueue.main.async { [weak self] in
                self?.lastGestureObservation = obs
            }
        }

        guard let matchedRule else { return false }

        if let last = lastTriggerByRuleID[matchedRule.id], now - last < cachedDebounceSeconds {
            return true
        }
        lastTriggerByRuleID[matchedRule.id] = now
        recognizer.recordTriggeredGesture(event)
        dispatchRuleExecution(matchedRule)
        return true
    }

    // MARK: - Action Execution Dispatch

    private func rebuildExecutorIfNeeded() {
        executorLock.withLock {
            executor?.cancel()
            executor = makeExecutor()
        }
    }

    private func makeExecutor() -> GestureActionExecutor {
        let created = GestureActionExecutor()
        created.onCompletion = { [weak self] ruleName, failure in
            guard let failure else { return }
            DispatchQueue.main.async {
                self?.appendError("Rule \"\(ruleName)\" failed: \(failure)")
            }
        }
        return created
    }

    private func dispatchRuleExecution(_ rule: GestureAutomationRule) {
        if rule.actions.contains(where: { $0.kind == .keyboardShortcut }) && !AXIsProcessTrusted() {
            DispatchQueue.main.async { [weak self] in
                self?.appendError("Accessibility permission required for \"\(rule.name)\"")
            }
            return
        }
        let queued = executorLock.withLock {
            executor?.execute(rule.actions, ruleName: rule.name) ?? false
        }
        if queued {
            let timestamp = Date().formatted(date: .omitted, time: .standard)
            let summary = "\(rule.name) · \(timestamp)"
            DispatchQueue.main.async { [weak self] in
                self?.lastTriggeredSummary = summary
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendError("Action queue full; skipped \"\(rule.name)\"")
            }
        }
    }

    private func appendError(_ message: String) {
        if !errorMessages.contains(message) {
            errorMessages.append(message)
        }
    }

    private static func prefersChineseLabels() -> Bool {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.language) ?? ""
        if raw.hasPrefix("zh") { return true }
        if raw.isEmpty {
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true
        }
        return false
    }

    // MARK: - Global Keyboard Automation Tap (`HotkeyListener`)

    private func startChordTap() {
        let alreadyOpen = tapLock.withLock { chordTap != nil }
        guard !alreadyOpen else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let svc = Unmanaged<TrackpadGestureService>.fromOpaque(userInfo).takeUnretainedValue()
                return svc.handleKeyboardTapEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            appendError("Keyboard Event Tap failed to start; check Accessibility permission")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapLock.withLock {
            chordTap = tap
            chordRunLoopSource = source
            hotkeyMatcher.reset()
        }
        if let source {
            PointerTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isChordRunning = true
    }

    private func stopChordTap() {
        let (port, source) = tapLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (chordTap, chordRunLoopSource)
            chordTap = nil
            chordRunLoopSource = nil
            hotkeyMatcher.reset()
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            PointerTapRunLoop.remove(source, invalidating: port)
        }
        isChordRunning = false
    }

    private func handleKeyboardTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive && AXIsProcessTrusted() {
                if let tap = tapLock.withLock({ chordTap }) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
            let bundleID = frontmostBundleIdentifier
            let disposition = tapLock.withLock {
                hotkeyMatcher.handleKeyEvent(
                    isKeyDown: type == .keyDown,
                    keyCode: keyCode,
                    flags: event.flags,
                    isRepeat: isRepeat,
                    sourcePID: sourcePID,
                    shouldHandle: !shortcutRecordingActive,
                    frontmostBundleID: bundleID
                )
            }
            switch disposition {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .consume(let triggeredRule):
                if let rule = triggeredRule {
                    let shouldFire = recognizerLock.withLock { () -> Bool in
                        let now = ProcessInfo.processInfo.systemUptime
                        if let last = lastTriggerByRuleID[rule.id], now - last < cachedDebounceSeconds {
                            return false
                        }
                        lastTriggerByRuleID[rule.id] = now
                        return true
                    }
                    if shouldFire {
                        dispatchRuleExecution(rule)
                    }
                }
                return nil
            }
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
