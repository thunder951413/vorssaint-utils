// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import Security

enum FanControlLifecycleTests {
    final class Connection {
        var invalidations = 0
        func invalidate() { invalidations += 1 }
    }

    final class Remote: NSObject, FanControlXPCProtocol {
        func status(withReply reply: @escaping (Data) -> Void) {}
        func startMaximumCooling(withReply reply: @escaping (Data) -> Void) {}
        func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void) {}
        func heartbeat(withReply reply: @escaping (Data) -> Void) {}
        func restoreAutomatic(withReply reply: @escaping (Data) -> Void) {}
    }

    class State {
        let domain = "com.vorssaint.tests.fan-lifecycle.\(UUID().uuidString)"
        lazy var defaults = UserDefaults(suiteName: domain)!
        var available = true
        var isCurveArmed = false
        var panelIsVisible = false
        var snapshot = FanControlSnapshot.empty
        var timer: Timer?
        var connection: Connection?
        var errors: [(Connection) -> Void] = []
        var probes = 0
        var observations = 0
        var restores = 0
        var unregisters = 0
        var idleStops = 0
        var takeovers = 0
        var heartbeats = 0
        func setCurveArmed(_ armed: Bool) { isCurveArmed = armed }
        func restoreAutomatic() { restores += 1 }
        func restoreThenUnregister() { unregisters += 1 }
        func stopIdleWorkIfPossible() { idleStops += 1 }
        func refreshLocalProbe() { probes += 1 }
        func startObservingSystemState() { observations += 1 }
        func tryTakeOverIfNeeded() { takeovers += 1 }
        func heartbeat() { heartbeats += 1 }
        func proxy(errorHandler: @escaping (Connection) -> Void)
            -> (proxy: FanControlXPCProtocol, connection: Connection)? {
            if connection == nil { connection = Connection() }
            errors.append(errorHandler)
            return (Remote(), connection!)
        }
        deinit {
            timer?.invalidate()
            defaults.removePersistentDomain(forName: domain)
        }
    }

    static func pump(_ seconds: TimeInterval = 0.03) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func run(_ suite: TestSuite) {
        let armed = Service()
        armed.defaults.set(true, forKey: DefaultsKey.fanControlCurveArmed)
        armed.syncWithPreferences()
        suite.expect(armed.probes == 1 && armed.timer != nil && armed.isCurveArmed,
                     "persisted armed curve starts probing without opening the panel")
        let originalTimer = armed.timer
        armed.syncWithPreferences()
        suite.expect(armed.timer === originalTimer, "preference sync does not duplicate the timer")
        // A run-loop iteration may return for an unrelated event before the
        // timer fires. Keep tracking until the poll itself arrives.
        let pollDeadline = Date().addingTimeInterval(3)
        while armed.takeovers == 0, Date() < pollDeadline {
            RunLoop.main.run(mode: .eventTracking, before: pollDeadline)
        }
        suite.expect(armed.takeovers > 0 && armed.probes > 2,
                     "curve polling continues while the menu is tracking")
        armed.timer?.invalidate()

        let idle = Service()
        idle.syncWithPreferences()
        suite.expect(idle.timer == nil && idle.probes == 0 && idle.idleStops == 1,
                     "idle startup performs no polling")
        idle.defaults.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        idle.syncWithPreferences()
        suite.expect(idle.restores == 1, "pending recovery takes precedence over curve startup")
        idle.available = false
        idle.isCurveArmed = true
        idle.syncWithPreferences()
        suite.expect(!idle.isCurveArmed && idle.unregisters == 1,
                     "disabled feature disarms and unregisters")

        let service = Service()
        var firstReply: ((Data) -> Void)?
        var completions = 0
        let success = FanControlIPC.encode(FanControlResponse(succeeded: true, snapshot: .empty, error: nil))
        service.send(replyTimeout: 0.1, { _, reply in firstReply = reply }, completion: { _ in completions += 1 })
        let originalConnection = service.connection!
        firstReply?(success)
        pump()
        service.send(replyTimeout: 1, { _, _ in }, completion: { _ in completions += 1 })
        service.errors[0](originalConnection)
        pump(0.15)
        suite.expect(completions == 1 && originalConnection.invalidations == 0
                     && service.connection === originalConnection,
                     "late error and timeout cannot invalidate a newer request's connection")

        let timeoutService = Service()
        var replacement: Connection?
        var timeoutCompletions = 0
        timeoutService.send(replyTimeout: 0.01, { _, _ in }, completion: { _ in
            timeoutCompletions += 1
            timeoutService.send(replyTimeout: 1, { _, _ in }, completion: { _ in })
            replacement = timeoutService.connection
        })
        let timedOut = timeoutService.connection!
        pump(0.05)
        timeoutService.errors[0](timedOut)
        pump()
        suite.expect(timeoutCompletions == 1 && timedOut.invalidations == 1
                     && replacement !== timedOut && timeoutService.connection === replacement,
                     "timeout tears down before a reentrant completion starts its replacement")

        for requirement in [
            FanControlIdentifiers.codeRequirement(identifier: "com.vorssaint.utils", team: nil, certificateHash: nil),
            FanControlIdentifiers.codeRequirement(identifier: "com.vorssaint.utils", team: "2L2XRX7G4J", certificateHash: nil),
            FanControlIdentifiers.codeRequirement(identifier: "com.vorssaint.utils", team: nil,
                                                  certificateHash: String(repeating: "a", count: 40))
        ] {
            var compiled: SecRequirement?
            suite.expect(SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess,
                         "fan trust requirement compiles: \(requirement)")
        }
        suite.expect(FanControlIdentifiers.codeRequirement(identifier: "com.vorssaint.utils", team: nil,
                                                          certificateHash: nil) == "never",
                     "ad-hoc code cannot authenticate by a forgeable bundle identifier")
        let forged = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-fan-auth-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: forged)
            defer { try? FileManager.default.removeItem(at: forged) }
            let signed = Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier",
                                                        "com.vorssaint.utils", forged.path])
            suite.expect(signed.status == 0, "authentication fixture can forge an ad-hoc bundle identifier")
            var code: SecStaticCode?
            suite.expect(SecStaticCodeCreateWithPath(forged as CFURL, [], &code) == errSecSuccess,
                         "authentication fixture opens the forged executable")
            if let code {
                for trusted in ["identifier \"com.vorssaint.utils\"", "never",
                                FanControlIdentifiers.codeRequirement(identifier: "com.vorssaint.utils",
                                                                      team: "2L2XRX7G4J", certificateHash: nil)] {
                    var requirement: SecRequirement?
                    let compiled = SecRequirementCreateWithString(trusted as CFString, [], &requirement)
                    let accepted = compiled == errSecSuccess
                        && SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
                    suite.expect(accepted == trusted.hasPrefix("identifier"),
                                 "only the old identifier-only policy accepts forged ad-hoc code")
                }
            }
        } catch {
            suite.expect(false, "authentication fixture failed: \(error)")
        }
    }
}
