// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum TrackpadGestureDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case up
    case down
    case left
    case right
    case pinch
    case spread

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .up: return "Swipe Up"
        case .down: return "Swipe Down"
        case .left: return "Swipe Left"
        case .right: return "Swipe Right"
        case .pinch: return "Pinch In"
        case .spread: return "Spread Out"
        }
    }
}

struct TrackpadActiveTouch: Equatable, Sendable {
    let identifier: Int
    let state: Int
    let normalizedX: CGFloat
    let normalizedY: CGFloat
}

struct TrackpadGestureEvent: Equatable, Sendable {
    let fingers: Int
    let direction: TrackpadGestureDirection
    let distance: CGFloat
    let dx: CGFloat
    let dy: CGFloat
}

struct TrackpadGestureRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    var fingers: Int
    var direction: TrackpadGestureDirection
    var minDistance: Double
    var keys: [String]

    init(id: UUID = UUID(),
         isEnabled: Bool = true,
         name: String,
         fingers: Int,
         direction: TrackpadGestureDirection,
         minDistance: Double,
         keys: [String]) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.fingers = min(max(fingers, 2), 5)
        self.direction = direction
        self.minDistance = min(max(minDistance, 0.05), 0.65)
        self.keys = keys
    }

    var keysDisplayString: String {
        keys.joined(separator: "+")
    }
}

struct ChordRemapRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    var whenKeys: [String]
    var sendKeys: [String]

    init(id: UUID = UUID(),
         isEnabled: Bool = true,
         name: String,
         whenKeys: [String],
         sendKeys: [String]) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.whenKeys = whenKeys
        self.sendKeys = sendKeys
    }

    var whenDisplayString: String { whenKeys.joined(separator: "+") }
    var sendDisplayString: String { sendKeys.joined(separator: "+") }
}

/// Pure multi-touch swipe/pinch/spread recognizer ported from `mac_gesture`
/// (`GestureRecognizer.swift` + `GestureDaemon.swift`).
final class TrackpadGestureRecognizer {
    private static let extraFingerConfirmFrames = 3
    private static let extraFingerConfirmDuration: Double = 0.018

    private var activeTouches: [Int: TrackpadActiveTouch] = [:]
    private var gestureStartCentroid: CGPoint?
    private var currentCentroid: CGPoint = .zero
    private var maxGestureDx: CGFloat = 0
    private var maxGestureDy: CGFloat = 0
    private var maxGestureDistance: CGFloat = 0
    private var maxFingersSeen = 0
    private var gestureFingers = 0
    private var startSpread: CGFloat = 0
    private var endSpread: CGFloat = 0
    private var didTriggerCurrentGesture = false
    private var lastObservedFingerCount = 0
    private var lastObservedFingerTimestamp: Double = 0
    private var observedFingerFrames = 0

    var onGesture: ((TrackpadGestureEvent) -> Bool)?
    var diagonalRejectRatio: Double = 0.95
    var downBiasRatio: Double = 0.35
    var liveTriggerDistance: CGFloat = 0.06

    func processTouches(_ touches: [TrackpadActiveTouch], timestamp: Double) {
        let activeSet = Set(touches.map(\.identifier))
        let prevCount = activeTouches.count

        activeTouches = activeTouches.filter { activeSet.contains($0.key) }
        for touch in touches {
            activeTouches[touch.identifier] = touch
        }

        let nowCount = activeTouches.count
        updateObservedFingerCount(nowCount, timestamp: timestamp)
        let effectiveCount = effectiveFingerCount(for: nowCount, timestamp: timestamp)
        maxFingersSeen = max(maxFingersSeen, effectiveCount)

        if nowCount == 0 && prevCount > 0 {
            evaluateGesture(fingers: gestureFingers > 0 ? gestureFingers : maxFingersSeen)
            reset()
            return
        }

        guard effectiveCount >= 2 else {
            if nowCount == 0 { reset() }
            return
        }

        // Freeze centroid when one finger lifts slightly earlier than the others.
        if gestureFingers > 0 && nowCount < gestureFingers {
            return
        }

        updateCentroid()
        if gestureStartCentroid == nil {
            gestureStartCentroid = currentCentroid
            startSpread = calculateSpread()
            resetMaxGestureDisplacement()
        }
        if effectiveCount > gestureFingers && !didTriggerCurrentGesture {
            gestureFingers = effectiveCount
            gestureStartCentroid = currentCentroid
            startSpread = calculateSpread()
            resetMaxGestureDisplacement()
        }

        updateMaxGestureDisplacement()
        endSpread = calculateSpread()

        if !didTriggerCurrentGesture,
           let event = recognizeGesture(fingers: gestureFingers),
           event.distance >= liveTriggerDistance {
            didTriggerCurrentGesture = onGesture?(event) == true
        }
    }

    func reset() {
        activeTouches.removeAll()
        gestureStartCentroid = nil
        currentCentroid = .zero
        resetMaxGestureDisplacement()
        maxFingersSeen = 0
        gestureFingers = 0
        startSpread = 0
        endSpread = 0
        didTriggerCurrentGesture = false
        lastObservedFingerCount = 0
        lastObservedFingerTimestamp = 0
        observedFingerFrames = 0
    }

    private func evaluateGesture(fingers: Int) {
        guard !didTriggerCurrentGesture,
              let event = recognizeGesture(fingers: fingers) else { return }
        didTriggerCurrentGesture = onGesture?(event) == true
    }

    private func recognizeGesture(fingers: Int) -> TrackpadGestureEvent? {
        guard fingers >= 2, let start = gestureStartCentroid else { return nil }

        let currentDx = currentCentroid.x - start.x
        let currentDy = currentCentroid.y - start.y
        let currentDistance = sqrt(currentDx * currentDx + currentDy * currentDy)

        let dx = maxGestureDistance > currentDistance ? maxGestureDx : currentDx
        let dy = maxGestureDistance > currentDistance ? maxGestureDy : currentDy
        let totalDistance = max(maxGestureDistance, currentDistance)

        let spreadDelta = endSpread - startSpread
        let spreadSignificant = abs(spreadDelta) > 0.03

        var direction: TrackpadGestureDirection
        if fingers >= 4 && spreadSignificant && abs(spreadDelta) > totalDistance * 2 {
            direction = spreadDelta > 0 ? .spread : .pinch
        } else if totalDistance > 0.01 {
            let absDx = abs(dx)
            let absDy = abs(dy)
            let minor = min(absDx, absDy)
            let major = max(absDx, absDy)

            if major > 0 && minor >= major * CGFloat(diagonalRejectRatio) {
                return nil
            }
            if absDx > absDy {
                direction = dx > 0 ? .right : .left
            } else {
                direction = dy > 0 ? .up : .down
            }
            if (direction == .left || direction == .right)
                && dy < 0
                && absDy > absDx * CGFloat(downBiasRatio)
                && absDy > 0.08 {
                direction = .down
            }
        } else {
            return nil
        }

        return TrackpadGestureEvent(
            fingers: fingers,
            direction: direction,
            distance: totalDistance,
            dx: dx,
            dy: dy
        )
    }

    private func updateObservedFingerCount(_ count: Int, timestamp: Double) {
        if count != lastObservedFingerCount {
            lastObservedFingerCount = count
            lastObservedFingerTimestamp = timestamp
            observedFingerFrames = count > 0 ? 1 : 0
        } else if count > 0 {
            observedFingerFrames += 1
        }
    }

    private func effectiveFingerCount(for nowCount: Int, timestamp: Double) -> Int {
        guard gestureFingers > 0, nowCount > gestureFingers else { return nowCount }
        let heldFrames = observedFingerFrames >= Self.extraFingerConfirmFrames
        let heldDuration = (timestamp - lastObservedFingerTimestamp) >= Self.extraFingerConfirmDuration
        return (heldFrames || heldDuration) ? nowCount : gestureFingers
    }

    private func updateCentroid() {
        guard !activeTouches.isEmpty else { return }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for touch in activeTouches.values {
            sumX += touch.normalizedX
            sumY += touch.normalizedY
        }
        let n = CGFloat(activeTouches.count)
        currentCentroid = CGPoint(x: sumX / n, y: sumY / n)
    }

    private func updateMaxGestureDisplacement() {
        guard let start = gestureStartCentroid else { return }
        let dx = currentCentroid.x - start.x
        let dy = currentCentroid.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        if distance >= maxGestureDistance {
            maxGestureDx = dx
            maxGestureDy = dy
            maxGestureDistance = distance
        }
    }

    private func resetMaxGestureDisplacement() {
        maxGestureDx = 0
        maxGestureDy = 0
        maxGestureDistance = 0
    }

    private func calculateSpread() -> CGFloat {
        guard activeTouches.count >= 2 else { return 0 }
        let c = currentCentroid
        var totalDist: CGFloat = 0
        for touch in activeTouches.values {
            let dx = touch.normalizedX - c.x
            let dy = touch.normalizedY - c.y
            totalDist += sqrt(dx * dx + dy * dy)
        }
        return totalDist / CGFloat(activeTouches.count)
    }

    static func matchingRule(for event: TrackpadGestureEvent,
                             in rules: [TrackpadGestureRule],
                             downBiasRatio: Double) -> TrackpadGestureRule? {
        for rule in rules where rule.isEnabled {
            guard rule.fingers == event.fingers else { continue }
            let flexibleDown = rule.direction == .down
                && event.dy < 0
                && max(0, -event.dy) >= CGFloat(rule.minDistance)
                && abs(event.dy) >= abs(event.dx) * CGFloat(downBiasRatio)
            guard rule.direction == event.direction || flexibleDown else { continue }
            let distOK: Bool
            if rule.direction == .down {
                distOK = event.dy < 0 && max(0, -event.dy) >= CGFloat(rule.minDistance)
            } else {
                distOK = event.distance >= CGFloat(rule.minDistance)
            }
            if distOK {
                return rule
            }
        }
        return nil
    }
}

enum TrackpadGestureKeyCodec {
    static let defaultGestureRules: [TrackpadGestureRule] = [
        TrackpadGestureRule(name: "Close Window", fingers: 3, direction: .down, minDistance: 0.22, keys: ["cmd", "w"]),
        TrackpadGestureRule(name: "Navigate Back", fingers: 3, direction: .left, minDistance: 0.15, keys: ["cmd", "["]),
        TrackpadGestureRule(name: "Navigate Forward", fingers: 3, direction: .right, minDistance: 0.15, keys: ["cmd", "]"]),
        TrackpadGestureRule(name: "Reload Page", fingers: 3, direction: .up, minDistance: 0.15, keys: ["cmd", "r"]),
        TrackpadGestureRule(name: "Hide Application", fingers: 4, direction: .down, minDistance: 0.14, keys: ["cmd", "h"]),
    ]

    static let defaultChordRules: [ChordRemapRule] = [
        ChordRemapRule(name: "Cmd+H → Left", whenKeys: ["cmd", "h"], sendKeys: ["left"]),
        ChordRemapRule(name: "Cmd+J → Down", whenKeys: ["cmd", "j"], sendKeys: ["down"]),
        ChordRemapRule(name: "Cmd+K → Up", whenKeys: ["cmd", "k"], sendKeys: ["up"]),
        ChordRemapRule(name: "Cmd+L → Right", whenKeys: ["cmd", "l"], sendKeys: ["right"]),
        ChordRemapRule(name: "Ctrl+Shift+A → Copy", whenKeys: ["ctrl", "shift", "a"], sendKeys: ["cmd", "c"]),
        ChordRemapRule(name: "Ctrl+Shift+X → Paste", whenKeys: ["ctrl", "shift", "x"], sendKeys: ["cmd", "v"]),
    ]

    static func parseKeyList(_ raw: String) -> [String] {
        raw.split { $0 == "+" || $0 == "," || $0.isWhitespace }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func classifyKeys(_ keys: [String]) -> (modifiers: [String], regular: [String]) {
        let modifierSet: Set<String> = [
            "cmd", "command", "shift", "option", "opt", "alt", "ctrl", "control", "fn", "function"
        ]
        var modifiers: [String] = []
        var regular: [String] = []
        for key in keys {
            let lower = key.lowercased()
            if modifierSet.contains(lower) {
                modifiers.append(lower)
            } else {
                regular.append(lower)
            }
        }
        return (modifiers, regular)
    }

    static func modifierFlags(for mods: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for mod in mods {
            switch mod.lowercased() {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "opt", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn", "function": flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        return flags
    }

    static func modKeyCode(name: String) -> CGKeyCode? {
        switch name.lowercased() {
        case "cmd", "command": return 55
        case "shift": return 56
        case "option", "opt", "alt": return 58
        case "ctrl", "control": return 59
        case "fn", "function": return 63
        default: return nil
        }
    }

    static func keyCodeFor(name: String) -> CGKeyCode? {
        let lower = name.lowercased()
        let charCodes: [Character: CGKeyCode] = [
            "a": 0,   "s": 1,   "d": 2,   "f": 3,   "h": 4,   "g": 5,
            "z": 6,   "x": 7,   "c": 8,   "v": 9,   "b": 11,  "q": 12,
            "w": 13,  "e": 14,  "r": 15,  "y": 16,  "t": 17,
            "1": 18,  "2": 19,  "3": 20,  "4": 21,  "6": 22,  "5": 23,
            "=": 24,  "9": 25,  "7": 26,  "-": 27,  "8": 28,  "0": 29,
            "]": 30,  "o": 31,  "u": 32,  "[": 33,  "i": 34,  "p": 35,
            "l": 37,  "j": 38,  "'": 39,  "k": 40,  ";": 41,  "\\": 42,
            ",": 43,  "/": 44,  "n": 45,  "m": 46,  ".": 47,  " ": 49,
            "`": 50,
        ]
        if lower.count == 1, let first = lower.first, let code = charCodes[first] {
            return code
        }
        let specialKeys: [String: CGKeyCode] = [
            "return": 36, "enter": 36, "tab": 48, "space": 49,
            "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118,
            "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        ]
        return specialKeys[lower]
    }

    // MARK: - ~/.gesture/config.json importer

    private struct LegacyConfig: Decodable {
        struct LegacyGesture: Decodable {
            let name: String
            let fingers: Int
            let direction: TrackpadGestureDirection
            let minDistance: Double
            let keys: [String]
        }
        struct LegacyHotkey: Decodable {
            let name: String
            let when: [String]
            let send: [String]
        }
        struct LegacySettings: Decodable {
            let debounceMs: Int?
            let diagonalRejectRatio: Double?
            let downBiasRatio: Double?
        }
        let gestures: [LegacyGesture]
        let hotkeys: [LegacyHotkey]?
        let settings: LegacySettings?
    }

    struct ImportedLegacyConfig: Equatable {
        let gestures: [TrackpadGestureRule]
        let hotkeys: [ChordRemapRule]
        let debounceMs: Int
        let diagonalRejectRatio: Double
        let downBiasRatio: Double
    }

    static func decodeLegacyConfigJSON(_ data: Data) -> ImportedLegacyConfig? {
        guard let decoded = try? JSONDecoder().decode(LegacyConfig.self, from: data) else {
            return nil
        }
        let gestures = decoded.gestures.map {
            TrackpadGestureRule(
                name: $0.name,
                fingers: $0.fingers,
                direction: $0.direction,
                minDistance: $0.minDistance,
                keys: $0.keys.map { $0.lowercased() }
            )
        }
        let hotkeys = (decoded.hotkeys ?? []).map {
            ChordRemapRule(
                name: $0.name,
                whenKeys: $0.when.map { $0.lowercased() },
                sendKeys: $0.send.map { $0.lowercased() }
            )
        }
        let debounce = min(max(decoded.settings?.debounceMs ?? 150, 0), 2_000)
        let diag = min(max(decoded.settings?.diagonalRejectRatio ?? 0.95, 0.2), 1.0)
        let downBias = min(max(decoded.settings?.downBiasRatio ?? 0.35, 0.05), 1.0)
        return ImportedLegacyConfig(
            gestures: gestures,
            hotkeys: hotkeys,
            debounceMs: debounce,
            diagonalRejectRatio: diag,
            downBiasRatio: downBias
        )
    }
}
