import AppKit
import Testing
@testable import MacMouseButtonsCore

@Suite struct ButtonMapperTests {
    @Test func unknownButtonsPassThrough() {
        for button: Int64 in [0, 1, 8, 31] {
            for isDown in [true, false] {
                #expect(ButtonMapper.response(button: button, isDown: isDown, settings: .init()) == .passThrough)
            }
        }
    }

    @Test func byDefaultOnlyTheSideButtonsAreRemapped() {
        let settings = ButtonSettings()
        #expect(ButtonMapper.response(button: 3, isDown: true, settings: settings) == .perform(.back))
        #expect(ButtonMapper.response(button: 4, isDown: true, settings: settings) == .perform(.forward))
        #expect(ButtonMapper.response(button: 3, isDown: false, settings: settings) == .swallow)
        for button: Int64 in [2, 5, 6, 7] {
            #expect(ButtonMapper.response(button: button, isDown: true, settings: settings) == .passThrough)
        }
        for tilt in [MouseButton.tiltLeft, .tiltRight] {
            #expect(ButtonMapper.response(tilt: tilt, isNewTilt: true, settings: settings) == .passThrough)
        }
    }

    @Test func triggerOnRelease() {
        let settings = ButtonSettings(triggerOnMouseDown: false)
        #expect(ButtonMapper.response(button: 3, isDown: true, settings: settings) == .swallow)
        #expect(ButtonMapper.response(button: 3, isDown: false, settings: settings) == .perform(.back))
    }

    @Test func everyButtonCanBeAssigned() {
        for button in MouseButton.allCases {
            guard let number = button.buttonNumber else { continue }
            var settings = ButtonSettings()
            settings[button] = .missionControl
            #expect(ButtonMapper.response(button: number, isDown: true, settings: settings) == .perform(.missionControl))
            #expect(ButtonMapper.response(button: number, isDown: false, settings: settings) == .swallow)
        }
    }

    @Test func doNothingBlocksBothHalvesOfTheClick() {
        var settings = ButtonSettings()
        settings[.middle] = .nothing
        #expect(ButtonMapper.response(button: 2, isDown: true, settings: settings) == .swallow)
        #expect(ButtonMapper.response(button: 2, isDown: false, settings: settings) == .swallow)
    }

    @Test func aShortcutThatWasNeverRecordedLeavesTheButtonAlone() {
        var settings = ButtonSettings()
        settings[.button4] = .shortcut(nil)
        #expect(ButtonMapper.response(button: 3, isDown: true, settings: settings) == .passThrough)
        #expect(ButtonMapper.response(button: 3, isDown: false, settings: settings) == .passThrough)
    }
}

@Suite struct TiltTests {
    @Test func recognisesOnlyPureHorizontalSteppedScrolling() {
        #expect(ButtonMapper.tilt(horizontal: 1, vertical: 0, isContinuous: false, shiftHeld: false) == .tiltLeft)
        #expect(ButtonMapper.tilt(horizontal: -3, vertical: 0, isContinuous: false, shiftHeld: false) == .tiltRight)
        // Ordinary scrolling, trackpads, diagonal scrolling and Shift-scrolling are not tilts.
        #expect(ButtonMapper.tilt(horizontal: 0, vertical: 1, isContinuous: false, shiftHeld: false) == nil)
        #expect(ButtonMapper.tilt(horizontal: 1, vertical: 0, isContinuous: true, shiftHeld: false) == nil)
        #expect(ButtonMapper.tilt(horizontal: 1, vertical: 1, isContinuous: false, shiftHeld: false) == nil)
        #expect(ButtonMapper.tilt(horizontal: 1, vertical: 0, isContinuous: false, shiftHeld: true) == nil)
    }

    @Test func aHeldTiltFiresOnce() {
        var settings = ButtonSettings()
        settings[.tiltLeft] = .back
        var debouncer = TiltDebouncer()
        var responses: [ButtonResponse] = []
        for time in [10.0, 10.1, 10.2, 10.3, 10.4] {
            responses.append(ButtonMapper.response(tilt: .tiltLeft, isNewTilt: debouncer.isNewTilt(.tiltLeft, at: time), settings: settings))
        }
        #expect(responses == [.perform(.back), .swallow, .swallow, .swallow, .swallow])
    }

    @Test func tiltingAgainOrTheOtherWayFiresAgain() {
        var debouncer = TiltDebouncer()
        let results = [
            debouncer.isNewTilt(.tiltLeft, at: 1.0),
            debouncer.isNewTilt(.tiltLeft, at: 1.1),
            debouncer.isNewTilt(.tiltRight, at: 1.2),
            debouncer.isNewTilt(.tiltRight, at: 2.0),
        ]
        #expect(results == [true, false, true, true])
    }
}

@Suite struct StorageTests {
    @Test func actionsRoundTrip() {
        let actions: [ButtonAction] = [
            .passThrough, .nothing, .back, .forward, .missionControl, .appWindows, .showDesktop, .shortcut(nil),
            .shortcut(KeyShortcut(keyCode: 13, modifiers: 0x10_0000, label: "⌘W")),
            .shortcut(KeyShortcut(keyCode: 41, modifiers: 0x12_0000, label: "⇧⌘:")),
        ]
        for action in actions {
            #expect(ButtonAction(storageValue: action.storageValue) == action)
        }
        #expect(ButtonAction(storageValue: "nonsense") == nil)
        #expect(ButtonAction(storageValue: "shortcut:x:1:A") == nil)
    }

    @Test func storeFallsBackToDefaultsAndRemembersChanges() throws {
        let suite = "MacMouseButtonsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)

        #expect(store.enabled)
        #expect(store.buttonSettings == ButtonSettings())
        store.setAction(.showDesktop, for: .tiltRight)
        store.triggerOnMouseDown = false
        #expect(store.action(for: .tiltRight) == .showDesktop)
        #expect(store.buttonSettings[.tiltRight] == .showDesktop)
        #expect(store.buttonSettings.triggerOnMouseDown == false)

        defaults.set("garbage", forKey: MouseButton.button4.defaultsKey)
        #expect(store.action(for: .button4) == .back)
    }

    @Test func shortcutEventsCarryKeyAndModifiers() throws {
        let events = KeyPress.events(for: KeyShortcut(keyCode: 13, modifiers: 0x10_0000, label: "⌘W"))
        try #require(events.count == 2)
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        for event in events {
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == 13)
            #expect(event.flags.contains(.maskCommand))
        }
    }
}

/// These tests are the early warning for a macOS update changing the
/// undocumented gesture event format: they ask AppKit to decode the events the
/// same way a receiving app would.
@Suite struct SwipeGestureTests {
    @Test func producesBeganThenEnded() throws {
        let events = SwipeGesture.events(for: .left)
        try #require(events.count == 2)
        #expect(events.map { $0.getIntegerValueField(SwipeGesture.Field.phase) } == [1, 4])
        for event in events {
            #expect(event.type == SwipeGesture.gestureEventType)
            #expect(event.getIntegerValueField(SwipeGesture.Field.hidType) == 16)
        }
    }

    @Test func directionIsOnlyOnTheFinalEvent() throws {
        for direction in SwipeDirection.allCases {
            let events = SwipeGesture.events(for: direction)
            try #require(events.count == 2)
            #expect(events[0].getIntegerValueField(SwipeGesture.Field.swipeDirection) == 0)
            #expect(events[1].getIntegerValueField(SwipeGesture.Field.swipeDirection) == direction.rawValue)
        }
    }

    @Test func appKitDecodesThemAsSwipes() throws {
        // AppKit reports a swipe to the left (back) as deltaX = +1.
        for (direction, deltaX) in [(SwipeDirection.left, CGFloat(1)), (.right, -1)] {
            let events = SwipeGesture.events(for: direction)
            try #require(events.count == 2)
            let began = try #require(NSEvent(cgEvent: events[0]))
            let ended = try #require(NSEvent(cgEvent: events[1]))
            #expect(began.type == .swipe)
            #expect(began.deltaX == 0)
            #expect(ended.type == .swipe)
            #expect(ended.deltaX == deltaX)
            #expect(ended.deltaY == 0)
        }
    }

    @Test func survivesSerialization() throws {
        // Events cross a process boundary on their way to the receiving app.
        let event = try #require(SwipeGesture.events(for: .right).last)
        let data = try #require(event.data)
        let copy = try #require(CGEvent(withDataAllocator: nil, data: data))
        #expect(copy.getIntegerValueField(SwipeGesture.Field.hidType) == 16)
        #expect(copy.getIntegerValueField(SwipeGesture.Field.phase) == 4)
        #expect(copy.getIntegerValueField(SwipeGesture.Field.swipeDirection) == 8)
    }
}
