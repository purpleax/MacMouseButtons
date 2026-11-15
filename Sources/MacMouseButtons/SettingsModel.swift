// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MacMouseButtonsCore

/// The settings as the settings window sees them. Every change is saved
/// straight away and applied to the running event tap.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var triggerOnMouseDown: Bool {
        didSet {
            store.triggerOnMouseDown = triggerOnMouseDown
            onChange()
        }
    }

    @Published private var actions: [MouseButton: ButtonAction]

    private let store: SettingsStore
    private let onChange: () -> Void

    init(store: SettingsStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        triggerOnMouseDown = store.triggerOnMouseDown
        actions = Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { ($0, store.action(for: $0)) })
    }

    func action(for button: MouseButton) -> ButtonAction {
        actions[button] ?? button.defaultAction
    }

    func setAction(_ action: ButtonAction, for button: MouseButton) {
        actions[button] = action
        store.setAction(action, for: button)
        onChange()
    }
}

/// The choices in each button's pop-up menu.
enum ActionKind: String, CaseIterable, Identifiable {
    case passThrough, nothing, back, forward, missionControl, appWindows, showDesktop, shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passThrough: "Leave Alone"
        case .nothing: "Do Nothing"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appWindows: "Application Windows"
        case .showDesktop: "Show Desktop"
        case .shortcut: "Keyboard Shortcut"
        }
    }

    init(_ action: ButtonAction) {
        switch action {
        case .passThrough: self = .passThrough
        case .nothing: self = .nothing
        case .back: self = .back
        case .forward: self = .forward
        case .missionControl: self = .missionControl
        case .appWindows: self = .appWindows
        case .showDesktop: self = .showDesktop
        case .shortcut: self = .shortcut
        }
    }

    /// `current` is the button's existing action, so that reselecting
    /// Keyboard Shortcut keeps a shortcut that was already recorded.
    func action(current: ButtonAction) -> ButtonAction {
        switch self {
        case .passThrough: return .passThrough
        case .nothing: return .nothing
        case .back: return .back
        case .forward: return .forward
        case .missionControl: return .missionControl
        case .appWindows: return .appWindows
        case .showDesktop: return .showDesktop
        case .shortcut:
            if case .shortcut = current { return current }
            return .shortcut(nil)
        }
    }
}

extension KeyShortcut {
    /// Builds a shortcut from a key press, with a label such as "⌃⌥⇧⌘K".
    init(event: NSEvent) {
        let flags = event.modifierFlags
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        label += Self.keyName(for: event)
        // NSEvent and CGEvent use the same bits for these four modifiers.
        self.init(keyCode: event.keyCode, modifiers: UInt64(flags.rawValue), label: label)
    }

    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static func keyName(for event: NSEvent) -> String {
        if let name = specialKeys[event.keyCode] { return name }
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return characters.isEmpty ? "Key \(event.keyCode)" : characters
    }
}
