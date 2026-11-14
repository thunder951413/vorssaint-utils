// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum TrackpadGestureTests {
    static func run(_ suite: TestSuite) {
        mtContactDecoderTests(suite)
        palmRejectionAndIsolatedContactTests(suite)
        swipeCoherenceAndMisfireGuardTests(suite)
        publicGestureAccumulatorTests(suite)
        automationModelsValidatorAndHotkeyTests(suite)
    }

    // MARK: - 96-Byte MTContactDecoder & TouchFrameValidator (`MTContactDecoderTests`)

    private static func mtContactDecoderTests(_ suite: TestSuite) {
        func records(count: Int) -> Data {
            var data = Data(repeating: 0, count: count * 96)
            for index in 0..<count {
                let base = index * 96
                data.withUnsafeMutableBytes { buffer in
                    buffer.storeBytes(of: Int32(index + 1), toByteOffset: base + 16, as: Int32.self)
                    buffer.storeBytes(of: Int32(4), toByteOffset: base + 20, as: Int32.self)
                    buffer.storeBytes(of: Float(index + 1) / 10, toByteOffset: base + 32, as: Float.self)
                    buffer.storeBytes(of: Float(index + 2) / 10, toByteOffset: base + 36, as: Float.self)
                    buffer.storeBytes(of: Float(0.75), toByteOffset: base + 48, as: Float.self)
                    buffer.storeBytes(of: Float(8 + index), toByteOffset: base + 60, as: Float.self)
                    buffer.storeBytes(of: Float(5 + index), toByteOffset: base + 64, as: Float.self)
                    // Offset 80 holds non-contact tail data that a wrong 64-byte stride would misread.
                    buffer.storeBytes(of: Float(73.5), toByteOffset: base + 80, as: Float.self)
                }
            }
            return data
        }

        for count in [2, 5] {
            let data = records(count: count)
            let touches = try? data.withUnsafeBytes { try MTContactDecoder.decode($0, count: count) }
            suite.expect(touches?.map(\.identifier) == Array(1...count),
                         "MTContactDecoder decodes all \(count) contacts using 96-byte arm64 stride")
            suite.expect(touches?.first?.majorAxis == 8 && touches?.first?.minorAxis == 5
                         && touches?.first?.contactSize == 0.75,
                         "MTContactDecoder reads ellipse axes and contact size proxy (\(count)F)")
        }

        let twoRecords = records(count: 2)
        let truncated = try? twoRecords.prefix(128).withUnsafeBytes {
            try MTContactDecoder.decode($0, count: 2)
        }
        suite.expect(truncated == nil, "MTContactDecoder rejects truncated buffers")

        var nanRecord = twoRecords
        nanRecord.withUnsafeMutableBytes {
            $0.storeBytes(of: Float.nan, toByteOffset: 96 + 32, as: Float.self)
        }
        let nanDecoded = try? nanRecord.withUnsafeBytes {
            try MTContactDecoder.decode($0, count: 2)
        }
        suite.expect(nanDecoded == nil, "MTContactDecoder rejects NaN coordinates")

        var noMetrics = records(count: 1)
        noMetrics.withUnsafeMutableBytes {
            $0.storeBytes(of: Float.nan, toByteOffset: 60, as: Float.self)
            $0.storeBytes(of: Float.zero, toByteOffset: 64, as: Float.self)
            $0.storeBytes(of: Float(-1), toByteOffset: 48, as: Float.self)
        }
        let plainTouch = try? noMetrics.withUnsafeBytes { try MTContactDecoder.decode($0, count: 1) }
        suite.expect(plainTouch?.count == 1
                     && plainTouch?[0].majorAxis == nil
                     && plainTouch?[0].minorAxis == nil
                     && plainTouch?[0].contactSize == nil,
                     "unavailable shape metrics fall back to nil without discarding valid coordinates")
    }

    // MARK: - PalmRejectionFilter & Isolated Contact Filter (`PalmRejectionTests` + `IsolatedContactFilterTests`)

    private static func palmRejectionAndIsolatedContactTests(_ suite: TestSuite) {
        func finger(_ id: Int, x: CGFloat, y: CGFloat = 0.5,
                    major: CGFloat = 8, minor: CGFloat = 7, size: CGFloat = 0.5,
                    state: Int = 4) -> TrackpadActiveTouch {
            TrackpadActiveTouch(identifier: id, state: state, normalizedX: x, normalizedY: y,
                                majorAxis: major, minorAxis: minor, contactSize: size)
        }

        func palm(x: CGFloat = 0.96, major: CGFloat = 21,
                  minor: CGFloat = 12, size: CGFloat = 4) -> TrackpadActiveTouch {
            finger(9, x: x, y: 0.12, major: major, minor: minor, size: size)
        }

        for scale: CGFloat in [0.01, 1, 100] {
            var filter = PalmRejectionFilter()
            let touches = [
                finger(1, x: 0.3, major: 8 * scale, minor: 7 * scale, size: 0.5 * scale),
                finger(2, x: 0.4, major: 8 * scale, minor: 7 * scale, size: 0.5 * scale),
                palm(x: 0.7, major: 21 * scale, minor: 12 * scale, size: 4 * scale),
            ]
            _ = filter.filter(touches, timestamp: 0)
            let accepted = filter.filter(touches, timestamp: 0.01).map(\.identifier)
            suite.expect(accepted == [1, 2],
                         "broad palm is rejected across device metric scales (scale=\(scale))")
        }

        // Split palm contacts rejected while preserving two-finger gesture
        let recognizer = TrackpadGestureRecognizer()
        var events: [TrackpadGestureEvent] = []
        recognizer.onGesture = { events.append($0); return true }
        for frame in 0..<16 {
            let movement = CGFloat(max(0, frame - 4)) * 0.01
            let contacts = [
                palm(),
                finger(1, x: 0.3 + movement),
                finger(2, x: 0.4 + movement),
                finger(8, x: 0.6, y: 0.2 + movement / 2, major: 21, minor: 9, size: 1.8),
            ]
            recognizer.processTouches(contacts, timestamp: Double(frame) * 0.01)
        }
        suite.expect(recognizer.rejectedPalmCount == 2,
                     "both contacts of a split palm are filtered out")
        recognizer.processTouches([], timestamp: 0.2)
        suite.expect(events.map(\.fingers) == [2] && events.map(\.direction) == [.right],
                     "remaining two real fingers still produce a clean 2-finger right swipe")

        // Isolated 3rd contact without shape data is rejected
        var isoFilter = PalmRejectionFilter()
        let rawThree = [
            TrackpadActiveTouch(identifier: 1, state: 4, normalizedX: 0.45, normalizedY: 0.75),
            TrackpadActiveTouch(identifier: 2, state: 4, normalizedX: 0.58, normalizedY: 0.78),
            TrackpadActiveTouch(identifier: 3, state: 4, normalizedX: 0.95, normalizedY: 0.15),
        ]
        _ = isoFilter.filter(rawThree, timestamp: 0)
        _ = isoFilter.filter(rawThree, timestamp: 0.008)
        suite.expect(isoFilter.filter(rawThree, timestamp: 0.016).map(\.identifier) == [1, 2],
                     "distant palm heel / resting thumb beside 2 fingers is rejected after 3 frames / 16 ms")

        // 4-finger pinch thumb is preserved even after one finger lifts
        var pinchFilter = PalmRejectionFilter()
        let thumb = TrackpadActiveTouch(identifier: 9, state: 4, normalizedX: 0.50, normalizedY: 0.05)
        let fingers = [
            TrackpadActiveTouch(identifier: 1, state: 4, normalizedX: 0.40, normalizedY: 0.60),
            TrackpadActiveTouch(identifier: 2, state: 4, normalizedX: 0.50, normalizedY: 0.65),
            TrackpadActiveTouch(identifier: 3, state: 4, normalizedX: 0.60, normalizedY: 0.60),
        ]
        for frame in 0..<5 {
            _ = pinchFilter.filter(fingers + [thumb], timestamp: Double(frame) * 0.008)
        }
        for frame in 5..<10 {
            let kept = pinchFilter.filter(Array(fingers.prefix(2)) + [thumb], timestamp: Double(frame) * 0.008)
            if frame == 9 {
                suite.expect(kept.count == 3,
                             "pinch thumb is never retroactively marked as an isolated palm")
            }
        }
    }

    // MARK: - Coherent Swipe & Misfire Guards (`SwipeGuardTests` + `MisfireGuardTests`)

    private static func swipeCoherenceAndMisfireGuardTests(_ suite: TestSuite) {
        func threeFingers(_ movement: CGFloat) -> [TrackpadActiveTouch] {
            [
                TrackpadActiveTouch(identifier: 1, state: 4, normalizedX: 0.50, normalizedY: 0.80 - movement),
                TrackpadActiveTouch(identifier: 2, state: 4, normalizedX: 0.60, normalizedY: 0.85 - movement),
                TrackpadActiveTouch(identifier: 3, state: 4, normalizedX: 0.70, normalizedY: 0.80 - movement),
            ]
        }

        func closeWindowCount(_ frames: [(Double, [TrackpadActiveTouch])]) -> Int {
            let recognizer = TrackpadGestureRecognizer()
            var count = 0
            recognizer.onGesture = { event in
                guard event.fingers == 3 && event.direction == .down && -event.dy >= 0.08 else { return false }
                count += 1
                return true
            }
            for (ts, touches) in frames {
                recognizer.processTouches(touches, timestamp: ts)
            }
            recognizer.processTouches([], timestamp: (frames.last?.0 ?? 0) + 0.01)
            return count
        }

        // Normal fast 3-finger downward swipe
        let fastSwipe = (0..<20).map { frame in
            (Double(frame) * 0.008, threeFingers(CGFloat(max(0, frame - 3)) * 0.015))
        }
        suite.expect(closeWindowCount(fastSwipe) == 1,
                     "normal fast 3-finger downward swipe triggers reliably")

        // Finger-sized stationary 3rd contact cannot trigger 3-finger swipe, emits rejectedIncoherentSwipe trace
        let stationaryThirdRecognizer = TrackpadGestureRecognizer()
        var incoherentEvents: [TrackpadGestureEvent] = []
        var traces: [GestureTrace] = []
        stationaryThirdRecognizer.onGesture = { incoherentEvents.append($0); return true }
        stationaryThirdRecognizer.onTrace = { traces.append($0) }
        for frame in 0..<30 {
            let m = CGFloat(max(0, frame - 4)) * 0.01
            stationaryThirdRecognizer.processTouches([
                TrackpadActiveTouch(identifier: 1, state: 4, normalizedX: 0.30, normalizedY: 0.80 - m),
                TrackpadActiveTouch(identifier: 2, state: 4, normalizedX: 0.40, normalizedY: 0.80 - m),
                TrackpadActiveTouch(identifier: 3, state: 4, normalizedX: 0.50, normalizedY: 0.80),
            ], timestamp: Double(frame) * 0.01)
        }
        stationaryThirdRecognizer.processTouches([], timestamp: 0.31)
        suite.expect(incoherentEvents.isEmpty
                     && traces.contains(where: { $0.decision == .rejectedIncoherentSwipe }),
                     "2 moving fingers + 1 stationary finger-sized contact are rejected as incoherent")

        // Mid-gesture contact landing during moving 3-finger swipe does not upgrade it to 4 fingers
        let lateContactFrames = (0..<60).map { frame -> (Double, [TrackpadActiveTouch]) in
            let movement = CGFloat(max(0, frame - 3)) * 0.004
            var touches = threeFingers(movement)
            if frame >= 20 {
                touches.append(TrackpadActiveTouch(identifier: 4, state: 4, normalizedX: 0.62, normalizedY: 0.60 - movement * 0.2))
            }
            return (Double(frame) * 0.008, touches)
        }
        suite.expect(closeWindowCount(lateContactFrames) == 1,
                     "late contact landing mid-swipe does not corrupt an active 3-finger swipe")

        // Brief brush contact during 3-finger swipe recovers cleanly
        let brushFrames = (0..<60).map { frame -> (Double, [TrackpadActiveTouch]) in
            var touches = threeFingers(CGFloat(max(0, frame - 4)) * 0.004)
            if (7..<13).contains(frame) {
                touches.append(TrackpadActiveTouch(identifier: 4, state: 4, normalizedX: 0.62, normalizedY: 0.62))
            }
            return (Double(frame) * 0.008, touches)
        }
        suite.expect(closeWindowCount(brushFrames) == 1,
                     "brief brush contact departing quickly does not freeze the 3-finger swipe")

        // Resting hand slow drift rebases stillness anchor without misfiring
        let slowDriftFrames = (0..<180).map { frame -> (Double, [TrackpadActiveTouch]) in
            let timestamp = Double(frame) * 0.008
            let movement: Double
            switch timestamp {
            case ..<0.2: movement = 0
            case ..<0.45: movement = (timestamp - 0.2) / 0.25 * 0.045
            case ..<1.05: movement = 0.045
            case ..<1.3: movement = 0.045 + (timestamp - 1.05) / 0.25 * 0.045
            default: movement = 0.09
            }
            return (timestamp, threeFingers(CGFloat(movement)))
        }
        suite.expect(closeWindowCount(slowDriftFrames) == 0,
                     "resting hand slow drift separated by stillness rebase does not accumulate into a swipe")

        // 4-finger pinch recognition
        let pinchRecognizer = TrackpadGestureRecognizer()
        var pinchCaptured: TrackpadGestureEvent?
        pinchRecognizer.onGesture = { pinchCaptured = $0; return true }
        for frame in 0..<15 {
            let t = CGFloat(max(0, frame - 3)) / 11.0
            let spread: CGFloat = 0.22 * (1.0 - 0.65 * t)
            pinchRecognizer.processTouches([
                TrackpadActiveTouch(identifier: 1, state: 4, normalizedX: 0.50 - spread, normalizedY: 0.50 + spread),
                TrackpadActiveTouch(identifier: 2, state: 4, normalizedX: 0.50 + spread, normalizedY: 0.50 + spread),
                TrackpadActiveTouch(identifier: 3, state: 4, normalizedX: 0.50 + spread, normalizedY: 0.50 - spread),
                TrackpadActiveTouch(identifier: 4, state: 4, normalizedX: 0.50 - spread, normalizedY: 0.50 - spread),
            ], timestamp: Double(frame) * 0.01)
        }
        pinchRecognizer.processTouches([], timestamp: 0.20)
        suite.expect(pinchCaptured?.fingers == 4 && pinchCaptured?.direction == .pinch,
                     "4-finger inward pinch is recognized accurately")
    }

    // MARK: - PublicGestureAccumulator (`PublicGestureProvider` Compatibility Mode)

    private static func publicGestureAccumulatorTests(_ suite: TestSuite) {
        var acc = PublicGestureAccumulator()
        suite.expect(acc.scroll(dx: 0, dy: -0.05, phase: .began) == nil,
                     "scroll accumulator waits until gesture ends")
        suite.expect(acc.scroll(dx: 0, dy: -0.15, phase: .changed) == nil,
                     "scroll accumulator accumulates changed phases")
        let scrollResult = acc.scroll(dx: 0, dy: -0.05, phase: .ended)
        suite.expect(scrollResult?.fingers == 2 && scrollResult?.direction == .down,
                     "2-finger compatibility scroll emits swipe event on phase ended")
        suite.expect(acc.scroll(dx: 0, dy: -0.30, phase: [], momentum: .changed) == nil,
                     "momentum scroll events are ignored in compatibility mode")

        _ = acc.magnify(0.05, phase: .began)
        let magResult = acc.magnify(0.15, phase: .ended)
        suite.expect(magResult?.fingers == 2 && magResult?.direction == .spread,
                     "2-finger compatibility magnify emits spread event")
    }

    // MARK: - Schema v2 Models, Validator & Hotkey Matcher (`AutomationModelsTests` + `HotkeyListenerTests`)

    private static func automationModelsValidatorAndHotkeyTests(_ suite: TestSuite) {
        // Schema v2 round-trip
        let original = GestureAutomationConfiguration.defaults
        let encoded = try? TrackpadGestureKeyCodec.encodeAutomationConfiguration(original)
        let decoded = encoded.flatMap { try? TrackpadGestureKeyCodec.decodeAutomationConfiguration($0) }
        suite.expect(decoded == original,
                     "Schema v2 GestureAutomationConfiguration round-trips losslessly")

        // Legacy Schema v1 ~/.gesture/config.json migration to Schema v2
        let legacyJSON = """
        {
          "gestures": [
            { "name": "三指下滑关闭窗口", "fingers": 3, "direction": "down", "minDistance": 0.22, "keys": ["cmd", "w"] }
          ],
          "hotkeys": [
            { "name": "Cmd+H → Left", "when": ["cmd", "h"], "send": ["left"] }
          ],
          "settings": {
            "debounceMs": 180,
            "diagonalRejectRatio": 0.92,
            "downBiasRatio": 0.35
          }
        }
        """.data(using: .utf8)!
        let migrated = try? TrackpadGestureKeyCodec.decodeAutomationConfiguration(legacyJSON)
        suite.expect(migrated?.schemaVersion == 2
                     && migrated?.rules.count == 2
                     && migrated?.settings.debounceMilliseconds == 180,
                     "legacy ~/.gesture/config.json migrates directly into Schema v2 GestureAutomationConfiguration")

        // App scope matching & overlap detection
        let safariScope = GestureAppScope(mode: .include, bundleIdentifiers: ["com.apple.Safari"])
        let noSafariScope = GestureAppScope(mode: .exclude, bundleIdentifiers: ["com.apple.Safari"])
        suite.expect(safariScope.matches(bundleIdentifier: "com.apple.Safari")
                     && !safariScope.matches(bundleIdentifier: "com.apple.Terminal")
                     && !noSafariScope.matches(bundleIdentifier: "com.apple.Safari")
                     && noSafariScope.matches(bundleIdentifier: "com.apple.Terminal")
                     && !safariScope.overlaps(noSafariScope),
                     "GestureAppScope include/exclude matching and disjoint overlap check work accurately")

        // ConfigurationValidator warnings
        var invalidConfig = GestureAutomationConfiguration.defaults
        invalidConfig.rules[0].actions = []
        var dup = invalidConfig.rules[1]
        dup.id = UUID()
        dup.name = "Duplicate Left"
        invalidConfig.rules.append(dup)
        invalidConfig.settings.useCompatibilityTrackpadMode = true
        let warnings = GestureConfigurationValidator.warnings(for: invalidConfig, chinese: false)
        suite.expect(warnings.contains { $0.contains("no actions") }
                     && warnings.contains { $0.contains("same trigger") }
                     && warnings.contains { $0.contains("Advanced Trackpad Mode") },
                     "GestureConfigurationValidator surfaces empty-action, duplicate-trigger, and compatibility warnings")

        // KeyboardShortcut fn-stripping on arrow/function keys & aliases
        suite.expect(GestureKeyboardShortcut(keys: ["command", "enter"]) == GestureKeyboardShortcut(keys: ["cmd", "return"]),
                     "GestureKeyboardShortcut normalizes key aliases")
        suite.expect(GestureKeyboardShortcut(keys: ["cmd", "up"])?.matches(
            keyCode: 126,
            flags: [.maskCommand, .maskSecondaryFn, .maskNumericPad]
        ) == true, "GestureKeyboardShortcut strips intrinsic macOS maskSecondaryFn on arrow keys")
        suite.expect(GestureKeyboardShortcut(keys: ["j"])?.matches(keyCode: 38, flags: .maskSecondaryFn) == false
                     && GestureKeyboardShortcut(keys: ["fn", "j"])?.matches(keyCode: 38, flags: .maskSecondaryFn) == true,
                     "GestureKeyboardShortcut preserves explicit fn modifier on regular letter keys")

        // Stateful HotkeyMatcher: keyUp after modifier release, repeat, recording pass-through, own PID ignore
        let keyUpRule = GestureAutomationRule(
            name: "KeyUp Rule",
            trigger: .keyboard(KeyboardTriggerSpec(keys: ["cmd", "j"], phase: .keyUp, allowRepeat: false)),
            actions: [.keyboard(["down"])]
        )
        let matcher = GestureHotkeyMatcher(rules: [keyUpRule], ownPID: 9999)
        suite.expect(matcher.handleKeyEvent(
            isKeyDown: true, keyCode: 38, flags: .maskCommand, isRepeat: false,
            sourcePID: 9999, shouldHandle: true, frontmostBundleID: nil
        ) == .passThrough, "own synthetic PID events pass through untouched")

        suite.expect(matcher.handleKeyEvent(
            isKeyDown: true, keyCode: 38, flags: .maskCommand, isRepeat: false,
            sourcePID: 100, shouldHandle: false, frontmostBundleID: nil
        ) == .passThrough, "shortcut recording passes physical key presses through")

        suite.expect(matcher.handleKeyEvent(
            isKeyDown: true, keyCode: 38, flags: .maskCommand, isRepeat: false,
            sourcePID: 100, shouldHandle: true, frontmostBundleID: nil
        ) == .consume(triggered: nil), "keyUp rule consumes keyDown without firing prematurely")

        // Release Cmd before releasing J — keyUp still remembers and triggers!
        suite.expect(matcher.handleKeyEvent(
            isKeyDown: false, keyCode: 38, flags: [], isRepeat: false,
            sourcePID: 100, shouldHandle: true, frontmostBundleID: nil
        ) == .consume(triggered: keyUpRule), "keyUp rule triggers cleanly even after modifier was released first")
    }
}
