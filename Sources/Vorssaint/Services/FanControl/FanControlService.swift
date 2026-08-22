// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import ServiceManagement

final class FanControlService: ObservableObject {
    enum AccessState: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unavailable
    }

    static let shared = FanControlService()

    @Published private(set) var accessState: AccessState = .notRegistered
    @Published private(set) var snapshot: FanControlSnapshot = .empty
    @Published private(set) var error: FanControlErrorCode?
    @Published private(set) var isWorking = false
    @Published private(set) var isCurveArmed = false

    private let probeQueue = DispatchQueue(label: "com.vorssaint.fan-control.probe",
                                           qos: .utility)
    private var probeHardware: FanControlHardware?
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var panelIsVisible = false
    private var isSleeping = false
    private var helperUnreachable = false
    private var requestInFlight = false
    private var requestGeneration = 0
    private var registrationAttemptedVersion: String?
    private var observingWorkspace = false
    private var probeInFlight = false

    private static var appService: SMAppService {
        SMAppService.daemon(plistName: FanControlIdentifiers.plistName)
    }

    private static var helperVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintFanControlHelperVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? AppInfo.version
    }

    private init() {
        isCurveArmed = UserDefaults.standard.bool(forKey: DefaultsKey.fanControlCurveArmed)
        refreshAccessState()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        connection?.invalidate()
        timer?.invalidate()
    }

    static func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreAutomatic()
    }

    func syncWithPreferences() {
        isCurveArmed = UserDefaults.standard.bool(forKey: DefaultsKey.fanControlCurveArmed)
        if AppFeature.fanControl.isAvailable {
            if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                restoreAutomatic()
            }
        } else {
            setCurveArmed(false)
            restoreThenUnregister()
        }
    }

    func panelDidAppear() {
        panelIsVisible = true
        startObservingSystemState()
        refreshLocalProbe()
        startTimerIfNeeded()
    }

    func panelDidDisappear() {
        panelIsVisible = false
        stopIdleWorkIfPossible()
    }

    func refresh() {
        refreshAccessState()
        if accessState == .enabled, !helperUnreachable {
            guard !replaceRegistrationIfNeeded() else { return }
            requestStatus()
        } else {
            refreshLocalProbe()
        }
    }

    func authorize() {
        refreshAccessState()
        switch accessState {
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .enabled:
            helperUnreachable = false
            requestStatus()
        case .unavailable:
            error = .helperUnavailable
        case .notRegistered:
            isWorking = true
            do {
                try Self.appService.register()
                UserDefaults.standard.set(Self.helperVersion,
                                          forKey: DefaultsKey.fanControlHelperVersion)
                refreshAccessState()
                isWorking = false
                if accessState == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if accessState == .enabled {
                    requestStatus()
                }
            } catch {
                isWorking = false
                refreshAccessState()
                if accessState == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    self.error = .helperUnavailable
                }
            }
        }
        startTimerIfNeeded()
    }

    func applyConfiguration(_ configuration: FanControlConfiguration) {
        applyConfiguration(configuration, userInitiated: true)
    }

    func applyStoredCurve(userInitiated: Bool) {
        guard userInitiated || (!isSleeping && !helperUnreachable && !isWorking && !requestInFlight) else { return }
        let defaults = UserDefaults.standard
        let sensor = FanControlTemperatureSource(
            rawValue: defaults.string(forKey: DefaultsKey.fanControlSensor) ?? "")
            ?? FanControlPolicy.defaultSensor
        applyConfiguration(
            .curve(sensor: sensor,
                   threshold: FanControlPolicy.clampedThreshold(
                    defaults.object(forKey: DefaultsKey.fanControlThreshold) as? Int
                        ?? FanControlPolicy.defaultThreshold),
                   accelerationFactor: FanControlPolicy.clampAccelerationFactor(
                    defaults.object(forKey: DefaultsKey.fanControlAcceleration) as? Double
                        ?? FanControlPolicy.defaultAccelerationFactor)),
            userInitiated: userInitiated
        )
    }

    func applyConfiguration(_ configuration: FanControlConfiguration, userInitiated: Bool) {
        guard userInitiated || (!isWorking && !requestInFlight) else { return }
        guard FanControlPolicy.validConfiguration(configuration) else {
            error = .controlFailed
            return
        }
        if configuration.mode == .system {
            setCurveArmed(false)
            restoreAutomatic()
            return
        }
        guard accessState == .enabled else { authorize(); return }
        guard let encodedConfiguration = FanControlIPC.encode(configuration) else {
            error = .controlFailed
            return
        }
        error = nil
        let retrySnapshot = snapshot
        let armCurve = configuration.mode == .curve
        startObservingSystemState()
        let generation = beginRequest()
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        if userInitiated { isWorking = true }
        send(replyTimeout: Self.controlReplyTimeout) { proxy, reply in
            proxy.applyConfiguration(encodedConfiguration, withReply: reply)
        } completion: { response in
            let matches = self.finishRequest(generation)
            if userInitiated { self.isWorking = false }
            guard matches else { return }
            guard let response else {
                self.markHelperUnreachable(.helperUnavailable)
                return
            }
            self.helperUnreachable = false
            self.apply(response)
            if response.succeeded {
                self.setCurveArmed(armCurve)
                if response.snapshot.isCooling {
                    self.startTimerIfNeeded()
                } else {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
                    if armCurve {
                        self.startTimerIfNeeded()
                    } else {
                        self.restoreAutomatic(supersedingCurrentRequest: false,
                                              preserving: response.error,
                                              retrySnapshot: retrySnapshot)
                    }
                }
            } else {
                self.restoreAutomatic(supersedingCurrentRequest: false,
                                      preserving: response.error ?? .controlFailed,
                                      retrySnapshot: retrySnapshot)
                if self.snapshot.fans.isEmpty { self.refreshLocalProbe() }
            }
        }
    }

    func restoreAutomatic() {
        setCurveArmed(false)
        restoreAutomatic(supersedingCurrentRequest: false)
    }

    private func setCurveArmed(_ armed: Bool) {
        isCurveArmed = armed
        if armed {
            UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlCurveArmed)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlCurveArmed)
        }
    }

    private func restoreAutomatic(supersedingCurrentRequest: Bool,
                                  preserving failure: FanControlErrorCode? = nil,
                                  retrySnapshot: FanControlSnapshot? = nil) {
        guard supersedingCurrentRequest || !isWorking else { return }
        refreshAccessState()
        guard accessState == .enabled else { return }
        let generation = beginRequest()
        isWorking = true
        startTimerIfNeeded()
        send(replyTimeout: Self.controlReplyTimeout) { proxy, reply in
            proxy.restoreAutomatic(withReply: reply)
        } completion: { response in
            guard self.finishRequest(generation) else { return }
            self.isWorking = false
            guard let response else {
                self.markHelperUnreachable(.helperUnavailable)
                if let retrySnapshot, self.snapshot.fans.isEmpty {
                    self.snapshot = retrySnapshot
                }
                return
            }
            self.apply(response)
            if response.succeeded, !response.snapshot.isCooling {
                if self.snapshot.fans.isEmpty, let retrySnapshot {
                    self.snapshot = retrySnapshot
                }
                if let failure { self.error = failure }
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
                if !AppFeature.fanControl.isAvailable {
                    do {
                        try Self.appService.unregister()
                        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                        self.refreshAccessState()
                    } catch {
                        self.error = .helperUnavailable
                    }
                }
                self.stopIdleWorkIfPossible()
            }
        }
    }

    static func restoreBeforeTerminationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreBeforeTermination()
    }

    private func restoreBeforeTermination() {
        send(replyTimeout: Self.controlReplyTimeout) { proxy, reply in
            proxy.restoreAutomatic(withReply: reply)
        } completion: { response in
            if let response, response.succeeded, !response.snapshot.isCooling {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
            }
        }
        // Losing the authenticated client connection is itself a restore
        // trigger in the helper, including if the reply cannot beat app exit.
        connection?.invalidate()
        connection = nil
    }

    /// Used by the complete-uninstall path from its background queue. The
    /// daemon is removed only after it confirms automatic control, so teardown
    /// can never kill the recovery mechanism while a manual session remains.
    ///
    /// Reports whether the daemon is actually gone. A caller that tells someone
    /// the app was fully removed has no other way to know: the registration
    /// outlives the bundle, so a silent failure here reads as success forever.
    @discardableResult
    static func restoreAndUnregisterForRemoval() -> Bool {
        let service = appService
        guard service.status == .enabled else {
            guard service.status != .notRegistered else { return true }
            // A pending recovery keeps the daemon deliberately: it is the only
            // thing that can put the fans back. Still not a clean detach.
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
            else { return false }
            return unregisterForRemoval(service)
        }
        let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
        connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var restored = false
        connection.activate()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() }
            as? FanControlXPCProtocol
        guard let proxy else {
            connection.invalidate()
            return false
        }
        proxy.restoreAutomatic { data in
            if let response = FanControlIPC.decode(data) {
                resultLock.withLock {
                    restored = response.succeeded && !response.snapshot.isCooling
                }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20)
        connection.invalidate()
        guard resultLock.withLock({ restored }) else { return false }
        return unregisterForRemoval(service)
    }

    private static func unregisterForRemoval(_ service: SMAppService) -> Bool {
        do {
            try service.unregister()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Requests

    /// Status and heartbeat replies only read SMC state; anything slower means
    /// the helper is wedged. Control requests can legitimately take longer:
    /// the stopped-fan force-start path sleeps and retries for tens of seconds.
    private static let statusReplyTimeout: TimeInterval = 8
    private static let controlReplyTimeout: TimeInterval = 40

    private func requestStatus() {
        guard !requestInFlight else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.status(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.markHelperUnreachable(.helperUnavailable)
                return
            }
            self.helperUnreachable = false
            self.apply(response)
            // Any decoded reply proves that the installed helper speaks this
            // protocol, even when the hardware itself is unsupported.
            UserDefaults.standard.set(Self.helperVersion,
                                      forKey: DefaultsKey.fanControlHelperVersion)
            if response.succeeded, !response.snapshot.isCooling {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
            }
            if self.snapshot.fans.isEmpty, response.error != .noFans {
                self.refreshLocalProbe()
            }
        }
    }

    private func send(replyTimeout: TimeInterval = FanControlService.statusReplyTimeout,
                      _ operation: @escaping (FanControlXPCProtocol, @escaping (Data) -> Void) -> Void,
                      completion: @escaping (FanControlResponse?) -> Void) {
        var finished = false
        let finish: (FanControlResponse?) -> Void = { response in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(response)
            }
        }
        var timeoutWorkItem: DispatchWorkItem?
        guard let remote = proxy(errorHandler: { [weak self] failedConnection in
            timeoutWorkItem?.cancel()
            DispatchQueue.main.async {
                if self?.connection === failedConnection {
                    failedConnection.invalidate()
                    self?.connection = nil
                }
                finish(nil)
            }
        }) else {
            finish(nil)
            return
        }
        // Whichever of the reply, the error handler or the timeout claims the
        // finished flag first wins; the losers must do nothing at all, so a
        // late timeout can never tear down a connection a newer request,
        // sharing the same connection, still has in flight.
        let sentConnection = remote.connection
        let timeout = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(nil)
                guard self?.connection === sentConnection else { return }
                sentConnection.invalidate()
                self?.connection = nil
            }
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + replyTimeout, execute: timeout)
        operation(remote.proxy) { data in
            timeout.cancel()
            finish(FanControlIPC.decode(data))
        }
    }

    private func proxy(errorHandler: @escaping (NSXPCConnection) -> Void)
        -> (proxy: FanControlXPCProtocol, connection: NSXPCConnection)? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID,
                                             options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
            connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
            connection.interruptionHandler = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection, self?.connection === connection else { return }
                    connection.invalidate()
                    self?.connection = nil
                }
            }
            connection.invalidationHandler = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection else { return }
                    if self?.connection === connection { self?.connection = nil }
                }
            }
            connection.activate()
            self.connection = connection
        }
        guard let connection else { return nil }
        guard let remoteObject = connection.remoteObjectProxyWithErrorHandler(
                { _ in errorHandler(connection) }) as? FanControlXPCProtocol else { return nil }
        return (remoteObject, connection)
    }

    private func heartbeat() {
        guard snapshot.isCooling, !requestInFlight, !isWorking else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.heartbeat(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.markHelperUnreachable(.helperUnavailable)
                return
            }
            self.apply(response)
            if response.succeeded, !response.snapshot.isCooling {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
                self.stopIdleWorkIfPossible()
            }
        }
    }

    private func apply(_ response: FanControlResponse) {
        if !response.snapshot.fans.isEmpty
            || response.error == .noFans
            || response.error == .unsupportedHardware
            || snapshot.fans.isEmpty {
            snapshot = response.snapshot
        } else {
            var merged = snapshot
            merged.isCooling = response.snapshot.isCooling
            merged.endsAt = response.snapshot.endsAt
            merged.stopReason = response.snapshot.stopReason
            merged.coolingLevel = response.snapshot.coolingLevel
            merged.configuration = response.snapshot.configuration
            if let temperatures = response.snapshot.temperatures {
                merged.temperatures = temperatures
            }
            snapshot = merged
        }
        error = response.error
    }

    private func markHelperUnreachable(_ failure: FanControlErrorCode) {
        helperUnreachable = true
        error = failure
        connection?.invalidate()
        connection = nil
        refreshLocalProbe()
    }

    private func beginRequest() -> Int {
        requestGeneration += 1
        requestInFlight = true
        return requestGeneration
    }

    private func finishRequest(_ generation: Int) -> Bool {
        guard generation == requestGeneration else { return false }
        requestInFlight = false
        return true
    }

    // MARK: - Registration and local reads

    private func refreshAccessState() {
        switch Self.appService.status {
        case .notRegistered: accessState = .notRegistered
        case .enabled: accessState = .enabled
        case .requiresApproval: accessState = .requiresApproval
        // A bundled daemon can report notFound before its first registration.
        // register() then moves it to the user-approval state.
        case .notFound: accessState = .notRegistered
        @unknown default: accessState = .unavailable
        }
    }

    /// Apple requires a changed embedded daemon to be unregistered before it
    /// is registered again. This runs once per app build and only when the user
    /// opens an already-authorized Fan Control surface.
    private func replaceRegistrationIfNeeded() -> Bool {
        let installed = UserDefaults.standard.string(forKey: DefaultsKey.fanControlHelperVersion) ?? ""
        let current = Self.helperVersion
        guard !installed.isEmpty, installed != current,
              registrationAttemptedVersion != current,
              !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return false }
        registrationAttemptedVersion = current
        isWorking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.isWorking,
                  self.registrationAttemptedVersion == current else { return }
            self.isWorking = false
            self.markHelperUnreachable(.helperUnavailable)
        }
        Self.appService.unregister { error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self.isWorking = false
                    self.markHelperUnreachable(.helperUnavailable)
                    return
                }
                do {
                    try Self.appService.register()
                    UserDefaults.standard.set(current, forKey: DefaultsKey.fanControlHelperVersion)
                    self.isWorking = false
                    self.refreshAccessState()
                    if self.accessState == .enabled { self.requestStatus() }
                } catch {
                    self.isWorking = false
                    self.refreshAccessState()
                    self.markHelperUnreachable(.helperUnavailable)
                }
            }
        }
        return true
    }

    private func refreshLocalProbe() {
        guard !probeInFlight else { return }
        probeInFlight = true
        probeQueue.async {
            defer {
                DispatchQueue.main.async { self.probeInFlight = false }
            }
            if self.probeHardware == nil { self.probeHardware = FanControlHardware() }
            let result: Result<FanControlSnapshot, FanControlErrorCode>
            guard let probe = self.probeHardware else {
                result = .failure(.unsupportedHardware)
                DispatchQueue.main.async { self.applyProbe(result) }
                return
            }
            do {
                result = .success(try probe.readOnlySnapshot())
            } catch FanControlHardwareError.noFans {
                result = .failure(.noFans)
            } catch FanControlHardwareError.alreadyControlled {
                if let snapshot = try? probe.telemetrySnapshot() {
                    DispatchQueue.main.async {
                        self.applyProbeSnapshot(snapshot, error: .alreadyControlled)
                    }
                    return
                }
                result = .failure(.alreadyControlled)
            } catch {
                if let snapshot = try? probe.telemetrySnapshot() {
                    DispatchQueue.main.async {
                        self.applyProbeSnapshot(snapshot, error: .unsupportedHardware)
                    }
                    return
                }
                result = .failure(.unsupportedHardware)
            }
            DispatchQueue.main.async { self.applyProbe(result) }
        }
    }

    private func applyProbe(_ result: Result<FanControlSnapshot, FanControlErrorCode>) {
        switch result {
        case .success(let snapshot):
            applyProbeSnapshot(snapshot,
                               error: snapshot.fans.contains(where: \.isManuallyControlled)
                                   ? .alreadyControlled : nil)
        case .failure(let error):
            if self.snapshot.fans.isEmpty {
                self.snapshot = .empty
            }
            if self.error == nil { self.error = error }
        }
    }

    private func applyProbeSnapshot(_ snapshot: FanControlSnapshot,
                                    error: FanControlErrorCode?) {
        if !snapshot.fans.isEmpty {
            var next = snapshot
            if self.snapshot.isCooling {
                next.isCooling = true
                next.coolingLevel = self.snapshot.coolingLevel
                next.configuration = self.snapshot.configuration
                next.endsAt = self.snapshot.endsAt
                next.stopReason = self.snapshot.stopReason
            }
            if !Self.displayEquivalent(next, self.snapshot) {
                self.snapshot = next
            }
        }
        if error == .alreadyControlled {
            self.error = error
        } else if self.error == .noFans || self.error == .unsupportedHardware {
            self.error = error
        }
    }

    private static func displayEquivalent(_ lhs: FanControlSnapshot, _ rhs: FanControlSnapshot) -> Bool {
        guard lhs.fans.count == rhs.fans.count,
              lhs.isCooling == rhs.isCooling else { return false }
        let fansMatch = zip(lhs.fans, rhs.fans).allSatisfy { left, right in
            left.index == right.index
                && left.isManuallyControlled == right.isManuallyControlled
                && abs(left.actualRPM - right.actualRPM) < 40
                && abs(left.targetRPM - right.targetRPM) < 40
        }
        guard fansMatch else { return false }
        let leftTemps = lhs.temperatures ?? []
        let rightTemps = rhs.temperatures ?? []
        guard leftTemps.count == rightTemps.count else { return false }
        return zip(leftTemps, rightTemps).allSatisfy { left, right in
            left.source == right.source && abs(left.celsius - right.celsius) < 0.5
        }
    }

    private func restoreThenUnregister() {
        refreshAccessState()
        guard accessState != .notRegistered else { return }
        if accessState != .enabled {
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else {
                error = .authorizationRequired
                return
            }
            do {
                try Self.appService.unregister()
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                refreshAccessState()
            } catch {
                self.error = .helperUnavailable
            }
            return
        }
        let generation = beginRequest()
        isWorking = true
        send(replyTimeout: Self.controlReplyTimeout) { proxy, reply in
            proxy.restoreAutomatic(withReply: reply)
        } completion: { response in
            guard self.finishRequest(generation) else { return }
            self.isWorking = false
            guard let response, response.succeeded, !response.snapshot.isCooling else { return }
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
            guard !AppFeature.fanControl.isAvailable else {
                self.stopIdleWorkIfPossible()
                return
            }
            do {
                try Self.appService.unregister()
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                self.refreshAccessState()
            } catch {
                self.error = .helperUnavailable
            }
            self.stopIdleWorkIfPossible()
        }
    }

    // MARK: - Timers and system state

    private func startTimerIfNeeded() {
        guard panelIsVisible || snapshot.isCooling || isCurveArmed
                || UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        startObservingSystemState()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.snapshot.isCooling {
                self.heartbeat()
                return
            }
            // An armed curve keeps watching temperatures while the panel is
            // closed; without fresh local reads it would act on stale data.
            if self.panelIsVisible || self.isCurveArmed {
                self.refreshLocalProbe()
            }
            self.tryTakeOverIfNeeded()
        }
    }

    private func tryTakeOverIfNeeded() {
        guard isCurveArmed, !snapshot.isCooling, !helperUnreachable, !isSleeping,
              !isWorking, !requestInFlight else { return }
        let defaults = UserDefaults.standard
        let sensor = FanControlTemperatureSource(
            rawValue: defaults.string(forKey: DefaultsKey.fanControlSensor) ?? "")
            ?? FanControlPolicy.defaultSensor
        switch FanControlPolicy.curveDemand(
            sensor: sensor,
            threshold: FanControlPolicy.clampedThreshold(
                defaults.object(forKey: DefaultsKey.fanControlThreshold) as? Int
                    ?? FanControlPolicy.defaultThreshold),
            accelerationFactor: FanControlPolicy.clampAccelerationFactor(
                defaults.object(forKey: DefaultsKey.fanControlAcceleration) as? Double
                    ?? FanControlPolicy.defaultAccelerationFactor),
            temperatures: snapshot.temperatures ?? []
        ) {
        case .cooling:
            applyStoredCurve(userInitiated: false)
        case .belowThreshold, .unavailable:
            break
        }
        // The helper drops cooling once a heartbeat is `heartbeatLimit` seconds
        // old, so a second's cadence has six to spare; matching the leeway the
        // helper's own watchdog already takes lets these wakes coalesce with
        // everything else on the run loop instead of standing alone.
        timer?.tolerance = 0.1
    }

    private func stopIdleWorkIfPossible() {
        guard !panelIsVisible, !snapshot.isCooling, !isCurveArmed,
              !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        timer?.invalidate()
        timer = nil
        connection?.invalidate()
        connection = nil
        stopObservingSystemState()
    }

    private func startObservingSystemState() {
        guard !observingWorkspace else { return }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(workspaceWillSleep),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceDidWake),
                           name: NSWorkspace.didWakeNotification, object: nil)
        observingWorkspace = true
    }

    private func stopObservingSystemState() {
        guard observingWorkspace else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observingWorkspace = false
    }

    @objc private func workspaceWillSleep() {
        isSleeping = true
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) || isCurveArmed {
            restoreAutomatic(supersedingCurrentRequest: true)
        }
    }

    @objc private func workspaceDidWake() {
        isSleeping = false
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        } else if isCurveArmed {
            applyStoredCurve(userInitiated: false)
        } else if panelIsVisible {
            refresh()
        }
    }
}
