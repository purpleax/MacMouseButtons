// SPDX-License-Identifier: GPL-2.0-or-later

import CoreGraphics

/// Builds and posts the key-down/key-up pair for a shortcut.
public enum KeyPress {
    public static func events(for shortcut: KeyShortcut) -> [CGEvent] {
        [true, false].compactMap { keyDown in
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: keyDown)
            event?.flags = CGEventFlags(rawValue: shortcut.modifiers)
            return event
        }
    }

    /// Needs Accessibility permission; without it macOS silently drops the events.
    public static func post(_ shortcut: KeyShortcut) {
        for event in events(for: shortcut) {
            event.post(tap: .cghidEventTap)
        }
    }
}
