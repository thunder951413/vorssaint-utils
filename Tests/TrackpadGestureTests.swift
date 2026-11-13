// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum TrackpadGestureTests {
    static func run(_ suite: TestSuite) {
        recognizerSwipes(suite)
        keyCodecAndLegacyImport(suite)
    }

    private static func recognizerSwipes(_ suite: TestSuite) {
        let recognizer = TrackpadGestureRecognizer()
        var captured: TrackpadGestureEvent?
        recognizer.onGesture = { event in
            captured = event
            return true
        }

        // 3-finger downward swipe with slight horizontal arc (`downBiasRatio` = 0.35)
        let start = [
            TrackpadActiveTouch(identifier: 1, state: 4, normalizedX: 0.40, normalizedY: 0.72),
            TrackpadActiveTouch(identifier: 2, state: 4, normalizedX: 0.50, normalizedY: 0.74),
            TrackpadActiveTouch(identifier: 3, state: 4, normalizedX: 0.60, normalizedY: 0.72),
        ]
        let mid = [
            TrackpadActiveTouch(identifier: 1, state: 4, normalizedX: 0.44, normalizedY: 0.44),
            TrackpadActiveTouch(identifier: 2, state: 4, normalizedX: 0.54, normalizedY: 0.46),
            TrackpadActiveTouch(identifier: 3, state: 4, normalizedX: 0.64, normalizedY: 0.44),
        ]
        recognizer.processTouches(start, timestamp: 1.00)
        recognizer.processTouches(mid, timestamp: 1.05)
        recognizer.processTouches([], timestamp: 1.08)

        suite.expect(captured?.fingers == 3 && captured?.direction == .down,
                     "3-finger downward swipe is recognized reliably")
        if let captured {
            let matched = TrackpadGestureRecognizer.matchingRule(
                for: captured,
                in: TrackpadGestureKeyCodec.defaultGestureRules,
                downBiasRatio: 0.35
            )
            suite.expect(matched?.keys == ["cmd", "w"],
                         "3-finger swipe down matches Close Window (cmd+w)")
        }
    }

    private static func keyCodecAndLegacyImport(_ suite: TestSuite) {
        suite.expect(TrackpadGestureKeyCodec.keyCodeFor(name: "w") == 13
                     && TrackpadGestureKeyCodec.keyCodeFor(name: "left") == 123
                     && TrackpadGestureKeyCodec.modKeyCode(name: "cmd") == 55,
                     "macOS virtual keycodes match KeySimulator mappings")

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
        let imported = TrackpadGestureKeyCodec.decodeLegacyConfigJSON(legacyJSON)
        suite.expect(imported?.gestures.count == 1
                     && imported?.hotkeys.count == 1
                     && imported?.debounceMs == 180,
                     "legacy ~/.gesture/config.json decodes into native Vorssaint rules")
    }
}
