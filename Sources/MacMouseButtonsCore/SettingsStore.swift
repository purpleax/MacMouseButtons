// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Reads and writes the settings in `UserDefaults`. Shared by the app and by
/// `macmousebuttons-check`, which reads the app's settings to know what each
/// button is supposed to do.
public struct SettingsStore: @unchecked Sendable {
    public static let appDomain = "com.purpleax.MacMouseButtons"

    private enum Key {
        static let enabled = "Enabled"
        static let triggerOnMouseDown = "TriggerOnMouseDown"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.enabled: true, Key.triggerOnMouseDown: true])
    }

    public var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.enabled) }
    }

    public var triggerOnMouseDown: Bool {
        get { defaults.bool(forKey: Key.triggerOnMouseDown) }
        nonmutating set { defaults.set(newValue, forKey: Key.triggerOnMouseDown) }
    }

    public func action(for button: MouseButton) -> ButtonAction {
        defaults.string(forKey: button.defaultsKey).flatMap(ButtonAction.init(storageValue:)) ?? button.defaultAction
    }

    public func setAction(_ action: ButtonAction, for button: MouseButton) {
        defaults.set(action.storageValue, forKey: button.defaultsKey)
    }

    public var buttonSettings: ButtonSettings {
        var settings = ButtonSettings(triggerOnMouseDown: triggerOnMouseDown)
        for button in MouseButton.allCases {
            settings[button] = action(for: button)
        }
        return settings
    }
}
