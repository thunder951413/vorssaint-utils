// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreLocation
import os

/// Warms or tints every screen, following the sun or one fixed look.
///
/// The filter is a per-channel factor on each display's gamma curve, written
/// through `DisplayGammaCompositor` together with software dimming. The curve
/// is rewritten on every tick, after wake and after any reconfiguration,
/// because macOS puts the clean curve back on all of those without telling
/// anyone. No timer or observer exists while the filter is off.
final class DisplayColorService: NSObject, ObservableObject {
    static let shared = DisplayColorService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display")

    @Published private(set) var configuration: DisplayColorConfiguration
    /// The automatic mode's state right now; nil in manual mode or when off.
    @Published private(set) var schedule: DisplayColorSupport.ScheduleState?
    @Published private(set) var running = false
    /// f.lux writes the same curves; the two cannot both win.
    @Published private(set) var fluxRunning = false
    @Published private(set) var locating = false
    @Published private(set) var locationFailed = false

    /// Ticks while a fade runs, so it moves smoothly.
    private static let transitionInterval: TimeInterval = 10
    /// Ticks otherwise. Each tick also writes the curve again, which is what
    /// recovers it after something reset it.
    private static let idleInterval: TimeInterval = 60
    /// How long an edited look stays on screen before the schedule returns.
    private static let previewDuration: TimeInterval = 3

    private let gamma = DisplayGammaCompositor.shared
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var previewGains: DisplayColorGains?
    private var previewEnd: DispatchWorkItem?
    private var settleWork: [DispatchWorkItem] = []
    private var locationManager: CLLocationManager?

    private override init() {
        configuration = DisplayColorConfiguration.decoded(
            from: UserDefaults.standard.data(forKey: DefaultsKey.displayColorConfiguration))
        super.init()
    }

    private var wanted: Bool {
        AppFeature.displayColor.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.displayColorEnabled)
    }

    func syncWithPreferences() {
        if wanted { start() } else { stop() }
    }

    /// Changes the configuration, stores it and shows the result.
    func update(_ change: (inout DisplayColorConfiguration) -> Void) {
        var next = configuration
        change(&next)
        next = next.sanitized
        guard next != configuration else { return }
        configuration = next
        if let data = next.encoded {
            UserDefaults.standard.set(data, forKey: DefaultsKey.displayColorConfiguration)
        }
        if running { apply() }
    }

    /// Shows `setting` for a moment while it is being edited, so a phase that
    /// is not the current one can still be judged on screen.
    func preview(_ setting: DisplayColorSetting) {
        guard running else { return }
        previewGains = DisplayColorSupport.gains(for: setting)
        previewEnd?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewGains = nil
            if self.running { self.apply() }
        }
        previewEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewDuration, execute: work)
        apply()
    }

    // MARK: Lifecycle

    private func start() {
        guard !running else {
            apply()
            return
        }
        running = true
        installObservers()
        refreshFluxRunning()
        apply()
        Self.log.log("display color filter started")
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        timerInterval = 0
        removeObservers()
        previewEnd?.cancel()
        previewEnd = nil
        previewGains = nil
        settleWork.forEach { $0.cancel() }
        settleWork = []
        locationManager?.delegate = nil
        locationManager = nil
        locating = false
        schedule = nil
        gamma.setColor(.neutral, displays: [])
        Self.log.log("display color filter stopped")
    }

    // MARK: Applying

    private func apply() {
        guard running else { return }
        let now = Date()
        var gains: DisplayColorGains
        var transitioning = false
        switch configuration.mode {
        case .manual:
            if schedule != nil { schedule = nil }
            gains = DisplayColorSupport.gains(for: configuration.manual)
        case .sun:
            let state = DisplayColorSupport.scheduleState(at: now, configuration: configuration,
                                                          calendar: .current)
            if schedule != state { schedule = state }
            gains = state.gains
            transitioning = state.transitioning
        }
        if let previewGains { gains = previewGains }
        gamma.setColor(gains, displays: Self.activeDisplayIDs())
        scheduleTick(interval: transitioning ? Self.transitionInterval : Self.idleInterval)
    }

    private func scheduleTick(interval: TimeInterval) {
        guard timer == nil || timerInterval != interval else { return }
        timer?.invalidate()
        timerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.apply()
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Displays settle for a moment after a reconfiguration or wake, and
    /// macOS can put the clean curve back after the first write, so the
    /// filter goes back on a few times as they do.
    private func applyAfterSettling() {
        settleWork.forEach { $0.cancel() }
        settleWork = [0.5, 2, 5].map { delay in
            let work = DispatchWorkItem { [weak self] in self?.apply() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private static func activeDisplayIDs() -> Set<CGDirectDisplayID> {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
        return Set(ids.prefix(Int(count)))
    }

    // MARK: Observers

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ target: NotificationCenter, _ name: Notification.Name,
                     _ handler: @escaping (DisplayColorService) -> Void) {
            let token = target.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.running else { return }
                handler(self)
            }
            observers.append((target, token))
        }
        observe(center, NSApplication.didChangeScreenParametersNotification) { $0.applyAfterSettling() }
        observe(center, .NSSystemClockDidChange) { $0.apply() }
        observe(center, .NSSystemTimeZoneDidChange) { $0.apply() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.applyAfterSettling() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.applyAfterSettling() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.applyAfterSettling() }
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { $0.refreshFluxRunning() }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { service in
            service.refreshFluxRunning()
            // f.lux puts the clean curve back as it quits.
            service.applyAfterSettling()
        }
    }

    private func removeObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    private func refreshFluxRunning() {
        let running = !NSRunningApplication.runningApplications(
            withBundleIdentifier: DisplayColorSupport.fluxBundleIdentifier).isEmpty
        if fluxRunning != running { fluxRunning = running }
    }

    // MARK: Location

    /// Asks for one location fix, used only to work out sunrise and sunset.
    /// The coordinates are rounded to about a kilometre before being stored.
    func locate() {
        guard !locating else { return }
        locationFailed = false
        let manager = locationManager ?? CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = manager
        locating = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finishLocating(failed: true)
        default:
            manager.requestLocation()
        }
    }

    func setLocation(latitude: Double?, longitude: Double?) {
        update {
            $0.latitude = latitude
            $0.longitude = longitude
        }
    }

    private func finishLocating(failed: Bool) {
        locating = false
        locationFailed = failed
        locationManager?.delegate = nil
        locationManager = nil
    }
}

extension DisplayColorService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.locating, manager === self.locationManager else { return }
            switch manager.authorizationStatus {
            case .notDetermined:
                break
            case .denied, .restricted:
                self.finishLocating(failed: true)
            default:
                manager.requestLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.locating else { return }
            let latitude = (coordinate.latitude * 100).rounded() / 100
            let longitude = (coordinate.longitude * 100).rounded() / 100
            self.finishLocating(failed: false)
            self.setLocation(latitude: latitude, longitude: longitude)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.locating else { return }
            Self.log.error("location request failed: \(error.localizedDescription, privacy: .public)")
            self.finishLocating(failed: true)
        }
    }
}
