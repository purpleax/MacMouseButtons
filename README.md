# MacMouseButtons

Makes the back and forward side buttons on third-party mice work everywhere on
macOS. Each click is turned into a three-finger swipe, which is what Safari,
Finder, Xcode and most other apps with a history already respond to.

This is a Swift rewrite of
[SensibleSideButtons](https://github.com/archagon/sensible-side-buttons) by
Alexei Baboulevitch, built so it can be rebuilt and checked on each new macOS
with nothing but the command line tools. It needs macOS 13 or later.

## Build and install

```bash
scripts/build-app.sh
```

This produces `build/MacMouseButtons.app`. Copy it to `/Applications`, open it, and
allow it under **System Settings › Privacy & Security › Accessibility** when
asked. The mouse icon in the menu bar fills in once it is working.

`UNIVERSAL=1 scripts/build-app.sh` builds for both Apple silicon and Intel.

The script signs with your Developer ID certificate if you have one, so the
Accessibility permission survives rebuilds. Without one it signs ad hoc, and
after every rebuild you have to remove the app from the Accessibility list and
add it again.

## Menu

| Item | What it does |
| --- | --- |
| Enabled | Turns the remapping on and off. |
| Trigger on Mouse Down | Fires when the button is pressed. Untick to fire on release. |
| Swap Buttons | Swaps which button goes back and which goes forward. |
| Launch at Login | Starts the app when you log in. Works best from `/Applications`. |
| Hide Menu Bar Icon | Hides the icon. Open the app again to bring it back. |

## Checking it after a macOS update

```bash
scripts/test.sh
```

Unit tests. They include asking AppKit to decode the synthesized events, so
they fail if macOS changes the gesture event format.

```bash
swift run macmousebuttons-check
```

End-to-end check against the running app. It posts synthetic side-button
clicks, confirms each one is intercepted and comes out as exactly one swipe in
the right direction, and removes the test events before any app sees them.
Your terminal needs Accessibility permission to run it. It can't tell which app
did the remapping, so quit SensibleSideButtons or similar tools first.

## How it works

1. A `CGEventTap` at the HID level watches for `otherMouseDown` and
   `otherMouseUp` events with button number 3 or 4 and drops them
   (`Sources/MacMouseButtons/EventTap.swift`).
2. In their place it posts two gesture events, began then ended, that AppKit
   delivers to apps as `NSEvent.EventType.swipe`
   (`Sources/MacMouseButtonsCore/SwipeGesture.swift`).

macOS has no public API for step 2. The events are built with the public
`CGEvent` API but use three undocumented field numbers (110, 115 and 132).
That file is the only part that depends on macOS internals, and it is the first
place to look if a future macOS breaks things.

Differences from the original:

- If macOS disables the event tap (it does this when a tap responds slowly,
  for example around sleep and wake), the tap is switched back on.
- It notices Accessibility permission being granted or revoked while running.
- Launch at Login is built in.
- No storyboard, asset catalogue, Objective-C or Xcode project.

## Licence

GPL-2.0-or-later, the same as SensibleSideButtons, which this is derived from.
See `LICENSE`.
