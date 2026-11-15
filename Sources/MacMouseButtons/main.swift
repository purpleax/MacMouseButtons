// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon, no main menu.
app.setActivationPolicy(.accessory)
app.run()
