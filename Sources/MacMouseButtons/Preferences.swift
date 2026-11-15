// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MacMouseButtonsCore

@MainActor
struct Preferences {
    private enum Key {
        static let enabled = "Enabled"
        static let triggerOnMouseDown = "TriggerOnMouseDown"
        static let swapButtons = "SwapButtons"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.triggerOnMouseDown: true,
            Key.swapButtons: false,
        ])
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var triggerOnMouseDown: Bool {
        get { defaults.bool(forKey: Key.triggerOnMouseDown) }
        nonmutating set { defaults.set(newValue, forKey: Key.triggerOnMouseDown) }
    }

    var swapButtons: Bool {
        get { defaults.bool(forKey: Key.swapButtons) }
        nonmutating set { defaults.set(newValue, forKey: Key.swapButtons) }
    }

    var buttonSettings: ButtonSettings {
        ButtonSettings(triggerOnMouseDown: triggerOnMouseDown, swapButtons: swapButtons)
    }
}
