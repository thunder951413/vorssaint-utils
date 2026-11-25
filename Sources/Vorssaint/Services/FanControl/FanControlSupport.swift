// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FanControlFanReading: Codable, Equatable, Identifiable, Sendable {
    let index: Int
    let actualRPM: Double
    let minimumRPM: Double
    let maximumRPM: Double
    let targetRPM: Double
    let isManuallyControlled: Bool

    var id: Int { index }
}

enum FanControlMode: String, Codable, Sendable {
    case system
    case manual
    case curve
}

enum FanControlTemperatureSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case packageCPU
    case averageCPU
    case hottestCPU
    case averageSoC
    case hottestSoC
    case hottestGPU

    var id: String { rawValue }
}

struct FanControlTemperatureReading: Codable, Equatable, Sendable {
    let source: FanControlTemperatureSource
    let celsius: Double
}

struct FanControlCurvePoint: Codable, Equatable, Sendable {
    var temperature: Int
    var coolingLevel: Int
}

struct FanControlCurve: Codable, Equatable, Sendable {
    var sensor: FanControlTemperatureSource
    var points: [FanControlCurvePoint]
}

struct FanControlConfiguration: Codable, Equatable, Sendable {
    var mode: FanControlMode
    var manualLevel: Int
    var curves: [FanControlCurve]
    var sensor: FanControlTemperatureSource
    var threshold: Int
    var accelerationFactor: Double

    static let defaultCurve = FanControlCurve(
        sensor: .hottestCPU,
        points: [
            FanControlCurvePoint(temperature: FanControlPolicy.defaultThreshold,
                                 coolingLevel: 0),
            FanControlCurvePoint(temperature: FanControlPolicy.emergencyTemperature,
                                 coolingLevel: 100),
        ]
    )

    static func manual(level: Int) -> FanControlConfiguration {
        FanControlConfiguration(mode: .manual, manualLevel: level,
                                curves: [],
                                sensor: FanControlPolicy.defaultSensor,
                                threshold: FanControlPolicy.defaultThreshold,
                                accelerationFactor: FanControlPolicy.defaultAccelerationFactor)
    }

    static func curve(sensor: FanControlTemperatureSource = FanControlPolicy.defaultSensor,
                      threshold: Int = FanControlPolicy.defaultThreshold,
                      accelerationFactor: Double = FanControlPolicy.defaultAccelerationFactor) -> FanControlConfiguration {
        FanControlConfiguration(mode: .curve,
                                manualLevel: FanControlPolicy.defaultCoolingLevel,
                                curves: [],
                                sensor: sensor,
                                threshold: threshold,
                                accelerationFactor: accelerationFactor)
    }

    enum CodingKeys: String, CodingKey {
        case mode, manualLevel, curves, sensor, threshold, accelerationFactor
    }

    init(mode: FanControlMode, manualLevel: Int, curves: [FanControlCurve],
         sensor: FanControlTemperatureSource, threshold: Int, accelerationFactor: Double) {
        self.mode = mode
        self.manualLevel = manualLevel
        self.curves = curves
        self.sensor = sensor
        self.threshold = threshold
        self.accelerationFactor = accelerationFactor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(FanControlMode.self, forKey: .mode)
        manualLevel = try container.decode(Int.self, forKey: .manualLevel)
        curves = try container.decodeIfPresent([FanControlCurve].self, forKey: .curves) ?? []
        sensor = try container.decodeIfPresent(FanControlTemperatureSource.self, forKey: .sensor)
            ?? curves.first?.sensor
            ?? FanControlPolicy.defaultSensor
        if let threshold = try container.decodeIfPresent(Int.self, forKey: .threshold) {
            self.threshold = threshold
        } else if let stored = curves.first?.points.first?.temperature {
            self.threshold = FanControlPolicy.clampedThreshold(stored)
        } else {
            self.threshold = FanControlPolicy.defaultThreshold
        }
        accelerationFactor = try container.decodeIfPresent(Double.self, forKey: .accelerationFactor)
            ?? FanControlPolicy.defaultAccelerationFactor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(manualLevel, forKey: .manualLevel)
        try container.encode(curves, forKey: .curves)
        try container.encode(sensor, forKey: .sensor)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(accelerationFactor, forKey: .accelerationFactor)
    }

    static func encodeCurves(_ curves: [FanControlCurve]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(curves) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeCurves(_ value: String) -> [FanControlCurve]? {
        guard let data = value.data(using: .utf8),
              let curves = try? JSONDecoder().decode([FanControlCurve].self, from: data),
              FanControlPolicy.validCurves(curves) else { return nil }
        return curves
    }

    static var defaultCurvesStorage: String {
        encodeCurves([defaultCurve]) ?? "[]"
    }
}

struct FanControlSnapshot: Codable, Equatable, Sendable {
    var fans: [FanControlFanReading]
    var isCooling: Bool
    var endsAt: Date?
    var stopReason: FanControlStopReason?
    var coolingLevel: Int?
    var configuration: FanControlConfiguration?
    var temperatures: [FanControlTemperatureReading]?

    static let empty = FanControlSnapshot(fans: [], isCooling: false,
                                          endsAt: nil, stopReason: nil,
                                          coolingLevel: nil,
                                          configuration: nil,
                                          temperatures: nil)
}

enum FanControlStopReason: String, Codable, Equatable, Sendable {
    case timeLimit
    case appDisconnected
    case heartbeatLost
    case hardwareChanged
    case thermalPressure
    case temperatureUnavailable
    case recovery
}

enum FanControlErrorCode: String, Codable, Equatable, Error, Sendable {
    case noFans
    case unsupportedHardware
    case alreadyControlled
    case authorizationRequired
    case helperUnavailable
    case controlFailed
}

struct FanControlResponse: Codable, Equatable, Sendable {
    let succeeded: Bool
    let snapshot: FanControlSnapshot
    let error: FanControlErrorCode?

    static func success(_ snapshot: FanControlSnapshot) -> FanControlResponse {
        FanControlResponse(succeeded: true, snapshot: snapshot, error: nil)
    }

    static func failure(_ error: FanControlErrorCode,
                        snapshot: FanControlSnapshot = .empty) -> FanControlResponse {
        FanControlResponse(succeeded: false, snapshot: snapshot, error: error)
    }
}

enum FanControlCurveDemand: Equatable, Sendable {
    case cooling(Int)
    case belowThreshold
    case unavailable
}

enum FanControlPolicy {
    /// Retained only for the legacy XPC entry point used by older app builds.
    static let coolingDuration: TimeInterval = 15 * 60
    static let heartbeatLimit: TimeInterval = 7
    static let verificationFailureLimit = 3
    static let temperatureFailureLimit = 3
    static let maximumFanCount = 8
    static let maximumSaneRPM = 20_000.0
    static let minimumCoolingLevel = 0
    static let maximumCoolingLevel = 100
    static let coolingLevelStep = 5
    static let defaultCoolingLevel = maximumCoolingLevel
    static let minimumCurveTemperature = 20
    static let maximumCurveTemperature = 110
    static let minimumCurvePointCount = 2
    static let maximumCurvePointCount = 8
    static let maximumCurveCount = FanControlTemperatureSource.allCases.count
    static let curveHysteresis = 3.0
    static let defaultSensor = FanControlTemperatureSource.packageCPU
    static let minimumThreshold = 40
    static let maximumThreshold = 80
    static let defaultThreshold = 68
    static let emergencyTemperature = 90
    static let minimumAccelerationFactor = 0.5
    static let maximumAccelerationFactor = 2.0
    static let accelerationFactorStep = 0.1
    static let defaultAccelerationFactor = 1.0
    static let takeoverMarginRPM = 100.0
    /// After taking over, a curve keeps control at least this long before it
    /// may hand back, so sensor noise around the threshold cannot make the fans
    /// spin up and down (or replay the stopped-fan start) every few seconds.
    /// It only ever delays handing back, never raising the fans.
    static let minimumCurveHoldDuration: TimeInterval = 30
    /// Consecutive app-side polls that must agree before a takeover is sent.
    static let takeoverConfirmationSamples = 2
    /// Delay before an automatic takeover is retried after the helper refused it.
    static let takeoverRetryBackoff: TimeInterval = 30
    /// Pause after a clean handback so macOS's controller settles its own target
    /// before automatic re-takeover evaluates against it again.
    static let handbackCooldown: TimeInterval = 15
    /// Asymmetric temperature smoothing (1 s ticks): responsive on warming so
    /// sustained loads cool promptly, gentler on cooling so brief lulls and
    /// sensor jitter do not make the fans audibly hunt up and down.
    static let temperatureSmoothingUp = 0.25
    static let temperatureSmoothingDown = 0.12
    /// Consecutive ticks at raw emergency heat that bypass smoothing lag.
    static let emergencyConfirmationTicks = 2
    /// Slew/dwell tuning for automatic level updates: ramp up smoothly every
    /// second, and wait for sustained lower demand before gliding down 5% at a
    /// time.
    static let stepUpInterval: TimeInterval = 1
    static let stepDownDwellDuration: TimeInterval = 5
    static let fastRampGap = 20
    /// Multi-sensor protective floor enforced while manual/curve mode owns the
    /// fans. Replaces periodic firmware handovers (which audibly spun fans down
    /// and up) by continuously watching all chip, GPU, battery and OS thermal
    /// pressure signals without touching fan mode.
    static let safetyHotDieStart = 78.0
    static let safetyHotDieFull = 95.0
    static let safetyAverageDieStart = 72.0
    static let safetyAverageDieFull = 88.0
    static let safetyGPUStart = 72.0
    static let safetyGPUFull = 88.0
    static let safetyBatteryStart = 39.0
    static let safetyBatteryFull = 46.0
    static let safetyFairThermalFloor = 50
    static let safetyEmergencyTemperature = 95.0

    static func isAutomaticMode(_ mode: UInt8) -> Bool {
        mode == 0 || mode == 3
    }

    static func fanCount(from value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = value.rounded()
        guard abs(value - rounded) < 0.001 else { return nil }
        let count = Int(rounded)
        return (1...maximumFanCount).contains(count) ? count : nil
    }

    static func validBounds(minimum: Double, maximum: Double) -> Bool {
        minimum.isFinite && maximum.isFinite
            && minimum >= 0 && maximum > minimum && maximum <= maximumSaneRPM
    }

    static func validReading(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumSaneRPM
    }

    static func validCoolingLevel(_ level: Int) -> Bool {
        (minimumCoolingLevel...maximumCoolingLevel).contains(level)
            && level.isMultiple(of: coolingLevelStep)
    }

    static func targetRPMMatches(target: Double, expected: Double) -> Bool {
        target.isFinite && expected.isFinite
            && abs(target - expected) <= max(2, expected * 0.001)
    }

    /// Not every Mac exposes `Ftst`. Where it is present the unlock write has to
    /// succeed; where it is absent there is nothing to force and nothing to fail.
    static func forceTestSatisfied(keyExists: Bool, writeSucceeded: Bool) -> Bool {
        !keyExists || writeSucceeded
    }

    static func coolingTargetRPM(minimum: Double, maximum: Double,
                                 level: Int) -> Double? {
        guard validBounds(minimum: minimum, maximum: maximum),
              validCoolingLevel(level) else { return nil }
        return minimum + (maximum - minimum) * Double(level) / 100
    }

    static func validConfiguration(_ configuration: FanControlConfiguration) -> Bool {
        switch configuration.mode {
        case .system:
            return true
        case .manual:
            return validCoolingLevel(configuration.manualLevel)
        case .curve:
            return validThreshold(configuration.threshold)
                && validAccelerationFactor(configuration.accelerationFactor)
        }
    }

    static func validThreshold(_ threshold: Int) -> Bool {
        (minimumThreshold...maximumThreshold).contains(threshold)
    }

    static func clampedThreshold(_ threshold: Int) -> Int {
        min(maximumThreshold, max(minimumThreshold, threshold))
    }

    static func validAccelerationFactor(_ factor: Double) -> Bool {
        factor.isFinite
            && factor >= minimumAccelerationFactor
            && factor <= maximumAccelerationFactor
    }

    static func clampAccelerationFactor(_ factor: Double) -> Double {
        min(maximumAccelerationFactor, max(minimumAccelerationFactor, factor))
    }

    static func adjustedFraction(_ fraction: Double, factor: Double) -> Double {
        let fraction = min(max(fraction, 0), 1)
        guard fraction > 0, fraction < 1 else { return fraction }
        return pow(fraction, 1 / clampAccelerationFactor(factor))
    }

    static func steppedCoolingLevel(fromFraction fraction: Double) -> Int {
        let raw = min(1, max(0, fraction)) * Double(maximumCoolingLevel)
        let stepped = Int((raw / Double(coolingLevelStep)).rounded()) * coolingLevelStep
        return min(maximumCoolingLevel, max(minimumCoolingLevel, stepped))
    }

    static func ceilingCoolingLevel(fromFraction fraction: Double) -> Int {
        let raw = min(1, max(0, fraction)) * Double(maximumCoolingLevel)
        let stepped = Int(ceil(raw / Double(coolingLevelStep) - 1e-9)) * coolingLevelStep
        return min(maximumCoolingLevel, max(minimumCoolingLevel, stepped))
    }

    static func validCurves(_ curves: [FanControlCurve]) -> Bool {
        guard (1...maximumCurveCount).contains(curves.count),
              Set(curves.map(\.sensor)).count == curves.count else { return false }
        return curves.allSatisfy(validCurve)
    }

    static func validCurve(_ curve: FanControlCurve) -> Bool {
        guard (minimumCurvePointCount...maximumCurvePointCount).contains(curve.points.count) else {
            return false
        }
        for (index, point) in curve.points.enumerated() {
            guard (minimumCurveTemperature...maximumCurveTemperature).contains(point.temperature),
                  validCoolingLevel(point.coolingLevel) else { return false }
            if index > 0 {
                let previous = curve.points[index - 1]
                guard point.temperature > previous.temperature,
                      point.coolingLevel >= previous.coolingLevel else { return false }
            }
        }
        return true
    }

    static func curveDemand(sensor: FanControlTemperatureSource,
                            threshold: Int,
                            accelerationFactor: Double,
                            temperatures: [FanControlTemperatureReading],
                            previousLevel: Int? = nil) -> FanControlCurveDemand {
        guard validThreshold(threshold), validAccelerationFactor(accelerationFactor) else {
            return .unavailable
        }
        guard let temperature = temperatures.first(where: { $0.source == sensor })?.celsius,
              validTemperature(temperature) else {
            return .unavailable
        }
        if temperature >= Double(emergencyTemperature) {
            return .cooling(maximumCoolingLevel)
        }
        let start = Double(threshold)
        let isActive = previousLevel != nil
            ? temperature > start - curveHysteresis
            : temperature > start
        guard isActive else { return .belowThreshold }
        let span = max(1, Double(emergencyTemperature) - start)
        let fraction = min(1, max(0, (temperature - start) / span))
        return .cooling(steppedCoolingLevel(
            fromFraction: adjustedFraction(fraction, factor: accelerationFactor)))
    }

    static func shouldTakeOver(level: Int, fans: [FanControlFanReading]) -> Bool {
        guard validCoolingLevel(level), !fans.isEmpty else { return false }
        if level >= maximumCoolingLevel {
            return fans.contains { fan in
                guard validBounds(minimum: fan.minimumRPM, maximum: fan.maximumRPM) else {
                    return false
                }
                return max(fan.actualRPM, fan.targetRPM) < fan.maximumRPM - 25
            }
        }
        guard level > minimumCoolingLevel else { return false }
        return fans.allSatisfy { fan in
            guard let curveRPM = coolingTargetRPM(minimum: fan.minimumRPM,
                                                  maximum: fan.maximumRPM,
                                                  level: level) else { return false }
            return curveRPM >= max(fan.actualRPM, fan.targetRPM) + takeoverMarginRPM
        }
    }

    /// A curve only ever adds cooling on top of what the system was doing. Once
    /// it asks for less than the speed the system ran when the curve took over,
    /// the system's own controller was already doing better and gets it back.
    static func shouldHandBack(requestedLevel: Int, floorLevel: Int) -> Bool {
        validCoolingLevel(requestedLevel)
            && requestedLevel < maximumCoolingLevel
            && requestedLevel < floorLevel
    }

    static func thermalStateBlocksTakeover(_ thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .serious || thermalState == .critical
    }

    static func smoothedTemperature(previous: Double?, sample: Double) -> Double {
        guard sample.isFinite else { return previous ?? sample }
        guard let previous, previous.isFinite else { return sample }
        let alpha = sample >= previous ? temperatureSmoothingUp : temperatureSmoothingDown
        return previous + alpha * (sample - previous)
    }

    /// Continuous multi-sensor protective floor computed purely from read-only
    /// sensors and macOS thermal pressure, ensuring our applied speed never
    /// under-cools another hot die, GPU, battery or elevated thermal state.
    static func safetyCoolingLevel(
        temperatures: [FanControlTemperatureReading],
        batteryTemperature: Double? = nil,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) -> Int {
        if thermalStateBlocksTakeover(thermalState) {
            return maximumCoolingLevel
        }
        var floor = thermalState == .fair ? safetyFairThermalFloor : minimumCoolingLevel
        for reading in temperatures where validTemperature(reading.celsius) {
            let demand: Int
            switch reading.source {
            case .hottestCPU, .hottestSoC, .packageCPU:
                demand = linearSafetyLevel(reading.celsius,
                                           start: safetyHotDieStart,
                                           full: safetyHotDieFull)
            case .averageCPU, .averageSoC:
                demand = linearSafetyLevel(reading.celsius,
                                           start: safetyAverageDieStart,
                                           full: safetyAverageDieFull)
            case .hottestGPU:
                demand = linearSafetyLevel(reading.celsius,
                                           start: safetyGPUStart,
                                           full: safetyGPUFull)
            }
            floor = max(floor, demand)
        }
        if let batteryTemperature, validTemperature(batteryTemperature) {
            floor = max(floor, linearSafetyLevel(batteryTemperature,
                                                 start: safetyBatteryStart,
                                                 full: safetyBatteryFull))
        }
        return floor
    }

    private static func linearSafetyLevel(_ temperature: Double,
                                          start: Double,
                                          full: Double) -> Int {
        guard temperature > start, full > start else { return minimumCoolingLevel }
        if temperature >= full { return maximumCoolingLevel }
        return ceilingCoolingLevel(fromFraction: (temperature - start) / (full - start))
    }

    /// Smoothly advances the active cooling level toward `desired` so sensor
    /// jitter and brief workload lulls cannot make the fans audibly hunt up
    /// and down. Upward steps respond quickly; downward steps wait for a
    /// sustained lower demand and glide down one step at a time.
    static func nextCoolingLevel(
        current: Int,
        desired: Int,
        now: TimeInterval,
        lastChangeAt: TimeInterval?,
        stepDownCandidateSince: TimeInterval?,
        urgent: Bool = false
    ) -> (level: Int, stepDownCandidateSince: TimeInterval?) {
        let target = min(maximumCoolingLevel, max(minimumCoolingLevel, desired))
        guard target != current else { return (current, nil) }
        if target > current {
            if urgent || target >= maximumCoolingLevel {
                return (target, nil)
            }
            if let lastChangeAt, now - lastChangeAt < stepUpInterval {
                return (current, nil)
            }
            let step = (target - current >= fastRampGap)
                ? coolingLevelStep * 2
                : coolingLevelStep
            return (min(target, current + step), nil)
        }
        guard let since = stepDownCandidateSince else {
            return (current, now)
        }
        guard now - since >= stepDownDwellDuration else {
            return (current, since)
        }
        let next = max(target, current - coolingLevelStep)
        return (next, next > target ? now : nil)
    }

    static func curveHoldElapsed(startedAt start: TimeInterval?, now: TimeInterval) -> Bool {
        guard let start else { return true }
        return now - start >= minimumCurveHoldDuration
    }

    /// Ceiling-stepped level that guarantees `coolingTargetRPM` is at least
    /// `max(actualRPM, targetRPM)` on every fan so takeover never slows fans
    /// below what macOS was already running.
    static func floorCoolingLevel(fans: [FanControlFanReading]) -> Int {
        let levels = fans.compactMap { fan -> Int? in
            guard validBounds(minimum: fan.minimumRPM, maximum: fan.maximumRPM) else { return nil }
            let floorRPM = min(fan.maximumRPM, max(fan.minimumRPM, max(fan.actualRPM, fan.targetRPM)))
            let fraction = (floorRPM - fan.minimumRPM) / (fan.maximumRPM - fan.minimumRPM)
            return ceilingCoolingLevel(fromFraction: fraction)
        }
        return levels.max() ?? minimumCoolingLevel
    }

    static func appliedCoolingLevel(_ level: Int, floorLevel: Int) -> Int {
        guard validCoolingLevel(level) else { return floorLevel }
        if level >= maximumCoolingLevel { return maximumCoolingLevel }
        return max(level, min(maximumCoolingLevel, max(minimumCoolingLevel, floorLevel)))
    }

    static func interpolatedCoolingLevel(points: [FanControlCurvePoint],
                                         temperature: Double) -> Int {
        guard let first = points.first, let last = points.last else {
            return minimumCoolingLevel
        }
        if temperature <= Double(first.temperature) { return first.coolingLevel }
        if temperature >= Double(last.temperature) { return last.coolingLevel }
        for index in 1..<points.count {
            let upper = points[index]
            guard temperature <= Double(upper.temperature) else { continue }
            let lower = points[index - 1]
            let progress = (temperature - Double(lower.temperature))
                / Double(upper.temperature - lower.temperature)
            let raw = Double(lower.coolingLevel)
                + Double(upper.coolingLevel - lower.coolingLevel) * progress
            let stepped = Int(ceil(raw / Double(coolingLevelStep) - 1e-9))
                * coolingLevelStep
            return min(maximumCoolingLevel, max(minimumCoolingLevel, stepped))
        }
        return last.coolingLevel
    }

    static func validTemperature(_ value: Double) -> Bool {
        value.isFinite && value >= 1 && value < 125
    }

    static func aggregatedTemperatures(
        cpuReadings: [(key: String, value: Double)],
        gpuReadings: [Double],
        packageReadings: [Double] = [],
        platform: CPUTemperaturePlatform
    ) -> [FanControlTemperatureReading] {
        let validCPU = cpuReadings.filter {
            $0.value >= TemperatureSensorSelector.minimumChipTemperature
                && validTemperature($0.value)
        }
        let preferredCPU = validCPU.filter {
            TemperatureSensorSelector.isCPUCoreKey($0.key, platform: platform)
        }
        let cpu: [Double]
        if TemperatureSensorSelector.hasCPUCoreSet(platform: platform) {
            cpu = preferredCPU.map(\.value)
        } else if platform == .generic {
            cpu = validCPU.map(\.value)
        } else {
            cpu = []
        }
        let gpu = gpuReadings.filter {
            $0 >= TemperatureSensorSelector.minimumChipTemperature && validTemperature($0)
        }
        let soc = cpu + gpu
        let package = packageReadings.first {
            $0 >= TemperatureSensorSelector.minimumChipTemperature && validTemperature($0)
        }

        var readings: [FanControlTemperatureReading] = []
        if let package {
            readings.append(.init(source: .packageCPU, celsius: package))
        }
        if !cpu.isEmpty {
            readings.append(.init(source: .averageCPU,
                                  celsius: cpu.reduce(0, +) / Double(cpu.count)))
            if let hottest = cpu.max() {
                readings.append(.init(source: .hottestCPU, celsius: hottest))
            }
        }
        if !soc.isEmpty {
            readings.append(.init(source: .averageSoC,
                                  celsius: soc.reduce(0, +) / Double(soc.count)))
            if let hottest = soc.max() {
                readings.append(.init(source: .hottestSoC, celsius: hottest))
            }
        }
        if let hottest = gpu.max() {
            readings.append(.init(source: .hottestGPU, celsius: hottest))
        }
        return readings
    }

    static func telemetryReadings(expectedCount: Int,
                                  readings: [Double?]) -> [Double]? {
        guard (1...maximumFanCount).contains(expectedCount),
              readings.count == expectedCount else { return nil }
        let values = readings.compactMap { $0 }
        guard values.count == expectedCount,
              values.allSatisfy(validReading) else { return nil }
        return values
    }

    static func menuBarValue(for speeds: [Double]) -> String? {
        guard !speeds.isEmpty, speeds.allSatisfy(validReading) else { return nil }
        return speeds.map { String(Int($0.rounded())) }.joined(separator: "/")
    }

    static func menuBarWidthUnits(fanCount: Int) -> Int {
        guard (1...maximumFanCount).contains(fanCount) else { return 0 }
        return 7 + fanCount * 5 + (fanCount - 1)
    }

    static func restoreReason(now: Date,
                              endsAt: Date?,
                              heartbeatAge: TimeInterval,
                              verificationFailures: Int,
                              temperatureFailures: Int = 0,
                              thermalState: ProcessInfo.ThermalState) -> FanControlStopReason? {
        if let endsAt, now >= endsAt { return .timeLimit }
        if heartbeatAge > heartbeatLimit { return .heartbeatLost }
        if verificationFailures >= verificationFailureLimit { return .hardwareChanged }
        if temperatureFailures >= temperatureFailureLimit { return .temperatureUnavailable }
        if thermalStateBlocksTakeover(thermalState) {
            return .thermalPressure
        }
        return nil
    }
}

enum SMCValueCodec {
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Double(Float32(bitPattern: bits))
            return value.isFinite ? value : nil
        case "fpe2" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "sp78" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(UInt32(bytes[0]) << 24
                          | UInt32(bytes[1]) << 16
                          | UInt32(bytes[2]) << 8
                          | UInt32(bytes[3]))
        case "ioft" where bytes.count == 8:
            var raw: UInt64 = 0
            for (offset, byte) in bytes.enumerated() {
                raw |= UInt64(byte) << UInt64(offset * 8)
            }
            return Double(raw) / 65_536.0
        default:
            return nil
        }
    }

    static func encode(_ value: Double, type: String, size: Int) -> [UInt8]? {
        guard value.isFinite, value >= 0 else { return nil }
        switch type {
        case "flt " where size == 4:
            let float = Float32(value)
            guard float.isFinite else { return nil }
            let bits = float.bitPattern
            return [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                    UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
        case "fpe2" where size == 2:
            let scaled = (value * 4).rounded()
            guard scaled <= Double(UInt16.max) else { return nil }
            let raw = UInt16(scaled)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui8 " where size == 1:
            guard value.rounded() == value, value <= Double(UInt8.max) else { return nil }
            return [UInt8(value)]
        case "ui16" where size == 2:
            guard value.rounded() == value, value <= Double(UInt16.max) else { return nil }
            let raw = UInt16(value)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui32" where size == 4:
            guard value.rounded() == value, value <= Double(UInt32.max) else { return nil }
            let raw = UInt32(value)
            return [UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff),
                    UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        default:
            return nil
        }
    }
}
