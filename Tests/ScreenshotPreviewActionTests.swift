// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ScreenshotPreviewActionTests {
    enum Action: Hashable { case copy, save, saveAndCopy, edit, discard }
    final class Model { var disabledActions: Set<Action> = [] }
    class State {
        let model = Model()
        var closed = false
        var performingAction = false
        var dismissWork: DispatchWorkItem?
        var dismissSchedules = 0
        var action: @MainActor (Action) async -> Set<Action> = { _ in [] }
        func close() { closed = true }
        func scheduleAutoDismiss() { dismissSchedules += 1 }
    }

    static func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }

    static func run(_ suite: TestSuite) {
        let preview = Controller()
        var pending: CheckedContinuation<Set<Action>, Never>?
        var requests = 0
        preview.action = { _ in
            requests += 1
            return await withCheckedContinuation { pending = $0 }
        }
        preview.perform(.copy)
        pump { pending != nil }
        preview.perform(.copy)
        suite.expect(requests == 1 && !preview.closed && preview.performingAction,
                     "copy keeps preview open while awaiting the write and rejects duplicate actions")
        pending?.resume(returning: [])
        pump { !preview.performingAction }
        suite.expect(!preview.closed && preview.dismissSchedules == 1,
                     "failed write leaves the preview available for a retry")
        pending = nil
        preview.perform(.copy)
        pump { pending != nil }
        pending?.resume(returning: [.copy])
        pump { preview.closed }
        suite.expect(preview.closed, "successful write closes the preview only after completion")

        let automatic = Controller()
        automatic.action = { _ in [.save] }
        var completed = false
        let task = Task { @MainActor in
            completed = await automatic.runDefaultAction(.saveAndCopy)
        }
        pump { completed }
        _ = task
        suite.expect(completed && automatic.model.disabledActions == [.save] && !automatic.closed,
                     "partial automatic save/copy success disables only the successful save")
    }
}
