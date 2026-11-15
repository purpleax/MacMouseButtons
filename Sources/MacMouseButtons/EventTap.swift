// SPDX-License-Identifier: GPL-2.0-or-later

import CoreGraphics
import Foundation
import MacMouseButtonsCore

/// Intercepts side-button clicks system-wide and replaces them with swipes.
@MainActor
final class EventTap {
    /// Read on every click, so changes apply immediately.
    var settings = ButtonSettings()

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Returns false when macOS refuses the tap, which means Accessibility
    /// permission is missing.
    @discardableResult
    func start() -> Bool {
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return isRunning
        }

        let mask = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
            | CGEventMask(1) << CGEventType.otherMouseUp.rawValue

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.port = port
        self.source = source
        return isRunning
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil
    }

    /// Returns true when the event should continue on to apps.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches a tap off if it ever responds slowly (for example
            // while the Mac wakes from sleep). Without this, the side buttons
            // would silently stop working until the app was restarted.
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return true

        case .otherMouseDown, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            switch ButtonMapper.action(button: button, isDown: type == .otherMouseDown, settings: settings) {
            case .passThrough:
                return true
            case .swallow:
                return false
            case .swipe(let direction):
                SwipeGesture.post(direction)
                return false
            }

        default:
            return true
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    // The tap's run loop source is on the main run loop, so this callback is
    // always on the main thread; the compiler just can't see that through a C
    // function pointer.
    nonisolated(unsafe) let tappedEvent = event
    nonisolated(unsafe) let tapPointer = userInfo
    let passThrough = MainActor.assumeIsolated {
        Unmanaged<EventTap>.fromOpaque(tapPointer).takeUnretainedValue().handle(type: type, event: tappedEvent)
    }
    return passThrough ? Unmanaged.passUnretained(event) : nil
}
