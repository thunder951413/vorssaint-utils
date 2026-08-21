// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FanControlCurveEditor: View {
    let strings: FanControlFeatureStrings
    @Binding var sensor: FanControlTemperatureSource
    @Binding var threshold: Int
    @Binding var accelerationFactor: Double
    let temperatures: [FanControlTemperatureReading]
    let temperatureUnit: TemperatureUnit
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Picker(strings.sensor, selection: $sensor) {
                    ForEach(sourceOptions) { source in
                        Text(sourceName(source)).tag(source)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(disabled)

                Spacer(minLength: 4)

                if let temperature = temperature(for: sensor) {
                    Text(formattedTemperature(temperature))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(strings.threshold)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedTemperature(Double(threshold)))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            }
            Slider(value: thresholdBinding,
                   in: Double(FanControlPolicy.minimumThreshold)...Double(FanControlPolicy.maximumThreshold),
                   step: 1)
                .controlSize(.small)
                .disabled(disabled)

            HStack {
                Text(strings.acceleration)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: strings.accelerationFormat, accelerationFactor))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            }
            Slider(value: $accelerationFactor,
                   in: FanControlPolicy.minimumAccelerationFactor...FanControlPolicy.maximumAccelerationFactor,
                   step: FanControlPolicy.accelerationFactorStep)
                .controlSize(.small)
                .disabled(disabled)

            FanControlAccelerationGraph(
                threshold: threshold,
                accelerationFactor: accelerationFactor,
                currentTemperature: temperature(for: sensor).map { Int($0.rounded()) },
                accessibilityLabel: strings.curveGraph
            )
            .equatable()
            .frame(height: 72)

            Text(strings.accelerationCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { selectAvailableSensorIfNeeded() }
        .onChange(of: sensorAvailabilityToken) { _, _ in selectAvailableSensorIfNeeded() }
    }

    private var sensorAvailabilityToken: String {
        temperatures.map(\.source.rawValue).sorted().joined(separator: ",")
    }

    private var sourceOptions: [FanControlTemperatureSource] {
        let detected = Set(temperatures.map(\.source))
        let base = detected.isEmpty ? Array(FanControlTemperatureSource.allCases) : FanControlTemperatureSource.allCases.filter(detected.contains)
        if base.contains(sensor) { return base }
        return [sensor] + base
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(threshold) },
            set: { threshold = Int($0.rounded()) }
        )
    }

    private func temperature(for source: FanControlTemperatureSource) -> Double? {
        temperatures.first { $0.source == source }?.celsius
    }

    private func formattedTemperature(_ celsius: Double) -> String {
        MetricFormat.temperature(celsius, unit: temperatureUnit)
    }

    private func sourceName(_ source: FanControlTemperatureSource) -> String {
        switch source {
        case .packageCPU: return strings.packageCPU
        case .averageCPU: return strings.averageCPU
        case .hottestCPU: return strings.hottestCPU
        case .averageSoC: return strings.averageSoC
        case .hottestSoC: return strings.hottestSoC
        case .hottestGPU: return strings.hottestGPU
        }
    }

    private func selectAvailableSensorIfNeeded() {
        let detected = Set(temperatures.map(\.source))
        guard !detected.isEmpty, !detected.contains(sensor) else { return }
        sensor = FanControlTemperatureSource.allCases.first(where: detected.contains) ?? sensor
    }
}

private struct FanControlAccelerationGraph: View, Equatable {
    let threshold: Int
    let accelerationFactor: Double
    let currentTemperature: Int?
    let accessibilityLabel: String

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 12)
            let height = max(1, geometry.size.height - 12)
            let domainStart = Double(FanControlPolicy.minimumThreshold)
            let domainEnd = Double(FanControlPolicy.emergencyTemperature)
            let span = max(1, domainEnd - domainStart)

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.035))

                Path { path in
                    path.move(to: CGPoint(x: 6, y: 6 + height))
                    path.addLine(to: CGPoint(
                        x: 6 + CGFloat((Double(threshold) - domainStart) / span) * width,
                        y: 6 + height
                    ))
                    for step in 0...24 {
                        let temperature = Double(threshold)
                            + Double(FanControlPolicy.emergencyTemperature - threshold)
                            * Double(step) / 24
                        let fraction = FanControlPolicy.adjustedFraction(
                            Double(step) / 24, factor: accelerationFactor)
                        let x = 6 + CGFloat((temperature - domainStart) / span) * width
                        let y = 6 + height * (1 - CGFloat(fraction))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.cyan,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let currentTemperature {
                    let current = Double(currentTemperature)
                    if current >= domainStart, current <= domainEnd {
                        let start = Double(threshold)
                        let fraction: CGFloat = {
                            if current >= Double(FanControlPolicy.emergencyTemperature) {
                                return 1
                            }
                            guard current > start else { return 0 }
                            let raw = min(1, max(0,
                                (current - start)
                                    / max(1, Double(FanControlPolicy.emergencyTemperature) - start)))
                            return CGFloat(FanControlPolicy.adjustedFraction(
                                raw, factor: accelerationFactor))
                        }()
                        Circle()
                            .fill(Color.cyan)
                            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                            .frame(width: 8, height: 8)
                            .position(
                                x: 6 + CGFloat((min(domainEnd, max(domainStart, current)) - domainStart) / span) * width,
                                y: 6 + height * (1 - fraction)
                            )
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
