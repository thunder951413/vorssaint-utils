// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

// MARK: - Gesture Direction & Touch Primitives

enum TrackpadGestureDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case up
    case down
    case left
    case right
    case pinch
    case spread

    var id: String { rawValue }

    var displayTitle: String { title(chinese: false) }

    func title(chinese: Bool) -> String {
        switch self {
        case .up: return chinese ? "向上滑动" : "Swipe Up"
        case .down: return chinese ? "向下滑动" : "Swipe Down"
        case .left: return chinese ? "向左滑动" : "Swipe Left"
        case .right: return chinese ? "向右滑动" : "Swipe Right"
        case .pinch: return chinese ? "捏合 (Pinch)" : "Pinch In"
        case .spread: return chinese ? "张开 (Spread)" : "Spread Out"
        }
    }

    func shortTitle(chinese: Bool) -> String {
        switch self {
        case .up: return chinese ? "向上" : "Up"
        case .down: return chinese ? "向下" : "Down"
        case .left: return chinese ? "向左" : "Left"
        case .right: return chinese ? "向右" : "Right"
        case .pinch: return chinese ? "捏合" : "Pinch"
        case .spread: return chinese ? "张开" : "Spread"
        }
    }
}

struct TrackpadTouchDecodeError: LocalizedError, Equatable, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct TrackpadActiveTouch: Codable, Equatable, Sendable {
    let identifier: Int
    let state: Int
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    /// Contact ellipse & size proxy metrics from private `MTContact`; nil on legacy frames.
    let majorAxis: CGFloat?
    let minorAxis: CGFloat?
    let contactSize: CGFloat?

    /// Only `makeTouch` (3) and `touching` (4) represent physical pad contact;
    /// hover and lift-off lingering states do not count toward finger totals.
    var isTouching: Bool { state == 3 || state == 4 }

    init(identifier: Int,
         state: Int,
         normalizedX: CGFloat,
         normalizedY: CGFloat,
         majorAxis: CGFloat? = nil,
         minorAxis: CGFloat? = nil,
         contactSize: CGFloat? = nil) {
        self.identifier = identifier
        self.state = state
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.contactSize = contactSize
    }
}

/// Canonical 96-byte arm64 `MTContact` decoder ported from `tools/gesture` (`MTContactDecoder.swift`).
/// Normalized coordinates sit at offsets 32/36, contact size proxy at 48, and major/minor ellipse axes at 60/64.
enum MTContactDecoder {
    static let stride = 96

    static func decode(_ buffer: UnsafeRawBufferPointer, count: Int) throws -> [TrackpadActiveTouch] {
        guard (0...20).contains(count), buffer.count >= count * stride else {
            throw TrackpadTouchDecodeError("Abnormal touch buffer length (count=\(count), bytes=\(buffer.count))")
        }
        var touches: [TrackpadActiveTouch] = []
        touches.reserveCapacity(count)
        var identifiers = Set<Int>()
        for index in 0..<count {
            let base = index * stride
            let identifier = Int(buffer.loadUnaligned(fromByteOffset: base + 16, as: Int32.self))
            let state = Int(buffer.loadUnaligned(fromByteOffset: base + 20, as: Int32.self))
            let x = CGFloat(buffer.loadUnaligned(fromByteOffset: base + 32, as: Float.self))
            let y = CGFloat(buffer.loadUnaligned(fromByteOffset: base + 36, as: Float.self))
            guard (-1...128).contains(identifier),
                  identifiers.insert(identifier).inserted,
                  (0...7).contains(state),
                  x.isFinite, y.isFinite,
                  (-0.2...1.2).contains(x), (-0.2...1.2).contains(y) else {
                throw TrackpadTouchDecodeError("Invalid MTContact record at index \(index); private struct layout may have changed")
            }
            func metric(at offset: Int) -> CGFloat? {
                let value = CGFloat(buffer.loadUnaligned(fromByteOffset: base + offset, as: Float.self))
                return value.isFinite && value > 0 ? value : nil
            }
            touches.append(TrackpadActiveTouch(
                identifier: identifier,
                state: state,
                normalizedX: x,
                normalizedY: y,
                majorAxis: metric(at: 60),
                minorAxis: metric(at: 64),
                contactSize: metric(at: 48)
            ))
        }
        return touches
    }
}

enum TouchFrameValidator {
    static func isValid(_ touches: [TrackpadActiveTouch]) -> Bool {
        guard touches.count <= 20 else { return false }
        var identifiers = Set<Int>()
        return touches.allSatisfy {
            (-1...128).contains($0.identifier)
                && identifiers.insert($0.identifier).inserted
                && (0...7).contains($0.state)
                && $0.normalizedX.isFinite && $0.normalizedY.isFinite
                && (-0.2...1.2).contains($0.normalizedX)
                && (-0.2...1.2).contains($0.normalizedY)
                && [$0.majorAxis, $0.minorAxis, $0.contactSize].allSatisfy { metric in
                    metric.map { $0.isFinite && $0 > 0 } ?? true
                }
        }
    }
}

struct TrackpadGestureEvent: Equatable, Sendable {
    let fingers: Int
    let direction: TrackpadGestureDirection
    let distance: CGFloat
    let dx: CGFloat
    let dy: CGFloat
}

// MARK: - Palm Rejection & Coherent Swipe Guards

/// Relative intra-frame ellipse/size + isolated-contact palm filter ported from `tools/gesture` (`PalmRejectionFilter.swift`).
struct PalmRejectionFilter {
    private struct Contact {
        let origin: CGPoint
        let beganAt: Double
        var maximumMotion: CGFloat = 0
        var lastState: Int
        var candidateFrames = 0
        var candidateSince: Double = 0
        var isolatedFrames = 0
        var isolatedSince: Double = 0
        var isPalm = false

        var beganAtEdge: Bool {
            origin.x < 0.08 || origin.x > 0.92 || origin.y < 0.08 || origin.y > 0.92
        }
    }

    static let horizontalScale: CGFloat = 1.5
    static let isolationDistance: CGFloat = 0.40
    static let fingerPairDistance: CGFloat = 0.36

    private var contacts: [Int: Contact] = [:]
    private var sessionMaximumTouching = 0

    mutating func reset() {
        contacts.removeAll()
        sessionMaximumTouching = 0
    }

    static func scaledDistance(_ a: TrackpadActiveTouch, _ b: TrackpadActiveTouch) -> CGFloat {
        hypot((a.normalizedX - b.normalizedX) * horizontalScale, a.normalizedY - b.normalizedY)
    }

    mutating func filter(_ touches: [TrackpadActiveTouch], timestamp: Double) -> [TrackpadActiveTouch] {
        let identifiers = Set(touches.map(\.identifier))
        contacts = contacts.filter { identifiers.contains($0.key) }
        let touchingCount = touches.filter { $0.isTouching && contacts[$0.identifier]?.isPalm != true }.count
        sessionMaximumTouching = touchingCount == 0 ? 0 : max(sessionMaximumTouching, touchingCount)

        for touch in touches {
            if contacts[touch.identifier] == nil
                || (touch.state == 1 && (contacts[touch.identifier]?.lastState ?? 0) >= 5) {
                contacts[touch.identifier] = Contact(
                    origin: CGPoint(x: touch.normalizedX, y: touch.normalizedY),
                    beganAt: timestamp,
                    lastState: touch.state
                )
            }
            guard var contact = contacts[touch.identifier] else { continue }
            contact.maximumMotion = max(
                contact.maximumMotion,
                hypot(touch.normalizedX - contact.origin.x, touch.normalizedY - contact.origin.y)
            )
            contact.lastState = touch.state
            contacts[touch.identifier] = contact
        }

        let shapedTouches = touches.filter {
            contacts[$0.identifier]?.isPalm == false && $0.majorAxis != nil && $0.minorAxis != nil
        }.sorted { ($0.majorAxis! * $0.minorAxis!) < ($1.majorAxis! * $1.minorAxis!) }

        if shapedTouches.count >= 3 {
            let reference = Array(shapedTouches.prefix(2))
            let area = reference.reduce(CGFloat.zero) { $0 + $1.majorAxis! * $1.minorAxis! } / 2
            let major = reference.reduce(CGFloat.zero) { $0 + $1.majorAxis! } / 2
            let minor = reference.reduce(CGFloat.zero) { $0 + $1.minorAxis! } / 2
            let sizes = reference.compactMap(\.contactSize)
            let size = sizes.count == 2 ? sizes.reduce(0, +) / 2 : nil
            let peerMotion = reference.compactMap { contacts[$0.identifier]?.maximumMotion }.min() ?? 0

            if area > 0, major > 0, minor > 0 {
                for touch in shapedTouches.dropFirst(2) {
                    guard var contact = contacts[touch.identifier],
                          let touchMajor = touch.majorAxis,
                          let touchMinor = touch.minorAxis else { continue }
                    let areaRatio = touchMajor * touchMinor / area
                    let majorRatio = touchMajor / major
                    let minorRatio = touchMinor / minor
                    let sizeRatio = size.flatMap { baseline in touch.contactSize.map { $0 / baseline } } ?? 0

                    let broadPalm = areaRatio >= 2.5 && majorRatio >= 1.6 && minorRatio >= 1.4
                    let resting = contact.maximumMotion < 0.03
                        && peerMotion >= 0.04
                        && timestamp - contact.beganAt >= 0.06
                    let largePartialPalm = areaRatio >= 3.2 && majorRatio >= 2.2 && sizeRatio >= 3
                    let partialPalm = areaRatio >= 2.5 && majorRatio >= 1.8 && sizeRatio >= 3
                        && (contact.beganAtEdge || resting)

                    if broadPalm || partialPalm || largePartialPalm {
                        if contact.candidateFrames == 0 { contact.candidateSince = timestamp }
                        contact.candidateFrames += 1
                        if contact.candidateFrames >= 2 && timestamp - contact.candidateSince >= 0.008 {
                            contact.isPalm = true
                        }
                    } else {
                        contact.candidateFrames = 0
                    }
                    contacts[touch.identifier] = contact
                }
            }
            for touch in reference {
                contacts[touch.identifier]?.candidateFrames = 0
            }
        } else {
            for touch in shapedTouches {
                contacts[touch.identifier]?.candidateFrames = 0
            }
        }

        markIsolatedContact(in: touches, timestamp: timestamp)
        return touches.filter { contacts[$0.identifier]?.isPalm != true }
    }

    private mutating func markIsolatedContact(in touches: [TrackpadActiveTouch], timestamp: Double) {
        let candidates = touches.filter { $0.isTouching && contacts[$0.identifier]?.isPalm == false }
        var isolated: Int?
        if candidates.count == 3, sessionMaximumTouching <= 3 {
            for touch in candidates {
                let others = candidates.filter { $0.identifier != touch.identifier }
                let nearest = others.map { Self.scaledDistance(touch, $0) }.min() ?? 0
                if nearest > Self.isolationDistance,
                   others.count == 2,
                   Self.scaledDistance(others[0], others[1]) < Self.fingerPairDistance {
                    isolated = touch.identifier
                    break
                }
            }
        }
        for touch in candidates {
            guard var contact = contacts[touch.identifier] else { continue }
            if touch.identifier == isolated {
                if contact.isolatedFrames == 0 { contact.isolatedSince = timestamp }
                contact.isolatedFrames += 1
                if contact.isolatedFrames >= 3 && timestamp - contact.isolatedSince >= 0.016 {
                    contact.isPalm = true
                }
            } else {
                contact.isolatedFrames = 0
            }
            contacts[touch.identifier] = contact
        }
    }
}

/// Ensures every participating finger translates coherently during 3+ finger swipes (`SwipeMotion.swift`).
enum SwipeMotion {
    static func isCoherent(start: [Int: CGPoint],
                           end: [Int: CGPoint],
                           dx: CGFloat,
                           dy: CGFloat,
                           minimumDistance: CGFloat) -> Bool {
        let distance = hypot(dx, dy)
        guard distance > 0,
              start.count >= 3,
              start.keys.allSatisfy({ end[$0] != nil }),
              start.count == end.count else { return false }
        let ux = dx / distance
        let uy = dy / distance
        let motions = start.map { identifier, origin -> (along: CGFloat, across: CGFloat) in
            let point = end[identifier]!
            let x = point.x - origin.x
            let y = point.y - origin.y
            return (x * ux + y * uy, abs(x * uy - y * ux))
        }
        let projections = motions.map(\.along).sorted()
        let median = projections[projections.count / 2]
        let required = max(minimumDistance * 0.5, median * 0.5)
        return median > 0 && motions.allSatisfy { $0.along >= required && $0.across <= $0.along }
    }
}

// MARK: - Diagnostic Trace Ring Buffer

struct GestureTraceFrame: Codable, Equatable, Sendable {
    let timestamp: Double
    let touches: [TrackpadActiveTouch]
}

struct GestureTrace: Codable, Equatable, Sendable {
    enum Decision: String, Codable, Equatable, Sendable {
        case rejectedIncoherentSwipe
        case ignoredLateContact
        case ruleTriggered
    }

    struct Motion: Codable, Equatable, Sendable {
        let identifier: Int
        let startX: Double
        let startY: Double
        let endX: Double
        let endY: Double
    }

    let decision: Decision
    let fingers: Int
    let direction: TrackpadGestureDirection
    let distance: Double
    let dx: Double
    let dy: Double
    let motions: [Motion]
    let frames: [GestureTraceFrame]
}

struct GestureTraceBuffer: Sendable {
    private(set) var frames: [GestureTraceFrame] = []

    mutating func append(_ touches: [TrackpadActiveTouch], timestamp: Double) {
        frames.append(GestureTraceFrame(timestamp: timestamp, touches: touches))
        let expired = frames.prefix { $0.timestamp < timestamp - 2.0 }.count
        let excess = max(expired, frames.count - 192)
        if excess > 0 {
            frames.removeFirst(excess)
        }
    }

    mutating func reset() {
        frames.removeAll()
    }
}

// MARK: - Gesture Recognizer & Tuning

struct TrackpadGestureTuning: Equatable, Sendable {
    var diagonalRejectRatio: CGFloat = 0.95
    var downBiasRatio: CGFloat = 0.35
    var spreadThreshold: CGFloat = 0.03
    var minSwipeDistance: CGFloat = 0.01
    var downBiasMinAbsDy: CGFloat = 0.08
    var spreadToDistanceRatio: CGFloat = 2.0
    var liveTriggerDistance: CGFloat = 0.06
    var extraFingerConfirmFrames: Int = 3
    var extraFingerConfirmDuration: Double = 0.018
    var lockMotionDistance: CGFloat = 0.03
    var twoFingerLockDelay: Double = 0.08
    var multiFingerLockDelay: Double = 0.12
    var brushContactMaxDuration: Double = 0.15
    var brushContactMinJoinDelay: Double = 0.04
    var stillnessRebaseDuration: Double = 0.3
    var stillnessMotionTolerance: CGFloat = 0.01
}

/// Full multi-touch swipe/pinch/spread recognizer ported from `tools/gesture` (`GestureRecognizer.swift`).
final class TrackpadGestureRecognizer {
    private var palmFilter = PalmRejectionFilter()
    private var traceBuffer = GestureTraceBuffer()
    private var recordedRejectedSwipe = false
    private var recordedIgnoredLateTouch = false
    private var gestureBeganTimestamp: Double = 0
    private var lockedTouchIdentifiers: Set<Int>?
    private var currentGesturePositions: [Int: CGPoint] = [:]
    private var maxGesturePositions: [Int: CGPoint] = [:]
    private var maxSwipePositions: [Int: CGPoint] = [:]
    private var maxSwipeDx: CGFloat = 0
    private var maxSwipeDy: CGFloat = 0
    private var maxSwipeDistance: CGFloat = 0

    private(set) var acceptedTouchCount = 0
    private(set) var rejectedPalmCount = 0

    private var activeTouches: [Int: TrackpadActiveTouch] = [:]
    private var gestureStartCentroid: CGPoint?
    private var currentCentroid: CGPoint = .zero
    private var maxGestureDx: CGFloat = 0
    private var maxGestureDy: CGFloat = 0
    private var maxGestureDistance: CGFloat = 0
    private var maxFingersSeen = 0
    private var gestureFingers = 0
    private var gestureStartPositions: [Int: CGPoint] = [:]
    private var maxCoherentTranslationDistance: CGFloat = 0
    private var startSpread: CGFloat = 0
    private var endSpread: CGFloat = 0
    private var didTriggerCurrentGesture = false
    private var lastObservedFingerCount = 0
    private var lastObservedFingerTimestamp: Double = 0
    private var observedFingerFrames = 0
    private var gestureTouchIdentifiers = Set<Int>()
    private var contactFirstSeen: [Int: Double] = [:]
    private var stillnessAnchor: [Int: CGPoint] = [:]
    private var stillnessAnchorTimestamp: Double?

    var onGesture: ((TrackpadGestureEvent) -> Bool)?
    var onTrace: ((GestureTrace) -> Void)?
    var tuning = TrackpadGestureTuning()

    var diagonalRejectRatio: Double {
        get { Double(tuning.diagonalRejectRatio) }
        set { tuning.diagonalRejectRatio = CGFloat(newValue) }
    }

    var downBiasRatio: Double {
        get { Double(tuning.downBiasRatio) }
        set { tuning.downBiasRatio = CGFloat(newValue) }
    }

    var liveTriggerDistance: CGFloat {
        get { tuning.liveTriggerDistance }
        set { tuning.liveTriggerDistance = newValue }
    }

    func processTouches(_ rawTouches: [TrackpadActiveTouch], timestamp: Double) {
        guard timestamp.isFinite, TouchFrameValidator.isValid(rawTouches) else { return }
        if onTrace != nil {
            traceBuffer.append(rawTouches, timestamp: timestamp)
        }
        let nonPalms = palmFilter.filter(rawTouches, timestamp: timestamp)
        let rejected = Set(rawTouches.map(\.identifier)).subtracting(nonPalms.map(\.identifier))
        var touches = nonPalms.filter(\.isTouching)

        let lockDelay = gestureFingers >= 3 ? tuning.multiFingerLockDelay : tuning.twoFingerLockDelay
        if lockedTouchIdentifiers == nil,
           gestureFingers >= 2,
           maxGestureDistance >= tuning.lockMotionDistance,
           timestamp - gestureBeganTimestamp >= lockDelay {
            lockedTouchIdentifiers = gestureTouchIdentifiers
        }
        if let lockedTouchIdentifiers {
            let previousCount = touches.count
            touches = touches.filter { lockedTouchIdentifiers.contains($0.identifier) }
            if previousCount > touches.count, !recordedIgnoredLateTouch {
                recordedIgnoredLateTouch = true
                let direction: TrackpadGestureDirection = abs(maxGestureDx) > abs(maxGestureDy)
                    ? (maxGestureDx > 0 ? .right : .left)
                    : (maxGestureDy > 0 ? .up : .down)
                emitTrace(
                    decision: .ignoredLateContact,
                    event: TrackpadGestureEvent(
                        fingers: gestureFingers,
                        direction: direction,
                        distance: maxGestureDistance,
                        dx: maxGestureDx,
                        dy: maxGestureDy
                    ),
                    positions: currentGesturePositions
                )
            }
        }

        let activeSet = Set(touches.map(\.identifier))
        let previousFirstSeen = contactFirstSeen
        contactFirstSeen = contactFirstSeen.filter { activeSet.contains($0.key) }
        for identifier in activeSet where contactFirstSeen[identifier] == nil {
            contactFirstSeen[identifier] = timestamp
        }

        if !didTriggerCurrentGesture, !rejected.isDisjoint(with: activeTouches.keys) {
            let origins = gestureStartPositions.filter { activeSet.contains($0.key) }
            if touches.count >= 2 && origins.count == touches.count {
                let count = CGFloat(origins.count)
                let origin = origins.values.reduce(CGPoint.zero) {
                    CGPoint(x: $0.x + $1.x / count, y: $0.y + $1.y / count)
                }
                gestureStartCentroid = origin
                gestureFingers = touches.count
                maxFingersSeen = touches.count
                gestureTouchIdentifiers = activeSet
                startSpread = origins.values.reduce(CGFloat.zero) {
                    $0 + hypot($1.x - origin.x, $1.y - origin.y) / count
                }
                resetMaxGestureDisplacement(startPositions: origins)
                stillnessAnchorTimestamp = nil
            } else {
                resetGesture()
            }
        }

        acceptedTouchCount = touches.count
        rejectedPalmCount = rejected.count
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
            resetGesture()
            return
        }

        guard effectiveCount >= 2 else {
            if nowCount == 0 { resetGesture() }
            return
        }

        guard nowCount <= effectiveCount else { return }

        if gestureFingers > 0 && nowCount < gestureFingers {
            guard isBrushDeparture(activeSet: activeSet,
                                   previousFirstSeen: previousFirstSeen,
                                   timestamp: timestamp) else {
                return
            }
        }

        updateCentroid()

        if gestureStartCentroid == nil {
            gestureBeganTimestamp = timestamp
            gestureStartCentroid = currentCentroid
            startSpread = calculateSpread()
            resetMaxGestureDisplacement()
            stillnessAnchorTimestamp = nil
        }

        if !didTriggerCurrentGesture && (effectiveCount > gestureFingers || activeSet != gestureTouchIdentifiers) {
            gestureBeganTimestamp = timestamp
            gestureFingers = effectiveCount
            gestureTouchIdentifiers = activeSet
            gestureStartCentroid = currentCentroid
            startSpread = calculateSpread()
            resetMaxGestureDisplacement()
            stillnessAnchorTimestamp = nil
        }

        rebaseIfResting(timestamp: timestamp)
        updateMaxGestureDisplacement()

        if let start = gestureStartCentroid, !activeTouches.isEmpty {
            let dx = currentCentroid.x - start.x
            let dy = currentCentroid.y - start.y
            let squaredDeformation = activeTouches.values.reduce(CGFloat.zero) { total, touch in
                guard let origin = gestureStartPositions[touch.identifier] else { return total }
                let relativeX = touch.normalizedX - origin.x - dx
                let relativeY = touch.normalizedY - origin.y - dy
                return total + relativeX * relativeX + relativeY * relativeY
            }
            let deformation = sqrt(squaredDeformation / CGFloat(activeTouches.count))
            let minimumTouchMotion = activeTouches.values.compactMap { touch -> CGFloat? in
                guard let origin = gestureStartPositions[touch.identifier] else { return nil }
                return hypot(touch.normalizedX - origin.x, touch.normalizedY - origin.y)
            }.min() ?? hypot(dx, dy)
            let coherentMotion = min(minimumTouchMotion, max(0, hypot(dx, dy) - deformation))
            maxCoherentTranslationDistance = max(maxCoherentTranslationDistance, coherentMotion)
        }
        endSpread = calculateSpread()

        if !didTriggerCurrentGesture,
           let event = recognizeGesture(fingers: gestureFingers),
           event.distance >= tuning.liveTriggerDistance {
            didTriggerCurrentGesture = onGesture?(event) == true
        }
    }

    func reset() {
        palmFilter.reset()
        traceBuffer.reset()
        contactFirstSeen.removeAll()
        acceptedTouchCount = 0
        rejectedPalmCount = 0
        resetGesture()
    }

    func recordTriggeredGesture(_ event: TrackpadGestureEvent) {
        let isSwipe = event.direction != .pinch && event.direction != .spread && event.fingers >= 3
        emitTrace(
            decision: .ruleTriggered,
            event: event,
            positions: isSwipe ? maxSwipePositions : currentGesturePositions
        )
    }

    private func resetGesture() {
        recordedRejectedSwipe = false
        recordedIgnoredLateTouch = false
        lockedTouchIdentifiers = nil
        gestureBeganTimestamp = 0
        activeTouches.removeAll()
        gestureStartCentroid = nil
        gestureStartPositions.removeAll()
        maxCoherentTranslationDistance = 0
        currentCentroid = .zero
        resetMaxGestureDisplacement()
        startSpread = 0
        endSpread = 0
        maxFingersSeen = 0
        gestureFingers = 0
        didTriggerCurrentGesture = false
        lastObservedFingerCount = 0
        lastObservedFingerTimestamp = 0
        observedFingerFrames = 0
        gestureTouchIdentifiers.removeAll()
        stillnessAnchor.removeAll()
        stillnessAnchorTimestamp = nil
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
        var dx = maxGestureDistance > currentDistance ? maxGestureDx : currentDx
        var dy = maxGestureDistance > currentDistance ? maxGestureDy : currentDy
        var totalDistance = max(maxGestureDistance, currentDistance)

        let spreadDelta = endSpread - startSpread
        let spreadSignificant = abs(spreadDelta) > tuning.spreadThreshold

        var direction: TrackpadGestureDirection
        if fingers >= 4
            && spreadSignificant
            && abs(spreadDelta) > min(totalDistance, maxCoherentTranslationDistance) * tuning.spreadToDistanceRatio {
            direction = spreadDelta > 0 ? .spread : .pinch
        } else if totalDistance > tuning.minSwipeDistance {
            if fingers >= 3 {
                if !recordedRejectedSwipe,
                   totalDistance >= tuning.liveTriggerDistance,
                   maxSwipeDistance < tuning.liveTriggerDistance {
                    recordedRejectedSwipe = true
                    let rejectedDirection: TrackpadGestureDirection = abs(dx) > abs(dy)
                        ? (dx > 0 ? .right : .left)
                        : (dy > 0 ? .up : .down)
                    emitTrace(
                        decision: .rejectedIncoherentSwipe,
                        event: TrackpadGestureEvent(
                            fingers: fingers,
                            direction: rejectedDirection,
                            distance: totalDistance,
                            dx: dx,
                            dy: dy
                        ),
                        positions: maxGestureDistance > currentDistance ? maxGesturePositions : currentGesturePositions
                    )
                }
                guard maxSwipeDistance > tuning.minSwipeDistance else { return nil }
                dx = maxSwipeDx
                dy = maxSwipeDy
                totalDistance = maxSwipeDistance
            }

            let absDx = abs(dx)
            let absDy = abs(dy)
            let minor = min(absDx, absDy)
            let major = max(absDx, absDy)

            if major > 0 && minor >= major * tuning.diagonalRejectRatio {
                return nil
            }

            if absDx > absDy {
                direction = dx > 0 ? .right : .left
            } else {
                direction = dy > 0 ? .up : .down
            }

            if (direction == .left || direction == .right)
                && dy < 0
                && absDy > absDx * tuning.downBiasRatio
                && absDy > tuning.downBiasMinAbsDy {
                direction = .down
            }
        } else {
            return nil
        }

        let recognizedDistance: CGFloat = (direction == .pinch || direction == .spread)
            ? abs(spreadDelta)
            : totalDistance
        return TrackpadGestureEvent(
            fingers: fingers,
            direction: direction,
            distance: recognizedDistance,
            dx: dx,
            dy: dy
        )
    }

    private func updateObservedFingerCount(_ count: Int, timestamp: Double) {
        if count == lastObservedFingerCount {
            observedFingerFrames += 1
            return
        }
        lastObservedFingerCount = count
        lastObservedFingerTimestamp = timestamp
        observedFingerFrames = 1
    }

    private func isBrushDeparture(activeSet: Set<Int>,
                                  previousFirstSeen: [Int: Double],
                                  timestamp: Double) -> Bool {
        guard !didTriggerCurrentGesture,
              activeSet.count >= 2,
              activeSet.isSubset(of: gestureTouchIdentifiers),
              let earliestRemaining = activeSet.compactMap({ contactFirstSeen[$0] }).min() else {
            return false
        }
        let departed = gestureTouchIdentifiers.subtracting(activeSet)
        return !departed.isEmpty && departed.allSatisfy { identifier in
            guard let began = previousFirstSeen[identifier] else { return false }
            return timestamp - began < tuning.brushContactMaxDuration
                && began - earliestRemaining >= tuning.brushContactMinJoinDelay
        }
    }

    private func rebaseIfResting(timestamp: Double) {
        guard !didTriggerCurrentGesture, gestureStartCentroid != nil else { return }
        let positions = activeTouches.mapValues { CGPoint(x: $0.normalizedX, y: $0.normalizedY) }
        guard let anchorTimestamp = stillnessAnchorTimestamp,
              Set(stillnessAnchor.keys) == Set(positions.keys) else {
            stillnessAnchor = positions
            stillnessAnchorTimestamp = timestamp
            return
        }
        let motion = positions.map { identifier, point -> CGFloat in
            let anchor = stillnessAnchor[identifier]!
            return hypot(point.x - anchor.x, point.y - anchor.y)
        }.max() ?? 0
        if motion > tuning.stillnessMotionTolerance {
            stillnessAnchor = positions
            stillnessAnchorTimestamp = timestamp
        } else if timestamp - anchorTimestamp >= tuning.stillnessRebaseDuration {
            gestureStartCentroid = currentCentroid
            startSpread = calculateSpread()
            resetMaxGestureDisplacement()
            stillnessAnchor = positions
            stillnessAnchorTimestamp = timestamp
        }
    }

    private func effectiveFingerCount(for observedCount: Int, timestamp: Double) -> Int {
        if gestureFingers >= 2 && observedCount < gestureFingers { return observedCount }
        guard observedCount >= 3 else { return observedCount }

        let stableDuration = timestamp - lastObservedFingerTimestamp
        let isStable = observedFingerFrames >= tuning.extraFingerConfirmFrames
            && stableDuration >= tuning.extraFingerConfirmDuration
        if isStable {
            return observedCount
        }
        if gestureFingers >= 2 {
            return gestureFingers
        }
        return 0
    }

    private func updateCentroid() {
        guard !activeTouches.isEmpty else { return }
        let sum = activeTouches.values.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.normalizedX, y: $0.y + $1.normalizedY)
        }
        let n = CGFloat(activeTouches.count)
        currentCentroid = CGPoint(x: sum.x / n, y: sum.y / n)
    }

    private func updateMaxGestureDisplacement() {
        guard let start = gestureStartCentroid else { return }
        currentGesturePositions = activeTouches.mapValues { CGPoint(x: $0.normalizedX, y: $0.normalizedY) }
        let dx = currentCentroid.x - start.x
        let dy = currentCentroid.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        if distance > maxGestureDistance {
            maxGestureDx = dx
            maxGestureDy = dy
            maxGestureDistance = distance
            maxGesturePositions = currentGesturePositions
        }
        if distance > maxSwipeDistance,
           SwipeMotion.isCoherent(start: gestureStartPositions,
                                  end: currentGesturePositions,
                                  dx: dx,
                                  dy: dy,
                                  minimumDistance: tuning.minSwipeDistance) {
            maxSwipeDx = dx
            maxSwipeDy = dy
            maxSwipeDistance = distance
            maxSwipePositions = currentGesturePositions
        }
    }

    private func resetMaxGestureDisplacement(startPositions: [Int: CGPoint]? = nil) {
        gestureStartPositions = startPositions ?? activeTouches.mapValues {
            CGPoint(x: $0.normalizedX, y: $0.normalizedY)
        }
        currentGesturePositions = gestureStartPositions
        maxGesturePositions = gestureStartPositions
        maxSwipePositions = [:]
        maxSwipeDx = 0
        maxSwipeDy = 0
        maxSwipeDistance = 0
        maxCoherentTranslationDistance = 0
        maxGestureDx = 0
        maxGestureDy = 0
        maxGestureDistance = 0
    }

    private func emitTrace(decision: GestureTrace.Decision,
                           event: TrackpadGestureEvent,
                           positions: [Int: CGPoint]) {
        guard let onTrace else { return }
        let motions = gestureStartPositions.keys.sorted().compactMap { identifier -> GestureTrace.Motion? in
            guard let origin = gestureStartPositions[identifier],
                  let end = positions[identifier] else { return nil }
            return GestureTrace.Motion(
                identifier: identifier,
                startX: Double(origin.x),
                startY: Double(origin.y),
                endX: Double(end.x),
                endY: Double(end.y)
            )
        }
        onTrace(GestureTrace(
            decision: decision,
            fingers: event.fingers,
            direction: event.direction,
            distance: Double(event.distance),
            dx: Double(event.dx),
            dy: Double(event.dy),
            motions: motions,
            frames: traceBuffer.frames
        ))
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

    static func matchingAutomationRule(for event: TrackpadGestureEvent,
                                       in rules: [GestureAutomationRule],
                                       frontmostBundleID: String?) -> GestureAutomationRule? {
        rules.first { rule in
            guard GestureConfigurationValidator.isExecutable(rule),
                  case .trackpad(let trigger) = rule.trigger,
                  trigger.fingers == event.fingers,
                  trigger.direction == event.direction else {
                return false
            }
            let distance = trigger.direction == .down ? max(0, -event.dy) : event.distance
            return distance >= CGFloat(trigger.minimumDistance)
                && rule.applicationScope.matches(bundleIdentifier: frontmostBundleID)
        }
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

// MARK: - Public Compatibility Mode Accumulator (`PublicGestureAccumulator.swift`)

struct PublicGestureAccumulator: Sendable {
    private var scrollDX: CGFloat = 0
    private var scrollDY: CGFloat = 0
    private var magnification: CGFloat = 0

    mutating func scroll(dx: CGFloat,
                         dy: CGFloat,
                         phase: NSEvent.Phase,
                         momentum: NSEvent.Phase = []) -> TrackpadGestureEvent? {
        guard momentum.isEmpty else { return nil }
        if phase.contains(.began) { scrollDX = 0; scrollDY = 0 }
        if phase.contains(.cancelled) { scrollDX = 0; scrollDY = 0; return nil }
        guard !phase.isEmpty else { return nil }
        scrollDX += dx
        scrollDY += dy
        guard phase.contains(.ended) else { return nil }
        defer { scrollDX = 0; scrollDY = 0 }
        return Self.swipe(dx: scrollDX, dy: scrollDY)
    }

    mutating func magnify(_ delta: CGFloat, phase: NSEvent.Phase) -> TrackpadGestureEvent? {
        if phase.contains(.began) { magnification = 0 }
        if phase.contains(.cancelled) { magnification = 0; return nil }
        guard !phase.isEmpty else { return nil }
        magnification += delta
        guard phase.contains(.ended) else { return nil }
        defer { magnification = 0 }
        guard magnification.isFinite, abs(magnification) >= 0.01 else { return nil }
        return TrackpadGestureEvent(
            fingers: 2,
            direction: magnification >= 0 ? .spread : .pinch,
            distance: abs(magnification),
            dx: 0,
            dy: 0
        )
    }

    static func swipe(dx: CGFloat, dy: CGFloat) -> TrackpadGestureEvent? {
        let distance = hypot(dx, dy)
        guard distance.isFinite, distance >= 0.01 else { return nil }
        let direction: TrackpadGestureDirection = abs(dx) > abs(dy)
            ? (dx > 0 ? .right : .left)
            : (dy > 0 ? .up : .down)
        return TrackpadGestureEvent(fingers: 2, direction: direction, distance: distance, dx: dx, dy: dy)
    }
}

// MARK: - Unified Schema v2 Automation Models (`AutomationModels.swift`)

enum GestureRuleCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case trackpad
    case keyboard

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .trackpad: return chinese ? "触控板" : "Trackpad"
        case .keyboard: return chinese ? "键盘" : "Keyboard"
        }
    }

    var systemImage: String {
        self == .trackpad ? "rectangle.and.hand.point.up.left" : "keyboard"
    }
}

enum GestureTriggerPhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case keyDown
    case keyUp

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .keyDown: return chinese ? "按下时" : "On Key Down"
        case .keyUp: return chinese ? "松开时" : "On Key Up"
        }
    }
}

struct TrackpadTriggerSpec: Codable, Equatable, Sendable {
    var fingers: Int = 3
    var direction: TrackpadGestureDirection = .down
    var minimumDistance: Double = 0.15

    init(fingers: Int = 3, direction: TrackpadGestureDirection = .down, minimumDistance: Double = 0.15) {
        self.fingers = fingers
        self.direction = direction
        self.minimumDistance = minimumDistance
    }
}

struct KeyboardTriggerSpec: Codable, Equatable, Sendable {
    var keys: [String] = ["cmd", "j"]
    var phase: GestureTriggerPhase = .keyDown
    var allowRepeat: Bool = false

    init(keys: [String] = ["cmd", "j"], phase: GestureTriggerPhase = .keyDown, allowRepeat: Bool = false) {
        self.keys = keys
        self.phase = phase
        self.allowRepeat = allowRepeat
    }
}

enum GestureAutomationTrigger: Codable, Equatable, Sendable {
    case trackpad(TrackpadTriggerSpec)
    case keyboard(KeyboardTriggerSpec)

    private enum CodingKeys: String, CodingKey { case type, trackpad, keyboard }

    var category: GestureRuleCategory {
        switch self {
        case .trackpad: return .trackpad
        case .keyboard: return .keyboard
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(GestureRuleCategory.self, forKey: .type) {
        case .trackpad:
            self = .trackpad(try container.decode(TrackpadTriggerSpec.self, forKey: .trackpad))
        case .keyboard:
            self = .keyboard(try container.decode(KeyboardTriggerSpec.self, forKey: .keyboard))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .type)
        switch self {
        case .trackpad(let value): try container.encode(value, forKey: .trackpad)
        case .keyboard(let value): try container.encode(value, forKey: .keyboard)
        }
    }
}

enum GestureAppScopeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case include
    case exclude

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .all: return chinese ? "所有 App" : "All Apps"
        case .include: return chinese ? "仅指定 App" : "Only Selected"
        case .exclude: return chinese ? "排除指定 App" : "Exclude Selected"
        }
    }
}

struct GestureAppScope: Codable, Equatable, Sendable {
    var mode: GestureAppScopeMode = .all
    var bundleIdentifiers: [String] = []

    init(mode: GestureAppScopeMode = .all, bundleIdentifiers: [String] = []) {
        self.mode = mode
        self.bundleIdentifiers = bundleIdentifiers
    }

    func matches(bundleIdentifier: String?) -> Bool {
        guard mode != .all else { return true }
        guard let bundleIdentifier else { return mode == .exclude }
        let contains = bundleIdentifiers.contains(bundleIdentifier)
        return mode == .include ? contains : !contains
    }

    func overlaps(_ other: GestureAppScope) -> Bool {
        let own = Set(bundleIdentifiers)
        let theirs = Set(other.bundleIdentifiers)
        switch (mode, other.mode) {
        case (.all, .include): return !theirs.isEmpty
        case (.include, .all): return !own.isEmpty
        case (.all, _), (_, .all), (.exclude, .exclude): return true
        case (.include, .include): return !own.isDisjoint(with: theirs)
        case (.include, .exclude): return !own.subtracting(theirs).isEmpty
        case (.exclude, .include): return !theirs.subtracting(own).isEmpty
        }
    }
}

enum GestureActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case keyboardShortcut
    case openURL
    case launchApplication
    case shellScript
    case appleScript
    case delay

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .keyboardShortcut: return chinese ? "发送快捷键" : "Send Shortcut"
        case .openURL: return chinese ? "打开网址" : "Open URL"
        case .launchApplication: return chinese ? "打开应用" : "Launch Application"
        case .shellScript: return chinese ? "运行 Shell 脚本" : "Run Shell Script"
        case .appleScript: return chinese ? "运行 AppleScript" : "Run AppleScript"
        case .delay: return chinese ? "等待延迟" : "Delay"
        }
    }
}

struct GestureAutomationAction: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: GestureActionKind
    var keys: [String]
    var value: String
    var delayMilliseconds: Int

    init(id: UUID = UUID(),
         kind: GestureActionKind = .keyboardShortcut,
         keys: [String] = ["cmd", "w"],
         value: String = "",
         delayMilliseconds: Int = 250) {
        self.id = id
        self.kind = kind
        self.keys = keys
        self.value = value
        self.delayMilliseconds = delayMilliseconds
    }

    static func keyboard(_ keys: [String]) -> GestureAutomationAction {
        GestureAutomationAction(kind: .keyboardShortcut, keys: keys)
    }
}

struct GestureAutomationRule: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var trigger: GestureAutomationTrigger
    var applicationScope: GestureAppScope
    var actions: [GestureAutomationAction]

    var category: GestureRuleCategory { trigger.category }

    init(id: UUID = UUID(),
         name: String,
         isEnabled: Bool = true,
         trigger: GestureAutomationTrigger,
         applicationScope: GestureAppScope = GestureAppScope(),
         actions: [GestureAutomationAction]) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.applicationScope = applicationScope
        self.actions = actions
    }
}

struct GestureEngineSettings: Codable, Equatable, Sendable {
    var launchAtLogin: Bool
    var hideDockIcon: Bool
    var hideMenuBarIcon: Bool
    var useCompatibilityTrackpadMode: Bool
    var debounceMilliseconds: Int
    var logLevel: String
    var diagonalRejectRatio: Double
    var downBiasRatio: Double
    var spreadThreshold: Double
    var minimumSwipeDistance: Double
    var downBiasMinimumY: Double
    var spreadToDistanceRatio: Double
    var liveTriggerDistance: Double

    init(launchAtLogin: Bool = false,
         hideDockIcon: Bool = false,
         hideMenuBarIcon: Bool = false,
         useCompatibilityTrackpadMode: Bool = false,
         debounceMilliseconds: Int = 150,
         logLevel: String = "info",
         diagonalRejectRatio: Double = 0.95,
         downBiasRatio: Double = 0.35,
         spreadThreshold: Double = 0.03,
         minimumSwipeDistance: Double = 0.01,
         downBiasMinimumY: Double = 0.08,
         spreadToDistanceRatio: Double = 2.0,
         liveTriggerDistance: Double = 0.06) {
        self.launchAtLogin = launchAtLogin
        self.hideDockIcon = hideDockIcon
        self.hideMenuBarIcon = hideMenuBarIcon
        self.useCompatibilityTrackpadMode = useCompatibilityTrackpadMode
        self.debounceMilliseconds = max(0, debounceMilliseconds)
        self.logLevel = logLevel
        self.diagonalRejectRatio = diagonalRejectRatio.isFinite ? min(1, max(0, diagonalRejectRatio)) : 0.95
        self.downBiasRatio = downBiasRatio.isFinite ? min(1, max(0, downBiasRatio)) : 0.35
        self.spreadThreshold = spreadThreshold.isFinite ? max(0, spreadThreshold) : 0.03
        self.minimumSwipeDistance = minimumSwipeDistance.isFinite ? max(0, minimumSwipeDistance) : 0.01
        self.downBiasMinimumY = downBiasMinimumY.isFinite ? max(0, downBiasMinimumY) : 0.08
        self.spreadToDistanceRatio = spreadToDistanceRatio.isFinite ? max(0, spreadToDistanceRatio) : 2.0
        self.liveTriggerDistance = liveTriggerDistance.isFinite ? max(0, liveTriggerDistance) : 0.06
    }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, hideDockIcon, hideMenuBarIcon, useCompatibilityTrackpadMode
        case debounceMilliseconds, logLevel, diagonalRejectRatio, downBiasRatio
        case spreadThreshold, minimumSwipeDistance, downBiasMinimumY, spreadToDistanceRatio, liveTriggerDistance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            launchAtLogin: try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            hideDockIcon: try values.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false,
            hideMenuBarIcon: try values.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon) ?? false,
            useCompatibilityTrackpadMode: try values.decodeIfPresent(Bool.self, forKey: .useCompatibilityTrackpadMode) ?? false,
            debounceMilliseconds: try values.decodeIfPresent(Int.self, forKey: .debounceMilliseconds) ?? 150,
            logLevel: try values.decodeIfPresent(String.self, forKey: .logLevel) ?? "info",
            diagonalRejectRatio: try values.decodeIfPresent(Double.self, forKey: .diagonalRejectRatio) ?? 0.95,
            downBiasRatio: try values.decodeIfPresent(Double.self, forKey: .downBiasRatio) ?? 0.35,
            spreadThreshold: try values.decodeIfPresent(Double.self, forKey: .spreadThreshold) ?? 0.03,
            minimumSwipeDistance: try values.decodeIfPresent(Double.self, forKey: .minimumSwipeDistance) ?? 0.01,
            downBiasMinimumY: try values.decodeIfPresent(Double.self, forKey: .downBiasMinimumY) ?? 0.08,
            spreadToDistanceRatio: try values.decodeIfPresent(Double.self, forKey: .spreadToDistanceRatio) ?? 2.0,
            liveTriggerDistance: try values.decodeIfPresent(Double.self, forKey: .liveTriggerDistance) ?? 0.06
        )
    }

    var normalized: GestureEngineSettings {
        GestureEngineSettings(
            launchAtLogin: launchAtLogin,
            hideDockIcon: hideDockIcon,
            hideMenuBarIcon: hideMenuBarIcon,
            useCompatibilityTrackpadMode: useCompatibilityTrackpadMode,
            debounceMilliseconds: debounceMilliseconds,
            logLevel: logLevel,
            diagonalRejectRatio: diagonalRejectRatio,
            downBiasRatio: downBiasRatio,
            spreadThreshold: spreadThreshold,
            minimumSwipeDistance: minimumSwipeDistance,
            downBiasMinimumY: downBiasMinimumY,
            spreadToDistanceRatio: spreadToDistanceRatio,
            liveTriggerDistance: liveTriggerDistance
        )
    }

    var recognizerTuning: TrackpadGestureTuning {
        TrackpadGestureTuning(
            diagonalRejectRatio: CGFloat(diagonalRejectRatio),
            downBiasRatio: CGFloat(downBiasRatio),
            spreadThreshold: CGFloat(spreadThreshold),
            minSwipeDistance: CGFloat(minimumSwipeDistance),
            downBiasMinAbsDy: CGFloat(downBiasMinimumY),
            spreadToDistanceRatio: CGFloat(spreadToDistanceRatio),
            liveTriggerDistance: CGFloat(liveTriggerDistance)
        )
    }
}

enum GestureConfigurationError: LocalizedError, Equatable, Sendable {
    case unsupportedSchema(Int)
    case duplicateIdentity

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported gesture configuration schema version \(version)"
        case .duplicateIdentity:
            return "Duplicate rule or action UUID in gesture configuration"
        }
    }
}

struct GestureAutomationConfiguration: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var rules: [GestureAutomationRule]
    var settings: GestureEngineSettings

    init(schemaVersion: Int = 2,
         rules: [GestureAutomationRule],
         settings: GestureEngineSettings = GestureEngineSettings()) {
        self.schemaVersion = schemaVersion
        self.rules = rules
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, rules, settings }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 2
        guard schemaVersion == 2 else {
            throw GestureConfigurationError.unsupportedSchema(schemaVersion)
        }
        rules = try values.decode([GestureAutomationRule].self, forKey: .rules)
        settings = try values.decodeIfPresent(GestureEngineSettings.self, forKey: .settings) ?? GestureEngineSettings()
    }

    func validateIdentity() throws {
        guard schemaVersion == 2 else {
            throw GestureConfigurationError.unsupportedSchema(schemaVersion)
        }
        guard Set(rules.map(\.id)).count == rules.count,
              rules.allSatisfy({ Set($0.actions.map(\.id)).count == $0.actions.count }) else {
            throw GestureConfigurationError.duplicateIdentity
        }
    }

    static let defaults = GestureAutomationConfiguration(
        rules: [
            GestureAutomationRule(
                name: "三指下滑关闭窗口",
                trigger: .trackpad(TrackpadTriggerSpec(fingers: 3, direction: .down, minimumDistance: 0.22)),
                actions: [.keyboard(["cmd", "w"])]
            ),
            GestureAutomationRule(
                name: "三指左滑后退",
                trigger: .trackpad(TrackpadTriggerSpec(fingers: 3, direction: .left, minimumDistance: 0.15)),
                actions: [.keyboard(["cmd", "["])]
            ),
            GestureAutomationRule(
                name: "三指右滑前进",
                trigger: .trackpad(TrackpadTriggerSpec(fingers: 3, direction: .right, minimumDistance: 0.15)),
                actions: [.keyboard(["cmd", "]"])]
            ),
            GestureAutomationRule(
                name: "三指上滑刷新",
                trigger: .trackpad(TrackpadTriggerSpec(fingers: 3, direction: .up, minimumDistance: 0.15)),
                actions: [.keyboard(["cmd", "r"])]
            ),
            GestureAutomationRule(
                name: "四指下滑隐藏应用",
                trigger: .trackpad(TrackpadTriggerSpec(fingers: 4, direction: .down, minimumDistance: 0.14)),
                actions: [.keyboard(["cmd", "h"])]
            ),
            GestureAutomationRule(
                name: "⌘H → 左方向键",
                trigger: .keyboard(KeyboardTriggerSpec(keys: ["cmd", "h"])),
                actions: [.keyboard(["left"])]
            ),
            GestureAutomationRule(
                name: "⌘J → 下方向键",
                trigger: .keyboard(KeyboardTriggerSpec(keys: ["cmd", "j"])),
                actions: [.keyboard(["down"])]
            ),
            GestureAutomationRule(
                name: "⌘K → 上方向键",
                trigger: .keyboard(KeyboardTriggerSpec(keys: ["cmd", "k"])),
                actions: [.keyboard(["up"])]
            ),
            GestureAutomationRule(
                name: "⌘L → 右方向键",
                trigger: .keyboard(KeyboardTriggerSpec(keys: ["cmd", "l"])),
                actions: [.keyboard(["right"])]
            ),
        ],
        settings: GestureEngineSettings()
    )
}

// MARK: - Keyboard Shortcut & Stateful Hotkey Matcher (`KeyboardShortcut.swift` + `HotkeyListener.swift`)

struct GestureKeyboardShortcut: Equatable, Sendable {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags

    static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn,
    ]
    private static let functionCodes: Set<CGKeyCode> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        123, 124, 125, 126, 115, 119, 116, 121,
    ]

    init?(keys: [String]) {
        let (modifiers, regular) = TrackpadGestureKeyCodec.classifyKeys(keys)
        guard regular.count == 1,
              let code = TrackpadGestureKeyCodec.keyCodeFor(name: regular[0]) else {
            return nil
        }
        self.keyCode = code
        self.modifiers = Self.eventModifiers(TrackpadGestureKeyCodec.modifierFlags(for: modifiers), keyCode: code)
    }

    func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && modifiers == Self.eventModifiers(flags, keyCode: keyCode)
    }

    static func eventModifiers(_ flags: CGEventFlags, keyCode: CGKeyCode) -> CGEventFlags {
        var modifiers = flags.intersection(relevantModifiers)
        if functionCodes.contains(keyCode) {
            modifiers.remove(.maskSecondaryFn)
        }
        return modifiers
    }
}

/// Pure keyDown / keyUp / repeat state machine ported from `HotkeyListener.swift`.
final class GestureHotkeyMatcher {
    enum Disposition: Equatable {
        case passThrough
        case consume(triggered: GestureAutomationRule?)
    }

    private var entries: [(rule: GestureAutomationRule, shortcut: GestureKeyboardShortcut)] = []
    private var pressedRules: [CGKeyCode: (rule: GestureAutomationRule, shortcut: GestureKeyboardShortcut)] = [:]
    private let ownPID: Int64

    init(rules: [GestureAutomationRule] = [], ownPID: pid_t = getpid()) {
        self.ownPID = Int64(ownPID)
        updateRules(rules)
    }

    func updateRules(_ rules: [GestureAutomationRule]) {
        entries = rules.compactMap { rule in
            guard rule.isEnabled,
                  !rule.actions.isEmpty,
                  case .keyboard(let trigger) = rule.trigger,
                  let shortcut = GestureKeyboardShortcut(keys: trigger.keys) else {
                return nil
            }
            return (rule, shortcut)
        }
        pressedRules.removeAll()
    }

    func reset() {
        pressedRules.removeAll()
    }

    func handleKeyEvent(isKeyDown: Bool,
                        keyCode: CGKeyCode,
                        flags: CGEventFlags,
                        isRepeat: Bool,
                        sourcePID: Int64,
                        shouldHandle: Bool,
                        frontmostBundleID: String?) -> Disposition {
        if sourcePID == ownPID {
            return .passThrough
        }
        if isKeyDown {
            if let pressed = pressedRules[keyCode] {
                if shouldHandle,
                   isRepeat,
                   pressed.shortcut.matches(keyCode: keyCode, flags: flags),
                   pressed.rule.applicationScope.matches(bundleIdentifier: frontmostBundleID),
                   case .keyboard(let trigger) = pressed.rule.trigger,
                   trigger.allowRepeat,
                   trigger.phase == .keyDown {
                    return .consume(triggered: pressed.rule)
                }
                return .consume(triggered: nil)
            }
            guard shouldHandle,
                  !isRepeat,
                  let match = entries.first(where: {
                      $0.rule.applicationScope.matches(bundleIdentifier: frontmostBundleID)
                          && $0.shortcut.matches(keyCode: keyCode, flags: flags)
                  }),
                  case .keyboard(let trigger) = match.rule.trigger else {
                return .passThrough
            }
            pressedRules[keyCode] = match
            if trigger.phase == .keyDown {
                return .consume(triggered: match.rule)
            }
            return .consume(triggered: nil)
        } else {
            guard let pressed = pressedRules.removeValue(forKey: keyCode) else {
                return .passThrough
            }
            if shouldHandle,
               case .keyboard(let trigger) = pressed.rule.trigger,
               trigger.phase == .keyUp,
               pressed.rule.applicationScope.matches(bundleIdentifier: frontmostBundleID) {
                return .consume(triggered: pressed.rule)
            }
            return .consume(triggered: nil)
        }
    }
}

// MARK: - Configuration Validator (`ConfigurationValidator.swift`)

enum GestureConfigurationValidator {
    static func warnings(for configuration: GestureAutomationConfiguration, chinese: Bool = true) -> [String] {
        var warnings: [String] = []
        var earlierRules: [GestureAutomationRule] = []

        for rule in configuration.rules where rule.isEnabled {
            let label = rule.name.isEmpty ? rule.id.uuidString : rule.name
            if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(chinese ? "存在没有名称的规则" : "An enabled rule has an empty name")
            }
            if rule.actions.isEmpty {
                warnings.append(chinese ? "“\(label)”没有执行动作" : "\"\(label)\" has no actions")
            }
            if rule.applicationScope.mode != .all && rule.applicationScope.bundleIdentifiers.isEmpty {
                warnings.append(chinese
                    ? "“\(label)”选择了 App 范围，但没有指定 App"
                    : "\"\(label)\" enables app filtering without any selected apps")
            }
            switch rule.trigger {
            case .trackpad(let trigger):
                if !(2...5).contains(trigger.fingers) {
                    warnings.append(chinese ? "“\(label)”的手指数必须为 2–5" : "\"\(label)\" finger count must be 2–5")
                }
                if !trigger.minimumDistance.isFinite || trigger.minimumDistance <= 0 {
                    warnings.append(chinese
                        ? "“\(label)”的触发距离必须大于 0 且为有限值"
                        : "\"\(label)\" minimum distance must be finite and > 0")
                }
                if configuration.settings.useCompatibilityTrackpadMode && trigger.fingers != 2 {
                    warnings.append(chinese
                        ? "“\(label)”需要高级触控板模式，当前兼容模式不会触发该规则"
                        : "\"\(label)\" requires Advanced Trackpad Mode (Compatibility Mode only supports 2-finger events)")
                } else if !configuration.settings.useCompatibilityTrackpadMode
                    && trigger.fingers < 4
                    && [.pinch, .spread].contains(trigger.direction) {
                    warnings.append(chinese
                        ? "“\(label)”在高级模式下的捏合/张开需要 4–5 指；两指捏合请使用兼容模式"
                        : "\"\(label)\" pinch/spread in Advanced Mode requires 4–5 fingers (use Compatibility Mode for 2-finger pinch)")
                }
            case .keyboard(let trigger):
                if GestureKeyboardShortcut(keys: trigger.keys) == nil {
                    warnings.append(chinese
                        ? "“\(label)”需要一个有效的普通按键，可附加修饰键"
                        : "\"\(label)\" requires one valid regular key plus optional modifiers")
                }
            }
            for action in rule.actions where !isValid(action) {
                warnings.append(chinese
                    ? "“\(label)”包含无效的“\(action.kind.title(chinese: true))”动作"
                    : "\"\(label)\" contains an invalid \(action.kind.title(chinese: false)) action")
            }
            if let earlier = earlierRules.first(where: {
                sameTrigger($0.trigger, rule.trigger) && $0.applicationScope.overlaps(rule.applicationScope)
            }) {
                warnings.append(chinese
                    ? "“\(label)”与“\(earlier.name)”使用相同触发器且 App 范围重叠，列表靠前的规则会优先"
                    : "\"\(label)\" shares the same trigger and overlapping app scope with \"\(earlier.name)\"; earlier rules win")
            }
            earlierRules.append(rule)
        }

        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }

    static func isExecutable(_ rule: GestureAutomationRule) -> Bool {
        guard rule.isEnabled, !rule.actions.isEmpty, rule.actions.allSatisfy(isValid) else { return false }
        if rule.applicationScope.mode == .include && rule.applicationScope.bundleIdentifiers.isEmpty {
            return false
        }
        switch rule.trigger {
        case .trackpad(let trigger):
            return (2...5).contains(trigger.fingers)
                && trigger.minimumDistance.isFinite
                && trigger.minimumDistance > 0
        case .keyboard(let trigger):
            return GestureKeyboardShortcut(keys: trigger.keys) != nil
        }
    }

    static func isValid(_ action: GestureAutomationAction) -> Bool {
        switch action.kind {
        case .keyboardShortcut:
            let (_, regular) = TrackpadGestureKeyCodec.classifyKeys(action.keys)
            return !regular.isEmpty && regular.allSatisfy { TrackpadGestureKeyCodec.keyCodeFor(name: $0) != nil }
        case .openURL:
            return URL(string: action.value)?.scheme != nil
        case .launchApplication, .shellScript, .appleScript:
            return !action.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .delay:
            return action.delayMilliseconds >= 0
        }
    }

    private static func sameTrigger(_ lhs: GestureAutomationTrigger, _ rhs: GestureAutomationTrigger) -> Bool {
        switch (lhs, rhs) {
        case (.trackpad(let a), .trackpad(let b)):
            return a.fingers == b.fingers && a.direction == b.direction
        case (.keyboard(let a), .keyboard(let b)):
            guard let first = GestureKeyboardShortcut(keys: a.keys),
                  let second = GestureKeyboardShortcut(keys: b.keys) else { return false }
            return first == second
        default:
            return false
        }
    }
}

// MARK: - Key Names & Legacy Rule Compatibility

enum GestureKeyNames {
    static func display(_ key: String) -> String {
        switch key.lowercased() {
        case "cmd", "command": return "⌘"
        case "option", "opt", "alt": return "⌥"
        case "shift": return "⇧"
        case "ctrl", "control": return "⌃"
        case "fn", "function": return "fn"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "return", "enter": return "↩"
        case "delete", "backspace": return "⌫"
        case "escape", "esc": return "⎋"
        case "space": return "Space"
        default: return key.uppercased()
        }
    }

    static func formatted(_ keys: [String]) -> String {
        keys.map(display).joined(separator: " ")
    }

    static func name(for code: CGKeyCode) -> String? {
        let candidates = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
            + Array(0...9).map(String.init)
            + [
                "space", "return", "tab", "delete", "escape",
                "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
                "left", "right", "up", "down", "home", "end", "pageup", "pagedown",
                "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`",
            ]
        return candidates.first { TrackpadGestureKeyCodec.keyCodeFor(name: $0) == code }
    }
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

    var keysDisplayString: String { keys.joined(separator: "+") }
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
            "cmd", "command", "shift", "option", "opt", "alt", "ctrl", "control", "fn", "function",
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

    // MARK: - Schema v2 + Legacy Schema v1 Config Loader (`ConfigurationStore.swift`)

    private struct ConfigurationHeader: Decodable {
        let schemaVersion: Int?
        let isLegacy: Bool
        private enum CodingKeys: String, CodingKey { case schemaVersion, gestures }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
            isLegacy = values.contains(.gestures)
        }
    }

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
            let logLevel: String?
            let diagonalRejectRatio: Double?
            let downBiasRatio: Double?
            let spreadThreshold: Double?
            let minSwipeDistance: Double?
            let downBiasMinAbsDy: Double?
            let spreadToDistanceRatio: Double?
            let liveTriggerDistance: Double?
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

    /// Loads either Schema v2 (`AutomationConfiguration`) or Schema v1 (`gestures`/`hotkeys`/`settings`) JSON.
    static func decodeAutomationConfiguration(_ data: Data) throws -> GestureAutomationConfiguration {
        let header = try JSONDecoder().decode(ConfigurationHeader.self, from: data)
        if !header.isLegacy || (header.schemaVersion != nil && header.schemaVersion != 1) {
            var current = try JSONDecoder().decode(GestureAutomationConfiguration.self, from: data)
            try current.validateIdentity()
            current.settings = current.settings.normalized
            return current
        }
        let legacy = try JSONDecoder().decode(LegacyConfig.self, from: data)
        var rules = legacy.gestures.map { mapping in
            GestureAutomationRule(
                name: mapping.name,
                trigger: .trackpad(TrackpadTriggerSpec(
                    fingers: mapping.fingers,
                    direction: mapping.direction,
                    minimumDistance: mapping.minDistance
                )),
                actions: [.keyboard(mapping.keys.map { $0.lowercased() })]
            )
        }
        rules += (legacy.hotkeys ?? []).map { mapping in
            GestureAutomationRule(
                name: mapping.name,
                trigger: .keyboard(KeyboardTriggerSpec(keys: mapping.when.map { $0.lowercased() })),
                actions: [.keyboard(mapping.send.map { $0.lowercased() })]
            )
        }
        let old = legacy.settings
        let settings = GestureEngineSettings(
            debounceMilliseconds: max(0, old?.debounceMs ?? 150),
            logLevel: old?.logLevel ?? "info",
            diagonalRejectRatio: old?.diagonalRejectRatio ?? 0.95,
            downBiasRatio: old?.downBiasRatio ?? 0.35,
            spreadThreshold: old?.spreadThreshold ?? 0.03,
            minimumSwipeDistance: old?.minSwipeDistance ?? 0.01,
            downBiasMinimumY: old?.downBiasMinAbsDy ?? 0.08,
            spreadToDistanceRatio: old?.spreadToDistanceRatio ?? 2.0,
            liveTriggerDistance: old?.liveTriggerDistance ?? 0.06
        )
        return GestureAutomationConfiguration(rules: rules, settings: settings)
    }

    static func encodeAutomationConfiguration(_ configuration: GestureAutomationConfiguration) throws -> Data {
        var saved = configuration
        saved.settings = saved.settings.normalized
        try saved.validateIdentity()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(saved)
    }

    static func migrateFromVorssaintLegacy(gestures: [TrackpadGestureRule],
                                           chords: [ChordRemapRule],
                                           debounceMs: Int,
                                           diagonalRejectRatio: Double,
                                           downBiasRatio: Double) -> GestureAutomationConfiguration {
        var rules: [GestureAutomationRule] = gestures.map { g in
            GestureAutomationRule(
                id: g.id,
                name: g.name,
                isEnabled: g.isEnabled,
                trigger: .trackpad(TrackpadTriggerSpec(
                    fingers: g.fingers,
                    direction: g.direction,
                    minimumDistance: g.minDistance
                )),
                actions: [.keyboard(g.keys)]
            )
        }
        let usedIDs = Set(rules.map(\.id))
        rules += chords.map { c in
            GestureAutomationRule(
                id: usedIDs.contains(c.id) ? UUID() : c.id,
                name: c.name,
                isEnabled: c.isEnabled,
                trigger: .keyboard(KeyboardTriggerSpec(keys: c.whenKeys)),
                actions: [.keyboard(c.sendKeys)]
            )
        }
        let settings = GestureEngineSettings(
            debounceMilliseconds: debounceMs,
            diagonalRejectRatio: diagonalRejectRatio,
            downBiasRatio: downBiasRatio
        )
        return GestureAutomationConfiguration(rules: rules, settings: settings)
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
