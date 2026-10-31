// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Per-channel factors laid over a display's own gamma curve. White is
/// (1, 1, 1); every channel stays in 0...1 so the filter can only take light
/// away, never clip it.
struct DisplayColorGains: Equatable, Codable {
    var red: Double
    var green: Double
    var blue: Double

    static let neutral = DisplayColorGains(red: 1, green: 1, blue: 1)

    var isNeutral: Bool {
        abs(red - 1) < 0.0005 && abs(green - 1) < 0.0005 && abs(blue - 1) < 0.0005
    }

    func mixed(with other: DisplayColorGains, amount: Double) -> DisplayColorGains {
        let t = min(max(amount, 0), 1)
        return DisplayColorGains(red: red + (other.red - red) * t,
                                 green: green + (other.green - green) * t,
                                 blue: blue + (other.blue - blue) * t)
    }

    /// Scales the brightest channel back to one, so a tint shifts the colour
    /// of white instead of dimming the whole screen.
    var normalized: DisplayColorGains {
        let peak = max(red, green, blue)
        guard peak > 0 else { return .neutral }
        return DisplayColorGains(red: red / peak, green: green / peak, blue: blue / peak)
    }
}

/// One look: a white balance plus an optional push toward a hue on the
/// colour wheel. Strength zero means no tint at all, whatever the hue.
struct DisplayColorSetting: Equatable, Codable {
    var kelvin: Double
    var tintHue: Double
    var tintStrength: Double

    init(kelvin: Double, tintHue: Double = 0, tintStrength: Double = 0) {
        self.kelvin = kelvin
        self.tintHue = tintHue
        self.tintStrength = tintStrength
    }

    var sanitized: DisplayColorSetting {
        DisplayColorSetting(
            kelvin: min(max(kelvin.isFinite ? kelvin : DisplayColorSupport.neutralKelvin,
                            DisplayColorSupport.kelvinRange.lowerBound),
                        DisplayColorSupport.kelvinRange.upperBound),
            tintHue: tintHue.isFinite ? tintHue - tintHue.rounded(.down) : 0,
            tintStrength: min(max(tintStrength.isFinite ? tintStrength : 0, 0), 1))
    }
}

/// The parts of the day the automatic mode follows, each with a look of its
/// own: day runs from sunrise to sunset, sunset until bedtime, night until
/// the next sunrise.
enum DisplayColorPhase: String, CaseIterable, Codable {
    case day, sunset, night
}

enum DisplayColorMode: String, CaseIterable, Codable {
    /// Follows sunrise, sunset and bedtime.
    case sun
    /// One fixed look.
    case manual
}

/// Everything the colour filter is configured with, stored as one value so a
/// half-written change can never leave the phases out of step.
struct DisplayColorConfiguration: Equatable, Codable {
    var mode: DisplayColorMode = .sun
    var manual = DisplayColorSetting(kelvin: 4200)
    var day = DisplayColorSetting(kelvin: 6500)
    var sunset = DisplayColorSetting(kelvin: 3400)
    var night = DisplayColorSetting(kelvin: 2700)
    /// Minutes after midnight, local time.
    var bedtimeMinutes = 23 * 60
    /// How long each change of phase fades, in minutes.
    var transitionMinutes = 30
    var latitude: Double?
    var longitude: Double?

    static let transitionRange = 0...120

    func setting(for phase: DisplayColorPhase) -> DisplayColorSetting {
        switch phase {
        case .day: return day
        case .sunset: return sunset
        case .night: return night
        }
    }

    mutating func setSetting(_ setting: DisplayColorSetting, for phase: DisplayColorPhase) {
        switch phase {
        case .day: day = setting.sanitized
        case .sunset: sunset = setting.sanitized
        case .night: night = setting.sanitized
        }
    }

    var hasLocation: Bool {
        guard let latitude, let longitude else { return false }
        return DisplayColorSupport.isValidCoordinate(latitude: latitude, longitude: longitude)
    }

    var sanitized: DisplayColorConfiguration {
        var copy = self
        copy.manual = manual.sanitized
        copy.day = day.sanitized
        copy.sunset = sunset.sanitized
        copy.night = night.sanitized
        copy.bedtimeMinutes = ((bedtimeMinutes % 1440) + 1440) % 1440
        copy.transitionMinutes = min(max(transitionMinutes, Self.transitionRange.lowerBound),
                                     Self.transitionRange.upperBound)
        if !hasLocation {
            copy.latitude = nil
            copy.longitude = nil
        }
        return copy
    }

    /// A stored value, or the defaults when there is none or it no longer
    /// decodes. Missing fields fall back one by one, so a later version can
    /// add settings without discarding the ones a person already chose.
    static func decoded(from data: Data?) -> DisplayColorConfiguration {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DisplayColorConfiguration()
        }
        var config = DisplayColorConfiguration()
        func setting(_ key: String) -> DisplayColorSetting? {
            guard let value = object[key],
                  let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? JSONDecoder().decode(DisplayColorSetting.self, from: data)
        }
        if let raw = object["mode"] as? String, let mode = DisplayColorMode(rawValue: raw) {
            config.mode = mode
        }
        if let value = setting("manual") { config.manual = value }
        if let value = setting("day") { config.day = value }
        if let value = setting("sunset") { config.sunset = value }
        if let value = setting("night") { config.night = value }
        if let value = object["bedtimeMinutes"] as? Int { config.bedtimeMinutes = value }
        if let value = object["transitionMinutes"] as? Int { config.transitionMinutes = value }
        config.latitude = object["latitude"] as? Double
        config.longitude = object["longitude"] as? Double
        return config.sanitized
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}

enum DisplayColorSupport {
    static let kelvinRange: ClosedRange<Double> = 1200...6500
    static let neutralKelvin = 6500.0
    /// How far a full-strength tint pulls the other channels down. Below one
    /// so even the strongest tint keeps the picture readable.
    static let maximumTintDepth = 0.75
    /// Stand-ins for sunrise and sunset when no location is known, or where
    /// the sun does not rise or set that day.
    static let fallbackSunriseMinutes = 7 * 60
    static let fallbackSunsetMinutes = 19 * 60
    /// The bundle identifier of f.lux, which writes the same gamma curves.
    static let fluxBundleIdentifier = "org.herf.Flux"

    static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    // MARK: Colour

    /// The colour of a black body at `kelvin`, relative to 6500 K white.
    /// Tanner Helland's fit of the CIE data, which is smooth over the range
    /// the slider covers.
    static func whitePoint(kelvin: Double) -> DisplayColorGains {
        let clamped = min(max(kelvin, kelvinRange.lowerBound), kelvinRange.upperBound)
        let raw = blackBody(clamped)
        let reference = blackBody(neutralKelvin)
        return DisplayColorGains(red: raw.red / reference.red,
                                 green: raw.green / reference.green,
                                 blue: raw.blue / reference.blue).normalized
    }

    private static func blackBody(_ kelvin: Double) -> DisplayColorGains {
        let t = kelvin / 100
        let red: Double
        let green: Double
        let blue: Double
        if t <= 66 {
            red = 255
            green = 99.4708025861 * log(t) - 161.1195681661
        } else {
            red = 329.698727446 * pow(t - 60, -0.1332047592)
            green = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func channel(_ value: Double) -> Double { min(max(value, 0), 255) / 255 }
        // A floor keeps the reference division defined at the cold end of a
        // channel that the fit takes to zero.
        return DisplayColorGains(red: max(channel(red), 0.001),
                                 green: max(channel(green), 0.001),
                                 blue: max(channel(blue), 0.001))
    }

    /// The fully saturated colour at `hue` (0 red, 1/3 green, 2/3 blue).
    static func hueColor(_ hue: Double) -> DisplayColorGains {
        let h = (hue - hue.rounded(.down)) * 6
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        switch Int(h) {
        case 0: return DisplayColorGains(red: 1, green: x, blue: 0)
        case 1: return DisplayColorGains(red: x, green: 1, blue: 0)
        case 2: return DisplayColorGains(red: 0, green: 1, blue: x)
        case 3: return DisplayColorGains(red: 0, green: x, blue: 1)
        case 4: return DisplayColorGains(red: x, green: 0, blue: 1)
        default: return DisplayColorGains(red: 1, green: 0, blue: x)
        }
    }

    /// A push of white toward `hue`. The hue's own channels stay at one and
    /// the others are lowered, so the result never brightens anything.
    static func tint(hue: Double, strength: Double) -> DisplayColorGains {
        let depth = min(max(strength, 0), 1) * maximumTintDepth
        guard depth > 0 else { return .neutral }
        let color = hueColor(hue)
        return DisplayColorGains(red: 1 - depth * (1 - color.red),
                                 green: 1 - depth * (1 - color.green),
                                 blue: 1 - depth * (1 - color.blue))
    }

    static func gains(for setting: DisplayColorSetting) -> DisplayColorGains {
        let setting = setting.sanitized
        let white = whitePoint(kelvin: setting.kelvin)
        let tint = tint(hue: setting.tintHue, strength: setting.tintStrength)
        return DisplayColorGains(red: white.red * tint.red,
                                 green: white.green * tint.green,
                                 blue: white.blue * tint.blue).normalized
    }

    /// A gamma curve with each channel scaled by its own factor.
    static func scaledTable(_ table: [Float], factor: Double) -> [Float] {
        let factor = Float(min(max(factor, 0), 1))
        guard factor < 1 else { return table }
        return table.map { $0 * factor }
    }

    // MARK: Sun

    /// Sunrise and sunset on the local calendar day containing `date`, from
    /// the almanac algorithm with the standard 90.833° zenith. Nil when the
    /// sun stays up or stays down all day.
    static func sunTimes(on date: Date, latitude: Double, longitude: Double,
                         calendar: Calendar) -> (sunrise: Date, sunset: Date)? {
        guard isValidCoordinate(latitude: latitude, longitude: longitude),
              let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let utcMidnight = utc.date(from: DateComponents(year: day.year, month: day.month,
                                                              day: day.day)),
              let rise = sunEventHours(dayOfYear: dayOfYear, latitude: latitude,
                                       longitude: longitude, rising: true),
              let set = sunEventHours(dayOfYear: dayOfYear, latitude: latitude,
                                      longitude: longitude, rising: false) else { return nil }
        // The algorithm answers a time of day in UTC; the day it belongs to is
        // the one nearest the event's rough solar time at this longitude.
        func place(_ hours: Double, solarHour: Double) -> Date {
            let expected = utcMidnight.addingTimeInterval((solarHour - longitude / 15) * 3600)
            let base = utcMidnight.addingTimeInterval(hours * 3600)
            return [-86400.0, 0, 86400].map { base.addingTimeInterval($0) }
                .min { abs($0.timeIntervalSince(expected)) < abs($1.timeIntervalSince(expected)) }
                ?? base
        }
        return (place(rise, solarHour: 6), place(set, solarHour: 18))
    }

    private static func sunEventHours(dayOfYear: Int, latitude: Double, longitude: Double,
                                      rising: Bool) -> Double? {
        func sin(deg: Double) -> Double { Foundation.sin(deg * .pi / 180) }
        func cos(deg: Double) -> Double { Foundation.cos(deg * .pi / 180) }
        func wrap(_ value: Double, _ range: Double) -> Double {
            let r = value.truncatingRemainder(dividingBy: range)
            return r < 0 ? r + range : r
        }
        let longitudeHour = longitude / 15
        let t = Double(dayOfYear) + ((rising ? 6 : 18) - longitudeHour) / 24
        let anomaly = 0.9856 * t - 3.289
        let trueLongitude = wrap(anomaly + 1.916 * sin(deg: anomaly)
                                 + 0.020 * sin(deg: 2 * anomaly) + 282.634, 360)
        var ascension = wrap(atan(0.91764 * tan(trueLongitude * .pi / 180)) * 180 / .pi, 360)
        ascension += (trueLongitude / 90).rounded(.down) * 90 - (ascension / 90).rounded(.down) * 90
        ascension /= 15
        let sinDeclination = 0.39782 * sin(deg: trueLongitude)
        let cosDeclination = Foundation.cos(asin(sinDeclination))
        let cosHour = (cos(deg: 90.833) - sinDeclination * sin(deg: latitude))
            / (cosDeclination * cos(deg: latitude))
        guard cosHour >= -1, cosHour <= 1 else { return nil }
        let angle = acos(cosHour) * 180 / .pi
        let hour = (rising ? 360 - angle : angle) / 15
        let localMean = hour + ascension - 0.06571 * t - 6.622
        return wrap(localMean - longitudeHour, 24)
    }

    // MARK: Schedule

    struct ScheduleState: Equatable {
        var phase: DisplayColorPhase
        var gains: DisplayColorGains
        /// Whether a fade between two phases is in progress.
        var transitioning: Bool
        var sunrise: Date
        var sunset: Date
        /// False when sunrise and sunset are the fallback clock times.
        var usesSunTimes: Bool
    }

    /// The look the automatic mode puts on screen at `now`. Night holds until
    /// sunrise even if bedtime is set before sunset, so the evening never
    /// comes back after it.
    static func scheduleState(at now: Date, configuration: DisplayColorConfiguration,
                              calendar: Calendar) -> ScheduleState {
        let config = configuration.sanitized
        struct Event { let time: Date; let phase: DisplayColorPhase }
        var events: [Event] = []
        var todaySun: (sunrise: Date, sunset: Date, real: Bool)?
        let today = calendar.startOfDay(for: now)
        for offset in -2...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let sun = sunOrFallback(on: day, configuration: config, calendar: calendar)
            if offset == 0 { todaySun = sun }
            events.append(Event(time: sun.sunrise, phase: .day))
            events.append(Event(time: sun.sunset, phase: .sunset))
            if let bedtime = calendar.date(byAdding: .minute, value: config.bedtimeMinutes, to: day) {
                events.append(Event(time: bedtime, phase: .night))
            }
        }
        events.sort { $0.time < $1.time }

        var phase = DisplayColorPhase.night
        var previous = DisplayColorPhase.night
        var changedAt = Date.distantPast
        for event in events where event.time <= now {
            if phase == .night && event.phase == .sunset { continue }
            guard event.phase != phase else { continue }
            previous = phase
            phase = event.phase
            changedAt = event.time
        }

        let target = gains(for: config.setting(for: phase))
        let fade = Double(config.transitionMinutes) * 60
        let elapsed = now.timeIntervalSince(changedAt)
        let progress = fade > 0 ? min(max(elapsed / fade, 0), 1) : 1
        let shown = progress < 1
            ? gains(for: config.setting(for: previous)).mixed(with: target, amount: progress)
            : target
        let sun = todaySun ?? sunOrFallback(on: today, configuration: config, calendar: calendar)
        return ScheduleState(phase: phase, gains: shown, transitioning: progress < 1,
                             sunrise: sun.sunrise, sunset: sun.sunset, usesSunTimes: sun.real)
    }

    private static func sunOrFallback(on day: Date, configuration: DisplayColorConfiguration,
                                      calendar: Calendar) -> (sunrise: Date, sunset: Date, real: Bool) {
        if let latitude = configuration.latitude, let longitude = configuration.longitude,
           let sun = sunTimes(on: day, latitude: latitude, longitude: longitude, calendar: calendar) {
            return (sun.sunrise, sun.sunset, true)
        }
        let start = calendar.startOfDay(for: day)
        let sunrise = calendar.date(byAdding: .minute, value: fallbackSunriseMinutes, to: start) ?? start
        let sunset = calendar.date(byAdding: .minute, value: fallbackSunsetMinutes, to: start) ?? start
        return (sunrise, sunset, false)
    }
}
