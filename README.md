# MacMouseButtons

Choose what the extra buttons on a third-party mouse do on macOS. Out of the
box, the two side buttons go back and forward in almost every app, which macOS
doesn't do on its own.

Back and Forward are sent as three-finger swipes, which is what Safari, Finder,
Xcode and most other apps with a history already respond to.

This is a Swift rewrite and extension of
[SensibleSideButtons](https://github.com/archagon/sensible-side-buttons) by
Alexei Baboulevitch. It needs macOS 13 or later.

## Install

Download the latest `.dmg` from
[Releases](https://github.com/purpleax/MacMouseButtons/releases), open it and
drag MacMouseButtons to Applications. Open the app and allow it under
**System Settings › Privacy & Security › Accessibility** when asked. The mouse
icon in the menu bar fills in once it is working.

## Settings

Choose **Settings…** from the menu bar icon.

| Control | Default |
| --- | --- |
| Back button (button 4) | Back |
| Forward button (button 5) | Forward |
| Wheel click | Leave Alone |
| Wheel tilt left, wheel tilt right | Leave Alone |
| Buttons 6, 7 and 8 | Leave Alone |

Each control can be set to:

| Action | What it does |
| --- | --- |
| Leave Alone | The control behaves as if the app weren't running. |
| Do Nothing | Blocks the control. |
| Back, Forward | Navigates, by sending a three-finger swipe. |
| Mission Control, Application Windows, Show Desktop | Opens that view. Click again to leave it. |
| Keyboard Shortcut | Presses a key combination you record. |

Buttons act when pressed; you can change that to when released.

The menu also has **Enabled**, **Launch at Login** and **Hide Menu Bar Icon**
(open the app again to bring the icon back).

### Notes for Logitech mice

- MacMouseButtons sees the standard events a mouse sends. If Logi Options+ is
  running, it may handle some buttons first.
- A wheel tilt reaches macOS as a horizontal scroll, and holding the tilt
  repeats it. MacMouseButtons treats each hold as one click. Trackpad
  scrolling and Shift-scrolling are never treated as tilts.
- Controls that only work through Logitech's software, such as the thumb wheel
  and gesture button on MX mice, send nothing standard and can't be configured
  here.

## Build from source

Only the Xcode command line tools are needed.

```bash
scripts/build-app.sh
```

This produces `build/MacMouseButtons.app`. `UNIVERSAL=1` builds for both Apple
silicon and Intel. The script signs with your Developer ID certificate if you
have one, so the Accessibility permission survives rebuilds. Without one it
signs ad hoc, and after every rebuild you have to remove the app from the
Accessibility list and add it again.

```bash
scripts/release.sh
```

Builds a notarised disk image for a release. This one needs Xcode, a Developer
ID certificate and a `notarytool` keychain profile; see the top of the script.

## Checking it after a macOS update

```bash
scripts/test.sh
```

Unit tests. They include asking AppKit to decode the synthesized swipe events,
so they fail if macOS changes the gesture event format.

```bash
swift run macmousebuttons-check
```

End-to-end check against the installed, running app. It operates every control
with synthetic events and confirms the app does what its settings say, then
removes the test events before any app sees them. Controls set to Mission
Control views are skipped. Your terminal needs Accessibility permission to run
it, and other button-remapping tools should be quit first.

## How it works

1. A `CGEventTap` at the HID level watches for extra-button presses and
   horizontal scroll steps, and drops the ones that are configured
   (`Sources/MacMouseButtons/EventTap.swift`).
2. In their place it carries out the action
   (`Sources/MacMouseButtons/ActionPerformer.swift`).

Two actions rely on macOS behaviour that isn't public API, and are the first
places to look if a future macOS breaks something:

- **Back and Forward** post gesture events built with the public `CGEvent` API
  but using three undocumented field numbers
  (`Sources/MacMouseButtonsCore/SwipeGesture.swift`).
- **Mission Control views** run the Mission Control app with an undocumented
  argument.

## Licence

GPL-2.0-or-later, the same as SensibleSideButtons, which this is derived from.
See `LICENSE`.
