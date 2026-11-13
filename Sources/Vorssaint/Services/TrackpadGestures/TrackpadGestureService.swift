// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import Foundation
import IOKit

private func multitouchHubContactCallback(_ device: UnsafeMutableRawPointer?,
                                          _ touches: UnsafeMutableRawPointer?,
                                          _ count: Int32,
                                          _ timestamp: Double,
                                          _ frame: Int32) -> Int32 {
    MultitouchDeviceHub.shared.dispatchFrame(touches: touches, count: Int(count), timestamp: timestamp)
    return 0
}

/// Shared MultitouchSupport multiplexer so `MiddleClickService` and
/// `TrackpadGestureService` coexist in the same process across all connected
/// trackpads (built-in + Magic Trackpad) with automatic wake/hotplug recovery.
final class MultitouchDeviceHub: @unchecked Sendable {
    static let shared = MultitouchDeviceHub()

    typealias FrameConsumer = (UnsafeMutableRawPointer?, Int, Double) -> Void

    private typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback?) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW
    )
    private static let createListFn: CreateListFn? = symbol("MTDeviceCreateList")
    private static let registerFn: RegisterFn? = symbol("MTRegisterContactFrameCallback")
    private static let startFn: StartFn? = symbol("MTDeviceStart")
    private static let stopFn: StopFn? = symbol("MTDeviceStop")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    private let lock = NSLock()
    private var consumers: [String: FrameConsumer] = [:]
    private var deviceList: CFArray?
    private var observers: [NSObjectProtocol] = []
    private var hotplugPort: IONotificationPortRef?
    private var hotplugIterator: io_iterator_t = 0
    private var resolvedTouchStride: Int?

    private init() {}

    func subscribe(id: String, consumer: @escaping FrameConsumer) {
        let shouldStart: Bool = lock.withLock {
            let wasEmpty = consumers.isEmpty
            consumers[id] = consumer
            return wasEmpty
        }
        if shouldStart {
            DispatchQueue.main.async { [weak self] in
                self?.ensureStartedOnMain()
            }
        }
        ensureStartedIfOnMain()
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

    fileprivate func dispatchFrame(touches: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        let snapshot = lock.withLock { Array(consumers.values) }
        for consumer in snapshot {
            consumer(touches, count, timestamp)
        }
    }

    /// Reads active touches with adaptive stride detection (64-byte arm64 macOS 26
    /// layout vs 96-byte classic layout) validated on the first multi-finger frame.
    func extractActiveTouches(touches: UnsafeMutableRawPointer?, count: Int) -> [TrackpadActiveTouch] {
        guard let touches, count > 0, count <= 20 else { return [] }
        let stride: Int = lock.withLock {
            if let existing = resolvedTouchStride { return existing }
            guard count >= 2 else { return 64 }
            for candidate in [64, 96, 88, 80, 72] {
                if Self.strideLooksValid(touches: touches, count: count, stride: candidate) {
                    resolvedTouchStride = candidate
                    return candidate
                }
            }
            return 64
        }

        var output: [TrackpadActiveTouch] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            let base = touches.advanced(by: index * stride)
            let ident = Int(base.loadUnaligned(fromByteOffset: 16, as: Int32.self))
            let state = Int(base.loadUnaligned(fromByteOffset: 20, as: Int32.self))
            let x = base.loadUnaligned(fromByteOffset: 32, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: 36, as: Float.self)
            guard x.isFinite, y.isFinite,
                  x >= -0.25, x <= 1.25, y >= -0.25, y <= 1.25 else { continue }
            output.append(TrackpadActiveTouch(
                identifier: ident,
                state: state,
                normalizedX: CGFloat(x),
                normalizedY: CGFloat(y)
            ))
        }
        return output
    }

    private static func strideLooksValid(touches: UnsafeMutableRawPointer, count: Int, stride: Int) -> Bool {
        for index in 0..<count {
            let base = touches.advanced(by: index * stride)
            let ident = base.loadUnaligned(fromByteOffset: 16, as: Int32.self)
            let state = base.loadUnaligned(fromByteOffset: 20, as: Int32.self)
            let x = base.loadUnaligned(fromByteOffset: 32, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: 36, as: Float.self)
            guard ident >= 0, ident < 100_000,
                  state >= 0, state <= 12,
                  x.isFinite, y.isFinite,
                  x >= -0.2, x <= 1.2, y >= -0.2, y <= 1.2 else {
                return false
            }
        }
        return true
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
              let registerFn = Self.registerFn,
              let startFn = Self.startFn,
              let list = createFn()?.takeRetainedValue(),
              CFArrayGetCount(list) > 0 else { return }
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            registerFn(dev, multitouchHubContactCallback)
            startFn(dev, 0)
        }
    }

    private func stopDevices() {
        guard let list = deviceList else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            Self.stopFn?(dev)
            Self.registerFn?(dev, nil)
        }
        deviceList = nil
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

/// Native Vorssaint service hosting `mac_gesture` multi-touch swipes/pinches
/// and global chord key remapping (`HotkeyListener`).
final class TrackpadGestureService: ObservableObject {
    static let shared = TrackpadGestureService()

    @Published private(set) var isGestureRunning = false
    @Published private(set) var isChordRunning = false
    @Published private(set) var lastTriggeredSummary = ""
    @Published var gestureRules: [TrackpadGestureRule] = []
    @Published var chordRules: [ChordRemapRule] = []

    private let recognizerLock = NSLock()
    private let recognizer = TrackpadGestureRecognizer()
    private var cachedGestureRules: [TrackpadGestureRule] = []
    private var cachedDownBiasRatio: Double = 0.35
    private var cachedDebounceSeconds: TimeInterval = 0.15
    private var lastTriggerByRuleID: [UUID: TimeInterval] = [:]

    private let tapLock = NSLock()
    private var chordTap: CFMachPort?
    private var chordRunLoopSource: CFRunLoopSource?
    private var activeFlags: CGEventFlags = []
    private var cachedChordRules: [ChordRemapRule] = []
    private let myPID: pid_t = getpid()

    private static let relevantMods: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn,
    ]

    private init() {
        loadStoredRulesOrMigrateLegacy()
        recognizer.onGesture = { [weak self] event in
            self?.handleRecognizedGesture(event) ?? false
        }
        SessionActivity.shared.onChange { [weak self] active in
            if active {
                self?.syncWithPreferences()
            } else {
                self?.suspend()
            }
        }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let debounceMs = min(max(defaults.integer(forKey: DefaultsKey.trackpadGestureDebounceMs), 0), 2_000)
        let downBias = defaults.object(forKey: DefaultsKey.trackpadGestureDownBiasRatio) as? Double ?? 0.35
        let diagReject = defaults.object(forKey: DefaultsKey.trackpadGestureDiagonalRejectRatio) as? Double ?? 0.95

        recognizerLock.withLock {
            recognizer.diagonalRejectRatio = min(max(diagReject, 0.2), 1.0)
            recognizer.downBiasRatio = min(max(downBias, 0.05), 1.0)
            cachedDownBiasRatio = recognizer.downBiasRatio
            cachedDebounceSeconds = TimeInterval(debounceMs) / 1000.0
            cachedGestureRules = gestureRules
        }
        tapLock.withLock {
            cachedChordRules = chordRules
        }

        let trusted = AXIsProcessTrusted()
        let activeSession = SessionActivity.shared.isActive
        let wantGestures = defaults.bool(forKey: DefaultsKey.trackpadGesturesEnabled) && trusted && activeSession
        let wantChords = defaults.bool(forKey: DefaultsKey.trackpadChordRemapEnabled) && trusted && activeSession

        if wantGestures {
            startGestures()
        } else {
            stopGestures()
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
    }

    func saveRules() {
        if let gData = try? JSONEncoder().encode(gestureRules),
           let gStr = String(data: gData, encoding: .utf8) {
            UserDefaults.standard.set(gStr, forKey: DefaultsKey.trackpadGestureRulesJSON)
        }
        if let cData = try? JSONEncoder().encode(chordRules),
           let cStr = String(data: cData, encoding: .utf8) {
            UserDefaults.standard.set(cStr, forKey: DefaultsKey.trackpadChordRulesJSON)
        }
        syncWithPreferences()
    }

    @discardableResult
    func importLegacyConfigFromHome() -> Bool {
        let path = NSString(string: "~/.gesture/config.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let imported = TrackpadGestureKeyCodec.decodeLegacyConfigJSON(data) else {
            return false
        }
        let defaults = UserDefaults.standard
        defaults.set(imported.debounceMs, forKey: DefaultsKey.trackpadGestureDebounceMs)
        defaults.set(imported.diagonalRejectRatio, forKey: DefaultsKey.trackpadGestureDiagonalRejectRatio)
        defaults.set(imported.downBiasRatio, forKey: DefaultsKey.trackpadGestureDownBiasRatio)
        defaults.set(true, forKey: DefaultsKey.trackpadGestureLegacyImported)
        if !imported.gestures.isEmpty {
            gestureRules = imported.gestures
        }
        if !imported.hotkeys.isEmpty {
            chordRules = imported.hotkeys
        }
        saveRules()
        return true
    }

    func resetToPresets() {
        gestureRules = TrackpadGestureKeyCodec.defaultGestureRules
        chordRules = TrackpadGestureKeyCodec.defaultChordRules
        UserDefaults.standard.set(150, forKey: DefaultsKey.trackpadGestureDebounceMs)
        UserDefaults.standard.set(0.95, forKey: DefaultsKey.trackpadGestureDiagonalRejectRatio)
        UserDefaults.standard.set(0.35, forKey: DefaultsKey.trackpadGestureDownBiasRatio)
        saveRules()
    }

    // MARK: - Persistence & Migration

    private func loadStoredRulesOrMigrateLegacy() {
        let defaults = UserDefaults.standard
        let storedG = defaults.string(forKey: DefaultsKey.trackpadGestureRulesJSON) ?? ""
        let storedC = defaults.string(forKey: DefaultsKey.trackpadChordRulesJSON) ?? ""

        if let data = storedG.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TrackpadGestureRule].self, from: data),
           !decoded.isEmpty {
            gestureRules = decoded
        } else {
            gestureRules = TrackpadGestureKeyCodec.defaultGestureRules
        }

        if let data = storedC.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ChordRemapRule].self, from: data),
           !decoded.isEmpty {
            chordRules = decoded
        } else {
            chordRules = TrackpadGestureKeyCodec.defaultChordRules
        }

        if !defaults.bool(forKey: DefaultsKey.trackpadGestureLegacyImported) {
            _ = importLegacyConfigFromHome()
            defaults.set(true, forKey: DefaultsKey.trackpadGestureLegacyImported)
        }
    }

    // MARK: - Multitouch Gesture Pipeline

    private func startGestures() {
        guard !isGestureRunning else { return }
        recognizerLock.withLock { recognizer.reset() }
        MultitouchDeviceHub.shared.subscribe(id: "trackpadGestures") { [weak self] touches, count, timestamp in
            guard let self else { return }
            let activeTouches = MultitouchDeviceHub.shared.extractActiveTouches(touches: touches, count: count)
            self.recognizerLock.withLock {
                self.recognizer.processTouches(activeTouches, timestamp: timestamp)
            }
        }
        isGestureRunning = true
    }

    private func stopGestures() {
        guard isGestureRunning else { return }
        MultitouchDeviceHub.shared.unsubscribe(id: "trackpadGestures")
        recognizerLock.withLock { recognizer.reset() }
        isGestureRunning = false
    }

    private func handleRecognizedGesture(_ event: TrackpadGestureEvent) -> Bool {
        // Already under `recognizerLock` inside `processTouches`.
        guard let rule = TrackpadGestureRecognizer.matchingRule(
            for: event,
            in: cachedGestureRules,
            downBiasRatio: cachedDownBiasRatio
        ) else {
            return false
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastTriggerByRuleID[rule.id], now - last < cachedDebounceSeconds {
            return false
        }
        lastTriggerByRuleID[rule.id] = now

        let keys = rule.keys
        let summary = "\(rule.name) (\(keys.joined(separator: "+")))"
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            if self.postSimulatedChord(keys: keys) {
                DispatchQueue.main.async {
                    self.lastTriggeredSummary = summary
                }
            }
        }
        return true
    }

    // MARK: - Key Synthesis (`KeySimulator` + `HotkeyListener` replacement)

    private func postSimulatedChord(keys: [String]) -> Bool {
        let (modifiers, regularKeys) = TrackpadGestureKeyCodec.classifyKeys(keys)
        guard !regularKeys.isEmpty, AXIsProcessTrusted() else { return false }

        var modCodes: [CGKeyCode] = []
        for mod in modifiers {
            guard let code = TrackpadGestureKeyCodec.modKeyCode(name: mod) else { return false }
            modCodes.append(code)
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for code in modCodes {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return false }
            down.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(myPID))
            down.post(tap: .cghidEventTap)
            usleep(6_000)
        }
        for key in regularKeys {
            guard let code = TrackpadGestureKeyCodec.keyCodeFor(name: key),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
                continue
            }
            down.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(myPID))
            up.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(myPID))
            down.post(tap: .cghidEventTap)
            usleep(10_000)
            up.post(tap: .cghidEventTap)
            usleep(6_000)
        }
        for code in modCodes.reversed() {
            guard let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { continue }
            up.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(myPID))
            up.post(tap: .cghidEventTap)
            usleep(6_000)
        }
        return true
    }

    // MARK: - Global Chord Remap (`HotkeyListener`)

    private func startChordTap() {
        let alreadyOpen = tapLock.withLock { chordTap != nil }
        guard !alreadyOpen else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let svc = Unmanaged<TrackpadGestureService>.fromOpaque(userInfo).takeUnretainedValue()
                return svc.handleChordEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapLock.withLock {
            chordTap = tap
            chordRunLoopSource = source
            activeFlags = []
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
            activeFlags = []
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

    private func handleChordEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive && AXIsProcessTrusted() {
                if let tap = tapLock.withLock({ chordTap }) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(myPID) {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .flagsChanged:
            tapLock.withLock { activeFlags = event.flags }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let (flags, rules) = tapLock.withLock { (activeFlags, cachedChordRules) }
            let currentMods = flags.intersection(Self.relevantMods)
            for rule in rules where rule.isEnabled {
                let (mods, regular) = TrackpadGestureKeyCodec.classifyKeys(rule.whenKeys)
                guard regular.count == 1,
                      let targetCode = TrackpadGestureKeyCodec.keyCodeFor(name: regular[0]),
                      targetCode == keyCode,
                      TrackpadGestureKeyCodec.modifierFlags(for: mods) == currentMods else {
                    continue
                }
                postCleanReplacement(keys: rule.sendKeys)
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func postCleanReplacement(keys: [String]) {
        let (mods, regularKeys) = TrackpadGestureKeyCodec.classifyKeys(keys)
        guard !regularKeys.isEmpty, AXIsProcessTrusted() else { return }
        let flags = TrackpadGestureKeyCodec.modifierFlags(for: mods)
        let source = CGEventSource(stateID: .privateState)
        for key in regularKeys {
            guard let code = TrackpadGestureKeyCodec.keyCodeFor(name: key),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
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
    }
}
