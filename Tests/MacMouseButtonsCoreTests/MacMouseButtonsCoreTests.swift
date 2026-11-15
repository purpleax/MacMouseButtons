import AppKit
import Testing
@testable import MacMouseButtonsCore

@Suite struct ButtonMapperTests {
    @Test func otherButtonsPassThrough() {
        for button: Int64 in [0, 1, 2, 5, 6, 31] {
            for isDown in [true, false] {
                #expect(ButtonMapper.action(button: button, isDown: isDown, settings: .init()) == .passThrough)
            }
        }
    }

    @Test func defaultsGoBackOnButton3AndForwardOnButton4() {
        let settings = ButtonSettings()
        #expect(ButtonMapper.action(button: 3, isDown: true, settings: settings) == .swipe(.left))
        #expect(ButtonMapper.action(button: 4, isDown: true, settings: settings) == .swipe(.right))
        #expect(ButtonMapper.action(button: 3, isDown: false, settings: settings) == .swallow)
        #expect(ButtonMapper.action(button: 4, isDown: false, settings: settings) == .swallow)
    }

    @Test func triggerOnMouseUp() {
        let settings = ButtonSettings(triggerOnMouseDown: false)
        #expect(ButtonMapper.action(button: 3, isDown: true, settings: settings) == .swallow)
        #expect(ButtonMapper.action(button: 3, isDown: false, settings: settings) == .swipe(.left))
        #expect(ButtonMapper.action(button: 4, isDown: false, settings: settings) == .swipe(.right))
    }

    @Test func swapButtons() {
        let settings = ButtonSettings(swapButtons: true)
        #expect(ButtonMapper.action(button: 3, isDown: true, settings: settings) == .swipe(.right))
        #expect(ButtonMapper.action(button: 4, isDown: true, settings: settings) == .swipe(.left))
    }

    @Test func everyClickFiresExactlyOnce() {
        for triggerOnMouseDown in [true, false] {
            for swapButtons in [true, false] {
                let settings = ButtonSettings(triggerOnMouseDown: triggerOnMouseDown, swapButtons: swapButtons)
                for button: Int64 in [3, 4] {
                    let actions = [true, false].map { ButtonMapper.action(button: button, isDown: $0, settings: settings) }
                    #expect(actions.filter { $0 == .swallow }.count == 1)
                    #expect(!actions.contains(.passThrough))
                }
            }
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
