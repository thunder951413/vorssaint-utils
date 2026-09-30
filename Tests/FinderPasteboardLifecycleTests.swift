// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum FinderPasteboardLifecycleTests {
    struct MarkedItem { let url: URL; let icon: NSImage }
    class State {
        let pasteboard = FakeHistoryPasteboard()
        lazy var lane = GeneralPasteboardAccess(label: "Vorssaint.Tests.CutActions", pasteboard: { self.pasteboard })
        var operationGeneration = 1
        var cutPending = true
        var cutCancellation: PasteboardCancellation? = PasteboardCancellation()
        var marked: [MarkedItem] = []
        var markedChangeCount = 0
        var lastResult: Int?
        var moveInProgress = false
        var moveProgress: Int?
        var resultDismiss: DispatchWorkItem?
        var refreshes = 0
        func refreshPanel() { refreshes += 1 }
    }
    static func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }
    static func run(_ suite: TestSuite) {
        let urls = [URL(fileURLWithPath: "/tmp/vorssaint-cut-test")]
        let service = Service()
        service.applyCut(urls)
        pump { !service.marked.isEmpty }
        suite.expect(service.marked.map(\.url) == urls && service.markedChangeCount == 12 && !service.cutPending,
                     "cut marks appear only after a successful serialized clipboard write")
        service.cancelPendingCut()
        pump { service.pasteboard.operations.last == "clear" }
        suite.expect(service.marked.isEmpty && service.pasteboard.operations.suffix(2) == ["count", "clear"],
                     "cancelling clears only the clipboard change count owned by the cut")

        let cancelled = Service()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        cancelled.lane.async { entered.signal(); _ = release.wait(timeout: .now() + 2) }
        suite.expect(entered.wait(timeout: .now() + 1) == .success, "queued cut can wait behind a provider")
        cancelled.applyCut(urls)
        let token = cancelled.cutCancellation!
        cancelled.clearMarks()
        release.signal()
        var drained = false
        cancelled.lane.async({}, then: { drained = true })
        pump { drained }
        suite.expect(token.isCancelled && cancelled.marked.isEmpty && cancelled.pasteboard.operations.isEmpty,
                     "superseded cut never writes later or revives cancelled marks")
    }
}
