// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The colour filter's pure half: white balance and tint maths, sun times,
/// the phase schedule and the stored configuration.
enum DisplayColorTests {
    static func run(_ suite: TestSuite) {
        colour(suite)
        sun(suite)
        schedule(suite)
        configuration(suite)
    }

    private static func colour(_ suite: TestSuite) {
        suite.expect(DisplayColorSupport.whitePoint(kelvin: 6500).isNeutral,
                     "6500 K is the untouched white")
        let warm = DisplayColorSupport.whitePoint(kelvin: 2700)
        suite.expect(warm.red == 1 && warm.green < 1 && warm.blue < warm.green,
                     "a warm white keeps red and lowers blue the most")
        let warmer = DisplayColorSupport.whitePoint(kelvin: 1900)
        suite.expect(warmer.blue < warm.blue && warmer.green < warm.green,
                     "lower temperatures are warmer")
        suite.expect(DisplayColorSupport.whitePoint(kelvin: 100) == DisplayColorSupport.whitePoint(kelvin: 1200),
                     "temperatures clamp to the slider range")

        suite.expect(DisplayColorSupport.tint(hue: 0.4, strength: 0).isNeutral,
                     "no strength means no tint, whatever the hue")
        let red = DisplayColorSupport.tint(hue: 0, strength: 1)
        suite.expectClose(red.red, 1, "a red tint keeps red")
        suite.expectClose(red.green, 1 - DisplayColorSupport.maximumTintDepth, "a red tint lowers green")
        suite.expectClose(red.blue, 1 - DisplayColorSupport.maximumTintDepth, "a red tint lowers blue")
        let blue = DisplayColorSupport.hueColor(2.0 / 3)
        suite.expect(blue == DisplayColorGains(red: 0, green: 0, blue: 1), "two thirds round the wheel is blue")

        let mixed = DisplayColorSupport.gains(for: DisplayColorSetting(kelvin: 3000, tintHue: 0.6,
                                                                      tintStrength: 0.5))
        suite.expectClose(max(mixed.red, mixed.green, mixed.blue), 1,
                          "a combined look keeps its brightest channel at full")
        suite.expect([mixed.red, mixed.green, mixed.blue].allSatisfy { $0 >= 0 && $0 <= 1 },
                     "every channel stays within the curve")

        let half = DisplayColorGains.neutral.mixed(with: DisplayColorGains(red: 1, green: 0.5, blue: 0),
                                                   amount: 0.5)
        suite.expect(half == DisplayColorGains(red: 1, green: 0.75, blue: 0.5), "fades mix channel by channel")
        suite.expect(DisplayColorSupport.scaledTable([0, 0.5, 1], factor: 0.5) == [0, 0.25, 0.5]
                        && DisplayColorSupport.scaledTable([0, 0.3, 1], factor: 1) == [0, 0.3, 1],
                     "curves scale per channel and factor one is bit exact")
    }

    private static var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private static func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 6) -> Date {
        shanghai.date(from: DateComponents(year: 2026, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private static func sun(_ suite: TestSuite) {
        // Beijing on the June solstice: sunrise 04:46, sunset 19:46.
        let beijing = DisplayColorSupport.sunTimes(on: date(21, 12, 0), latitude: 39.9,
                                                   longitude: 116.4, calendar: shanghai)
        suite.expect(beijing.map { abs($0.sunrise.timeIntervalSince(date(21, 4, 46))) < 6 * 60 } == true,
                     "Beijing's solstice sunrise lands within minutes")
        suite.expect(beijing.map { abs($0.sunset.timeIntervalSince(date(21, 19, 46))) < 6 * 60 } == true,
                     "Beijing's solstice sunset lands within minutes")
        // A place west of Greenwich, read in its own time zone.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let ny = DisplayColorSupport.sunTimes(on: newYork.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!,
                                              latitude: 40.71, longitude: -74.01, calendar: newYork)
        let nySunrise = newYork.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 5, minute: 25))!
        suite.expect(ny.map { abs($0.sunrise.timeIntervalSince(nySunrise)) < 6 * 60 } == true,
                     "sun times west of Greenwich fall on the local day")
        suite.expect(DisplayColorSupport.sunTimes(on: date(21, 12, 0), latitude: 78.2,
                                                  longitude: 15.6, calendar: shanghai) == nil,
                     "the midnight sun has no sunset")
        suite.expect(DisplayColorSupport.sunTimes(on: date(21, 12, 0), latitude: 120,
                                                  longitude: 0, calendar: shanghai) == nil,
                     "impossible coordinates have no sun times")
    }

    private static func schedule(_ suite: TestSuite) {
        var config = DisplayColorConfiguration()
        config.day = DisplayColorSetting(kelvin: 6500)
        config.sunset = DisplayColorSetting(kelvin: 3400)
        config.night = DisplayColorSetting(kelvin: 2300, tintHue: 0, tintStrength: 0.3)
        config.bedtimeMinutes = 23 * 60
        config.transitionMinutes = 30
        func state(_ at: Date, _ config: DisplayColorConfiguration) -> DisplayColorSupport.ScheduleState {
            DisplayColorSupport.scheduleState(at: at, configuration: config, calendar: shanghai)
        }

        let noon = state(date(21, 12, 0), config)
        suite.expect(noon.phase == .day && !noon.transitioning && noon.gains.isNeutral && !noon.usesSunTimes,
                     "midday without a location is plain day on the fallback clock")
        let fading = state(date(21, 19, 10), config)
        suite.expect(fading.phase == .sunset && fading.transitioning,
                     "ten minutes after sunset the fade is still running")
        suite.expect(fading.gains.blue > DisplayColorSupport.gains(for: config.sunset).blue
                        && fading.gains.blue < 1,
                     "a fade sits between the two looks")
        suite.expect(state(date(21, 21, 0), config).gains == DisplayColorSupport.gains(for: config.sunset),
                     "the evening settles on the sunset look")
        suite.expect(state(date(21, 23, 45), config).phase == .night, "bedtime starts the night")
        suite.expect(state(date(22, 3, 0), config).phase == .night, "the night holds until sunrise")
        suite.expect(state(date(22, 7, 40), config).phase == .day, "sunrise brings the day back")

        var early = config
        early.bedtimeMinutes = 18 * 60
        suite.expect(state(date(21, 20, 0), early).phase == .night,
                     "a bedtime before sunset keeps the night, not the evening")

        var late = config
        late.bedtimeMinutes = 30
        suite.expect(state(date(21, 23, 59), late).phase == .sunset
                        && state(date(22, 1, 0), late).phase == .night,
                     "a bedtime after midnight belongs to the same evening")

        var instant = config
        instant.transitionMinutes = 0
        suite.expect(!state(date(21, 19, 1), instant).transitioning, "a zero fade switches at once")

        var located = config
        located.latitude = 39.9
        located.longitude = 116.4
        let summer = state(date(21, 5, 0), located)
        suite.expect(summer.usesSunTimes && summer.phase == .day,
                     "with a location the real sunrise decides the phase")
    }

    private static func configuration(_ suite: TestSuite) {
        suite.expect(DisplayColorConfiguration.decoded(from: nil) == DisplayColorConfiguration(),
                     "no stored value means the defaults")
        suite.expect(DisplayColorConfiguration.decoded(from: Data("nonsense".utf8)) == DisplayColorConfiguration(),
                     "an unreadable value means the defaults")
        let partial = Data(#"{"mode":"manual","night":{"kelvin":100,"tintHue":1.25,"tintStrength":4},"latitude":95,"longitude":10}"#.utf8)
        let decoded = DisplayColorConfiguration.decoded(from: partial)
        suite.expect(decoded.mode == .manual && decoded.day == DisplayColorConfiguration().day,
                     "missing fields keep their defaults one by one")
        suite.expect(decoded.night.kelvin == 1200 && decoded.night.tintStrength == 1
                        && abs(decoded.night.tintHue - 0.25) < 0.0001,
                     "stored looks are clamped into range")
        suite.expect(decoded.latitude == nil && decoded.longitude == nil, "an impossible location is dropped")

        var config = DisplayColorConfiguration()
        config.mode = .manual
        config.manual = DisplayColorSetting(kelvin: 3100, tintHue: 0.8, tintStrength: 0.4)
        config.latitude = -33.87
        config.longitude = 151.21
        config.bedtimeMinutes = 90
        suite.expect(DisplayColorConfiguration.decoded(from: config.encoded) == config,
                     "a configuration survives being stored")
    }
}
