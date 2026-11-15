// SPDX-License-Identifier: GPL-2.0-or-later
//
// End-to-end check: clicks each side button with synthetic events and confirms
// a running copy of MacMouseButtons turns them into swipes. Run it after a macOS
// update to find out whether anything broke.
//
// Nothing reaches your apps: this tool sits further down the event pipeline
// than MacMouseButtons and removes the test events before they are delivered.

import AppKit
import ApplicationServices
import MacMouseButtonsCore

guard AXIsProcessTrusted() else {
    print("FAIL  This terminal needs Accessibility access to post test clicks.")
    print("      System Settings › Privacy & Security › Accessibility")
    exit(2)
}

final class Observer {
    var leakedButtons: [Int64] = []
    var swipes: [SwipeDirection] = []
    var beganCount = 0
}

let observer = Observer()

let mask = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
    | CGEventMask(1) << CGEventType.otherMouseUp.rawValue
    | CGEventMask(1) << SwipeGesture.gestureEventType.rawValue

let callback: CGEventTapCallBack = { _, type, event, userInfo in
    let observer = Unmanaged<Observer>.fromOpaque(userInfo!).takeUnretainedValue()
    switch type {
    case .otherMouseDown, .otherMouseUp:
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard button == ButtonMapper.backButton || button == ButtonMapper.forwardButton else { break }
        observer.leakedButtons.append(button)
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

@MainActor func settle(_ seconds: TimeInterval = 0.3) {
    CFRunLoopRunInMode(.defaultMode, seconds, false)
}

@MainActor func click(_ button: Int64) -> (leaked: Bool, began: Int, swipes: [SwipeDirection]) {
    observer.leakedButtons = []
    observer.swipes = []
    observer.beganCount = 0
    let position = CGEvent(source: nil)?.location ?? .zero
    for type in [CGEventType.otherMouseDown, .otherMouseUp] {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        event.post(tap: .cghidEventTap)
        settle(0.05)
    }
    settle()
    return (!observer.leakedButtons.isEmpty, observer.beganCount, observer.swipes)
}

settle(0.1)
var failed = false
var directions: [Int64: SwipeDirection] = [:]

for (button, name) in [(ButtonMapper.backButton, "Button 4 (back)"), (ButtonMapper.forwardButton, "Button 5 (forward)")] {
    let result = click(button)
    if result.leaked {
        print("FAIL  \(name): the click was not intercepted. Is MacMouseButtons running, enabled, and allowed under Accessibility?")
        failed = true
    } else if result.swipes.count != 1 || result.began != 1 {
        print("FAIL  \(name): expected one swipe, saw \(result.began) began and \(result.swipes.count) ended events.")
        failed = true
    } else {
        directions[button] = result.swipes[0]
        print("ok    \(name) → swipe \(result.swipes[0])")
    }
}

if !failed, directions[ButtonMapper.backButton] == directions[ButtonMapper.forwardButton] {
    print("FAIL  Both buttons swiped the same way.")
    failed = true
}

CGEvent.tapEnable(tap: port, enable: false)
print(failed ? "\nMacMouseButtons is NOT working." : "\nMacMouseButtons is working.")
exit(failed ? 1 : 0)
