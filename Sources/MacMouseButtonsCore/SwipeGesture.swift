// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import CoreGraphics

/// Builds the pair of gesture events macOS produces for a three-finger
/// trackpad swipe. Apps receive them as `NSEvent.EventType.swipe`, which is
/// what Safari, Finder, Xcode and most apps with a history respond to.
///
/// macOS has no public API for this. The events are ordinary `CGEvent`s of
/// type `NSEvent.EventType.gesture` carrying three undocumented fields. These
/// field numbers are the one part of the app that depends on macOS internals:
/// if a future macOS breaks swipes, start here. `swift test` and
/// `macmousebuttons-check` both fail loudly when the format stops working.
public enum SwipeGesture {
    /// Undocumented `CGEventField` numbers for gesture events.
    public enum Field {
        /// The IOHID event type the gesture wraps.
        public static let hidType = CGEventField(rawValue: 110)!
        /// `IOHIDSwipeMask` direction.
        public static let swipeDirection = CGEventField(rawValue: 115)!
        /// `CGGesturePhase`.
        public static let phase = CGEventField(rawValue: 132)!
    }

    /// `kIOHIDEventTypeNavigationSwipe`.
    public static let navigationSwipeHIDType: Int64 = 16

    public enum Phase: Int64, Sendable {
        case began = 1
        case ended = 4
    }

    public static let gestureEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!

    /// The began/ended pair for one swipe, in the order they must be posted.
    public static func events(for direction: SwipeDirection) -> [CGEvent] {
        // The direction goes only on the final event; putting it on both makes
        // some apps navigate twice.
        [makeEvent(phase: .began, direction: nil), makeEvent(phase: .ended, direction: direction)].compactMap { $0 }
    }

    /// Posts a swipe as if it came from the hardware.
    /// Needs Accessibility permission; without it macOS silently drops the events.
    public static func post(_ direction: SwipeDirection) {
        for event in events(for: direction) {
            event.post(tap: .cghidEventTap)
        }
    }

    static func makeEvent(phase: Phase, direction: SwipeDirection?) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.type = gestureEventType
        // NX_NONCOALSESCEDMASK, which real gesture events carry.
        event.flags = CGEventFlags(rawValue: 0x100)
        event.setIntegerValueField(Field.hidType, value: navigationSwipeHIDType)
        event.setIntegerValueField(Field.phase, value: phase.rawValue)
        if let direction {
            event.setIntegerValueField(Field.swipeDirection, value: direction.rawValue)
        }
        return event
    }
}
