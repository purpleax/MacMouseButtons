// MacMouseButtons — choose what the extra buttons on a third-party mouse do.
// A Swift reimplementation of SensibleSideButtons by Alexei Baboulevitch.
// SPDX-License-Identifier: GPL-2.0-or-later

/// The direction of a synthesized three-finger swipe.
/// Raw values match `IOHIDSwipeMask` in IOKit's private HID event headers.
public enum SwipeDirection: Int64, Sendable, CaseIterable {
    /// Navigates back.
    case left = 4
    /// Navigates forward.
    case right = 8
}

/// The mouse controls that can be configured.
public enum MouseButton: String, Sendable, CaseIterable, Identifiable {
    case middle
    case tiltLeft
    case tiltRight
    case button4
    case button5
    case button6
    case button7
    case button8

    public var id: String { rawValue }

    /// The button number macOS reports, which counts from zero: left, right,
    /// middle, then the rest. `nil` for wheel tilts, which arrive as
    /// horizontal scroll events instead of button events.
    public var buttonNumber: Int64? {
        switch self {
        case .middle: 2
        case .button4: 3
        case .button5: 4
        case .button6: 5
        case .button7: 6
        case .button8: 7
        case .tiltLeft, .tiltRight: nil
        }
    }

    public init?(buttonNumber: Int64) {
        guard let match = Self.allCases.first(where: { $0.buttonNumber == buttonNumber }) else { return nil }
        self = match
    }

    public var name: String {
        switch self {
        case .middle: "Wheel click"
        case .tiltLeft: "Wheel tilt left"
        case .tiltRight: "Wheel tilt right"
        case .button4: "Back button"
        case .button5: "Forward button"
        case .button6: "Button 6"
        case .button7: "Button 7"
        case .button8: "Button 8"
        }
    }

    public var defaultAction: ButtonAction {
        switch self {
        case .button4: .back
        case .button5: .forward
        default: .passThrough
        }
    }

    /// The `UserDefaults` key the control's action is stored under.
    public var defaultsKey: String { "Action.\(rawValue)" }
}

/// A key press with modifiers.
public struct KeyShortcut: Sendable, Equatable {
    public var keyCode: UInt16
    /// Raw `CGEventFlags`, limited to `KeyShortcut.modifierMask`.
    public var modifiers: UInt64
    /// What to show in the UI, for example "⌘W".
    public var label: String

    /// Control, Option, Shift and Command.
    public static let modifierMask: UInt64 = 0x1E_0000

    public init(keyCode: UInt16, modifiers: UInt64, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
        self.label = label
    }
}

/// What a button does when clicked.
public enum ButtonAction: Sendable, Equatable {
    /// Leave the button alone, as if the app weren't running.
    case passThrough
    /// Block the click and do nothing.
    case nothing
    case back
    case forward
    case missionControl
    case appWindows
    case showDesktop
    /// Press a key combination. `nil` until one has been recorded, and until
    /// then the button is left alone.
    case shortcut(KeyShortcut?)

    /// A compact string for `UserDefaults`, readable with `defaults read`.
    public var storageValue: String {
        switch self {
        case .passThrough: "passThrough"
        case .nothing: "nothing"
        case .back: "back"
        case .forward: "forward"
        case .missionControl: "missionControl"
        case .appWindows: "appWindows"
        case .showDesktop: "showDesktop"
        case .shortcut(nil): "shortcut"
        case .shortcut(let shortcut?): "shortcut:\(shortcut.keyCode):\(shortcut.modifiers):\(shortcut.label)"
        }
    }

    public init?(storageValue: String) {
        switch storageValue {
        case "passThrough": self = .passThrough
        case "nothing": self = .nothing
        case "back": self = .back
        case "forward": self = .forward
        case "missionControl": self = .missionControl
        case "appWindows": self = .appWindows
        case "showDesktop": self = .showDesktop
        case "shortcut": self = .shortcut(nil)
        default:
            // The label comes last because it may itself contain a colon.
            let parts = storageValue.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == "shortcut",
                  let keyCode = UInt16(parts[1]), let modifiers = UInt64(parts[2]), !parts[3].isEmpty
            else { return nil }
            self = .shortcut(KeyShortcut(keyCode: keyCode, modifiers: modifiers, label: String(parts[3])))
        }
    }
}

public struct ButtonSettings: Sendable, Equatable {
    /// Fire on press when true, on release when false.
    public var triggerOnMouseDown: Bool
    private var actions: [MouseButton: ButtonAction]

    public init(triggerOnMouseDown: Bool = true, actions: [MouseButton: ButtonAction] = [:]) {
        self.triggerOnMouseDown = triggerOnMouseDown
        self.actions = actions
    }

    public subscript(button: MouseButton) -> ButtonAction {
        get { actions[button] ?? button.defaultAction }
        set { actions[button] = newValue }
    }

    /// Compares what each control actually does, so a control explicitly set
    /// to its default equals one that was never set.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.triggerOnMouseDown == rhs.triggerOnMouseDown && MouseButton.allCases.allSatisfy { lhs[$0] == rhs[$0] }
    }
}

/// What to do with one mouse event.
public enum ButtonResponse: Sendable, Equatable {
    /// Let the event continue on to apps untouched.
    case passThrough
    /// Drop the event without doing anything.
    case swallow
    /// Drop the event and carry out the action.
    case perform(ButtonAction)
}

public enum ButtonMapper {
    /// For a button press or release.
    public static func response(button: Int64, isDown: Bool, settings: ButtonSettings) -> ButtonResponse {
        guard let button = MouseButton(buttonNumber: button) else { return .passThrough }
        let action = settings[button]
        switch action {
        case .passThrough, .shortcut(nil):
            return .passThrough
        case .nothing:
            return .swallow
        default:
            // Both halves of the click are always dropped, so apps never see a
            // stray button-up without its button-down.
            return isDown == settings.triggerOnMouseDown ? .perform(action) : .swallow
        }
    }

    /// For a scroll event. A wheel tilt arrives as a scroll that is purely
    /// horizontal and comes from a stepped wheel rather than a trackpad.
    /// `horizontal` is positive for left.
    public static func tilt(horizontal: Int64, vertical: Int64, isContinuous: Bool, shiftHeld: Bool) -> MouseButton? {
        // Shift turns ordinary vertical scrolling into horizontal scrolling,
        // which must not be mistaken for a tilt.
        guard !isContinuous, !shiftHeld, vertical == 0, horizontal != 0 else { return nil }
        return horizontal > 0 ? .tiltLeft : .tiltRight
    }

    /// For a wheel tilt. `isNewTilt` is false for the repeats a held tilt sends.
    public static func response(tilt: MouseButton, isNewTilt: Bool, settings: ButtonSettings) -> ButtonResponse {
        let action = settings[tilt]
        switch action {
        case .passThrough, .shortcut(nil):
            return .passThrough
        case .nothing:
            return .swallow
        default:
            return isNewTilt ? .perform(action) : .swallow
        }
    }
}

/// A held tilt sends a stream of scroll events. This picks out the first of
/// each stream so the action fires once per tilt.
public struct TiltDebouncer: Sendable {
    /// A gap this long between events means the wheel was released.
    public static let releaseGap: Double = 0.3

    private var last: (tilt: MouseButton, time: Double)?

    public init() {}

    public mutating func isNewTilt(_ tilt: MouseButton, at time: Double) -> Bool {
        defer { last = (tilt, time) }
        guard let last else { return true }
        return last.tilt != tilt || time - last.time > Self.releaseGap
    }
}
