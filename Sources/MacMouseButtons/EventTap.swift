// SPDX-License-Identifier: GPL-2.0-or-later

import CoreGraphics
import Foundation
import MacMouseButtonsCore

/// Intercepts clicks of the configured buttons system-wide and carries out
/// their actions instead.
@MainActor
final class EventTap {
    /// Read on every click, so changes apply immediately.
    var settings = ButtonSettings()

    private var tiltDebouncer = TiltDebouncer()
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
            | CGEventMask(1) << CGEventType.scrollWheel.rawValue

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
            switch ButtonMapper.response(button: button, isDown: type == .otherMouseDown, settings: settings) {
            case .passThrough:
                return true
            case .swallow:
                return false
            case .perform(let action):
                ActionPerformer.perform(action)
                return false
            }

        case .scrollWheel:
            guard let tilt = ButtonMapper.tilt(
                horizontal: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                vertical: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                shiftHeld: event.flags.contains(.maskShift)
            ) else { return true }
            let isNewTilt = tiltDebouncer.isNewTilt(tilt, at: ProcessInfo.processInfo.systemUptime)
            switch ButtonMapper.response(tilt: tilt, isNewTilt: isNewTilt, settings: settings) {
            case .passThrough:
                return true
            case .swallow:
                return false
            case .perform(let action):
                ActionPerformer.perform(action)
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
