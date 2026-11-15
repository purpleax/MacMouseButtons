// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MacMouseButtonsCore

@MainActor
enum ActionPerformer {
    static func perform(_ action: ButtonAction) {
        switch action {
        case .back:
            SwipeGesture.post(.left)
        case .forward:
            SwipeGesture.post(.right)
        case .shortcut(let shortcut?):
            KeyPress.post(shortcut)
        case .missionControl:
            runMissionControl(argument: nil)
        case .appWindows:
            runMissionControl(argument: "2")
        case .showDesktop:
            runMissionControl(argument: "1")
        case .passThrough, .nothing, .shortcut(nil):
            break
        }
    }

    /// Mission Control has no public API, but its app does the job when run:
    /// with no argument it opens Mission Control, "1" shows the desktop and
    /// "2" shows the current app's windows. Running it again reverses it.
    private static func runMissionControl(argument: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        process.arguments = argument.map { [$0] } ?? []
        try? process.run()
    }
}
