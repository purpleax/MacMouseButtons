// SPDX-License-Identifier: GPL-2.0-or-later
//
// End-to-end check: operates every configurable mouse control with synthetic
// events and confirms the running copy of MacMouseButtons does what its
// settings say. Run it after a macOS update to find out whether anything broke.
//
// Nothing reaches your apps: this tool sits further down the event pipeline
// than MacMouseButtons and removes the test events before they are delivered.

import AppKit
import ApplicationServices
import MacMouseButtonsCore

guard AXIsProcessTrusted() else {
    print("FAIL  This terminal needs Accessibility access to post test events.")
    print("      System Settings › Privacy & Security › Accessibility")
    exit(2)
}

guard let appDefaults = UserDefaults(suiteName: SettingsStore.appDomain) else {
    print("FAIL  Couldn't read the app's settings.")
    exit(2)
}
let store = SettingsStore(defaults: appDefaults)

final class Observer {
    var sawInput = false
    var swipes: [SwipeDirection] = []
    var beganCount = 0
    var keyDowns: [(keyCode: UInt16, modifiers: UInt64)] = []

    func reset() {
        sawInput = false
        swipes = []
        beganCount = 0
        keyDowns = []
    }
}

let observer = Observer()

let mask = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
    | CGEventMask(1) << CGEventType.otherMouseUp.rawValue
    | CGEventMask(1) << CGEventType.scrollWheel.rawValue
    | CGEventMask(1) << CGEventType.keyDown.rawValue
    | CGEventMask(1) << CGEventType.keyUp.rawValue
    | CGEventMask(1) << SwipeGesture.gestureEventType.rawValue

/// Marks the key events this tool expects, so real typing is left alone.
nonisolated(unsafe) var expectedKeyCode: UInt16?

let callback: CGEventTapCallBack = { _, type, event, userInfo in
    let observer = Unmanaged<Observer>.fromOpaque(userInfo!).takeUnretainedValue()
    switch type {
    case .otherMouseDown, .otherMouseUp:
        guard MouseButton(buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber)) != nil else { break }
        observer.sawInput = true
        return nil
    case .scrollWheel:
        guard ButtonMapper.tilt(
            horizontal: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            vertical: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            shiftHeld: event.flags.contains(.maskShift)
        ) != nil else { break }
        observer.sawInput = true
        return nil
    case .keyDown, .keyUp:
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == expectedKeyCode else { break }
        if type == .keyDown {
            observer.keyDowns.append((keyCode, event.flags.rawValue & KeyShortcut.modifierMask))
        }
        return nil
    case SwipeGesture.gestureEventType:
        guard event.getIntegerValueField(SwipeGesture.Field.hidType) == SwipeGesture.navigationSwipeHIDType else { break }
        switch event.getIntegerValueField(SwipeGesture.Field.phase) {
        case SwipeGesture.Phase.began.rawValue:
            observer.beganCount += 1
        case SwipeGesture.Phase.ended.rawValue:
            if let direction = SwipeDirection(rawValue: event.getIntegerValueField(SwipeGesture.Field.swipeDirection)) {
                observer.swipes.append(direction)
            }
        default:
            break
        }
        return nil
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

// The session tap comes after the HID tap MacMouseButtons uses, so this sees
// exactly what MacMouseButtons lets through or adds.
guard let port = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: callback,
    userInfo: Unmanaged.passUnretained(observer).toOpaque()
) else {
    print("FAIL  Couldn't create an event tap.")
    exit(2)
}
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
CGEvent.tapEnable(tap: port, enable: true)

@MainActor func settle(_ seconds: TimeInterval) {
    CFRunLoopRunInMode(.defaultMode, seconds, false)
}

/// Operates the control once with synthetic events.
@MainActor func operate(_ button: MouseButton) {
    if let number = button.buttonNumber {
        let position = CGEvent(source: nil)?.location ?? .zero
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: .center)!
            event.setIntegerValueField(.mouseEventButtonNumber, value: number)
            event.post(tap: .cghidEventTap)
            settle(0.05)
        }
    } else {
        let amount: Int32 = button == .tiltLeft ? 1 : -1
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: amount, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }
    settle(0.35)
}

if !store.enabled {
    print("note  MacMouseButtons is switched off in its menu, so expect failures.\n")
}

settle(0.1)
var failures = 0

for button in MouseButton.allCases {
    let action = store.action(for: button)
    let name = button.name.padding(toLength: 17, withPad: " ", startingAt: 0)

    func report(_ ok: Bool, _ message: String) {
        print("\(ok ? "ok   " : "FAIL ") \(name) \(message)")
        if !ok { failures += 1 }
    }

    switch action {
    case .missionControl, .appWindows, .showDesktop:
        print("skip  \(name) set to \(action.storageValue); testing it would open Mission Control")
        continue
    default:
        break
    }

    observer.reset()
    if case .shortcut(let shortcut?) = action { expectedKeyCode = shortcut.keyCode } else { expectedKeyCode = nil }
    operate(button)

    let noSwipes = observer.swipes.isEmpty && observer.beganCount == 0
    switch action {
    case .passThrough, .shortcut(nil):
        report(observer.sawInput && noSwipes, observer.sawInput ? "left alone" : "should be left alone, but was blocked")
    case .nothing:
        report(!observer.sawInput && noSwipes, observer.sawInput ? "should be blocked, but got through" : "blocked")
    case .back, .forward:
        let expected: SwipeDirection = action == .back ? .left : .right
        if observer.sawInput {
            report(false, "was not intercepted. Is MacMouseButtons running and allowed under Accessibility?")
        } else if observer.beganCount != 1 || observer.swipes != [expected] {
            report(false, "expected one swipe \(expected), saw \(observer.beganCount) began and \(observer.swipes) ended")
        } else {
            report(true, "→ \(action.storageValue) (swipe \(expected))")
        }
    case .shortcut(let shortcut?):
        let pressed = observer.keyDowns.count == 1 && observer.keyDowns[0].modifiers == shortcut.modifiers
        report(!observer.sawInput && pressed, pressed ? "→ \(shortcut.label)" : "expected \(shortcut.label), saw \(observer.keyDowns.count) matching key presses")
    case .missionControl, .appWindows, .showDesktop:
        break
    }
}

CGEvent.tapEnable(tap: port, enable: false)
print(failures == 0 ? "\nMacMouseButtons is working." : "\nMacMouseButtons is NOT working (\(failures) failed).")
exit(failures == 0 ? 0 : 1)
