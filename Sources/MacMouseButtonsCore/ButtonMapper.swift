// MacMouseButtons — makes the side buttons on third-party mice navigate back and forward.
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

public struct ButtonSettings: Sendable, Equatable {
    /// Fire on press when true, on release when false.
    public var triggerOnMouseDown: Bool
    /// Swap which side button goes back and which goes forward.
    public var swapButtons: Bool

    public init(triggerOnMouseDown: Bool = true, swapButtons: Bool = false) {
        self.triggerOnMouseDown = triggerOnMouseDown
        self.swapButtons = swapButtons
    }
}

public enum ButtonAction: Sendable, Equatable {
    /// Not a side button: leave the event alone.
    case passThrough
    /// A side button event that should be dropped without doing anything.
    case swallow
    /// A side button event that should be dropped and replaced with a swipe.
    case swipe(SwipeDirection)
}

public enum ButtonMapper {
    /// macOS numbers mouse buttons from zero: left, right, middle, then the side buttons.
    public static let backButton: Int64 = 3
    public static let forwardButton: Int64 = 4

    public static func action(button: Int64, isDown: Bool, settings: ButtonSettings) -> ButtonAction {
        let direction: SwipeDirection
        switch button {
        case backButton: direction = settings.swapButtons ? .right : .left
        case forwardButton: direction = settings.swapButtons ? .left : .right
        default: return .passThrough
        }
        // Both halves of the click are always dropped, so apps never see a
        // stray button-up without its button-down.
        return isDown == settings.triggerOnMouseDown ? .swipe(direction) : .swallow
    }
}
