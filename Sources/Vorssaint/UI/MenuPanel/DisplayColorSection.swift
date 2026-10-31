// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Panel section for the screen colour filter.
struct DisplayColorSection: View {
    @ObservedObject private var l10n = L10n.shared
    var collapsible = true

    var body: some View {
        PanelSection(.displayColor, title: FeatureStrings.displayColor(l10n.language).title,
                     collapsible: collapsible) {
            DisplayColorControls(compact: true)
                .panelCard()
        }
    }
}

/// The filter's controls, shared by the panel and the Energy page: on/off,
/// the mode, and one editor per look. In the automatic mode the edited phase
/// is shown on screen for a moment, so night can be tuned during the day.
struct DisplayColorControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DisplayColorService.shared
    @AppStorage(DefaultsKey.displayColorEnabled) private var enabled = false
    @State private var editedPhase: DisplayColorPhase?
    @State private var optionsExpanded = false
    var compact = true

    private var strings: DisplayColorFeatureStrings { FeatureStrings.displayColor(l10n.language) }
    private var config: DisplayColorConfiguration { service.configuration }
    private var fontSize: CGFloat { compact ? 11.5 : 13 }
    private var captionSize: CGFloat { compact ? 10 : 11.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(strings.enable, isOn: $enabled)
                .font(.system(size: fontSize, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(compact ? .mini : .small)
                .help(strings.enableCaption)
                .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
            if !compact {
                Text(strings.enableCaption)
                    .font(.system(size: captionSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if service.running, service.fluxRunning {
                Label(strings.fluxWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: captionSize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if enabled {
                Picker(strings.title, selection: modeBinding) {
                    ForEach(DisplayColorMode.allCases, id: \.self) { mode in
                        Text(strings.mode(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(compact ? .small : .regular)

                switch config.mode {
                case .manual:
                    DisplayColorSettingEditor(setting: config.manual, strings: strings,
                                              compact: compact) { setting in
                        service.update { $0.manual = setting }
                    }
                case .sun:
                    sunControls
                }
            }
        }
        .onAppear {
            if editedPhase == nil { editedPhase = service.schedule?.phase ?? .night }
        }
    }

    private var modeBinding: Binding<DisplayColorMode> {
        Binding(get: { config.mode },
                set: { mode in service.update { $0.mode = mode } })
    }

    @ViewBuilder
    private var sunControls: some View {
        let phase = editedPhase ?? .night
        if let schedule = service.schedule {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: strings.nowFormat, strings.phase(schedule.phase)))
                    .font(.system(size: captionSize, weight: .semibold))
                Text(String(format: strings.sunTimesFormat,
                            Self.time(schedule.sunrise), Self.time(schedule.sunset)))
                    .font(.system(size: captionSize).monospacedDigit())
                    .foregroundStyle(.secondary)
                if !schedule.usesSunTimes {
                    Text(strings.fallbackTimes)
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        Picker(strings.title, selection: Binding(get: { phase }, set: { editedPhase = $0 })) {
            ForEach(DisplayColorPhase.allCases, id: \.self) { phase in
                Text(strings.phase(phase)).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(compact ? .small : .regular)

        DisplayColorSettingEditor(setting: config.setting(for: phase), strings: strings,
                                  compact: compact) { setting in
            service.update { $0.setSetting(setting, for: phase) }
            if service.schedule?.phase != phase { service.preview(setting) }
        }
        Divider()
        optionsDisclosure
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                    Text(strings.scheduleOptions)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded || !compact {
                DisplayColorScheduleOptions(compact: compact)
                    .padding(.leading, compact ? 19 : 0)
            }
        }
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// Bedtime, fade length and the location the sun times are worked out for.
private struct DisplayColorScheduleOptions: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DisplayColorService.shared
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    let compact: Bool

    private var strings: DisplayColorFeatureStrings { FeatureStrings.displayColor(l10n.language) }
    private var config: DisplayColorConfiguration { service.configuration }
    private var fontSize: CGFloat { compact ? 11 : 13 }
    private var captionSize: CGFloat { compact ? 10 : 11.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.bedtime)
                Spacer(minLength: 8)
                DatePicker(strings.bedtime, selection: bedtimeBinding,
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
            HStack {
                Text(strings.transition)
                Spacer(minLength: 8)
                Text(String(format: strings.minutesFormat, config.transitionMinutes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(strings.transition, value: transitionBinding,
                        in: DisplayColorConfiguration.transitionRange, step: 5)
                    .labelsHidden()
            }
            locationControls
        }
        .font(.system(size: fontSize, weight: .medium))
        .controlSize(compact ? .small : .regular)
        .onAppear(perform: loadCoordinates)
        .onChange(of: config.latitude) { _, _ in loadCoordinates() }
        .onChange(of: config.longitude) { _, _ in loadCoordinates() }
    }

    @ViewBuilder
    private var locationControls: some View {
        HStack(spacing: 8) {
            Button {
                service.locate()
            } label: {
                Label(service.locating ? strings.locating : strings.locate,
                      systemImage: "location.fill")
            }
            .disabled(service.locating)
            if config.hasLocation {
                Button(strings.clearLocation) {
                    service.setLocation(latitude: nil, longitude: nil)
                }
                .buttonStyle(.link)
            }
        }
        if service.locationFailed {
            Text(strings.locationFailed)
                .font(.system(size: captionSize))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 6) {
            TextField(strings.latitude, text: $latitudeText)
                .onSubmit(commitCoordinates)
            TextField(strings.longitude, text: $longitudeText)
                .onSubmit(commitCoordinates)
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: fontSize).monospacedDigit())
    }

    private var bedtimeBinding: Binding<Date> {
        Binding(get: {
            Calendar.current.date(byAdding: .minute, value: config.bedtimeMinutes,
                                  to: Calendar.current.startOfDay(for: Date())) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            service.update { $0.bedtimeMinutes = (parts.hour ?? 23) * 60 + (parts.minute ?? 0) }
        })
    }

    private var transitionBinding: Binding<Int> {
        Binding(get: { config.transitionMinutes },
                set: { value in service.update { $0.transitionMinutes = value } })
    }

    private func loadCoordinates() {
        // The fields read a dot as the decimal mark, so they show one too.
        let posix = Locale(identifier: "en_US_POSIX")
        latitudeText = config.latitude.map { String(format: "%.2f", locale: posix, $0) } ?? ""
        longitudeText = config.longitude.map { String(format: "%.2f", locale: posix, $0) } ?? ""
    }

    private func commitCoordinates() {
        let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: "."))
        let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: "."))
        if let latitude, let longitude,
           DisplayColorSupport.isValidCoordinate(latitude: latitude, longitude: longitude) {
            service.setLocation(latitude: latitude, longitude: longitude)
        } else if latitudeText.isEmpty, longitudeText.isEmpty {
            service.setLocation(latitude: nil, longitude: nil)
        } else {
            loadCoordinates()
        }
    }
}

/// One look: the white balance slider over a strip of the colours it runs
/// through, and the tint wheel with its strength.
struct DisplayColorSettingEditor: View {
    let setting: DisplayColorSetting
    let strings: DisplayColorFeatureStrings
    var compact = true
    let onChange: (DisplayColorSetting) -> Void

    private var fontSize: CGFloat { compact ? 11 : 13 }
    private var wheelSize: CGFloat { compact ? 96 : 128 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(strings.whiteBalance)
                    Spacer(minLength: 4)
                    Text("\(Int(setting.kelvin)) K")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: kelvinBinding, in: DisplayColorSupport.kelvinRange)
                    .controlSize(.small)
                    .accessibilityLabel(strings.whiteBalance)
                LinearGradient(colors: stride(from: DisplayColorSupport.kelvinRange.lowerBound,
                                              through: DisplayColorSupport.kelvinRange.upperBound,
                                              by: 530).map {
                                   Self.color(DisplayColorSupport.whitePoint(kelvin: $0))
                               },
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 4)
                    .clipShape(Capsule())
                    .accessibilityHidden(true)
            }
            HStack(alignment: .center, spacing: 12) {
                ColorWheelPicker(hue: setting.tintHue, strength: setting.tintStrength,
                                 size: wheelSize) { hue, strength in
                    var next = setting
                    next.tintHue = hue
                    next.tintStrength = strength
                    onChange(next)
                }
                .accessibilityLabel(strings.tint)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(strings.tint)
                        Spacer(minLength: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Self.color(DisplayColorSupport.gains(for: setting)))
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 22, height: 12)
                            .accessibilityHidden(true)
                    }
                    HStack {
                        Text(strings.tintStrength)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text("\(Int((setting.tintStrength * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: strengthBinding, in: 0...1)
                        .controlSize(.small)
                        .accessibilityLabel(strings.tintStrength)
                    Button(strings.clearTint) {
                        var next = setting
                        next.tintStrength = 0
                        onChange(next)
                    }
                    .buttonStyle(.link)
                    .disabled(setting.tintStrength == 0)
                }
            }
        }
        .font(.system(size: fontSize, weight: .medium))
    }

    private var kelvinBinding: Binding<Double> {
        Binding(get: { setting.kelvin },
                set: { value in
                    var next = setting
                    next.kelvin = (value / 50).rounded() * 50
                    onChange(next)
                })
    }

    private var strengthBinding: Binding<Double> {
        Binding(get: { setting.tintStrength },
                set: { value in
                    var next = setting
                    next.tintStrength = value
                    onChange(next)
                })
    }

    static func color(_ gains: DisplayColorGains) -> Color {
        Color(red: gains.red, green: gains.green, blue: gains.blue)
    }
}

/// A hue wheel: the angle picks the colour, the distance from the centre how
/// strongly white is pushed toward it.
struct ColorWheelPicker: View {
    let hue: Double
    let strength: Double
    let size: CGFloat
    let onChange: (Double, Double) -> Void

    var body: some View {
        let radius = size / 2
        let angle = hue * 2 * .pi
        let knob = CGPoint(x: radius + cos(angle) * radius * strength,
                           y: radius + sin(angle) * radius * strength)
        ZStack {
            Circle()
                .fill(AngularGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                                          Color(hue: $0, saturation: 1, brightness: 1)
                                      },
                                      center: .center))
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: radius))
            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
            Circle()
                .fill(Color(hue: hue, saturation: strength, brightness: 1))
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 1.5)
                .frame(width: 14, height: 14)
                .position(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let dx = value.location.x - radius
            let dy = value.location.y - radius
            let distance = min(sqrt(dx * dx + dy * dy) / radius, 1)
            var newHue = atan2(dy, dx) / (2 * .pi)
            if newHue < 0 { newHue += 1 }
            onChange(Double(newHue), Double(distance))
        })
    }
}
