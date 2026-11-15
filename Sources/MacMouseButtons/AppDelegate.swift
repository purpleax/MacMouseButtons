// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import ApplicationServices
import ServiceManagement
import MacMouseButtonsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SettingsStore()
    private lazy var settingsModel = SettingsModel(store: store) { [weak self] in self?.refresh() }
    private let settingsWindow = SettingsWindowController()
    private let tap = EventTap()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let permissionInfoItem = NSMenuItem(title: "Needs Accessibility access to work", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let permissionSeparator = NSMenuItem.separator()

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacMouseButtons"
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // macOS remembers a hidden status item across launches. Launching the
        // app is how you get the icon back, so always show it.
        statusItem.isVisible = true
        statusItem.menu = makeMenu()
        NSApp.mainMenu = makeMainMenu()

        // Shows the system prompt the first time; does nothing once answered.
        // The key is the value of `kAXTrustedCheckOptionPrompt`, which Swift 6
        // won't let us read directly because C declares it as a mutable global.
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)

        // Permission can be granted or revoked at any time in System Settings,
        // and macOS sends no notification either way.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer

        refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.isVisible = true
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.stop()
    }

    // MARK: State

    /// Brings the event tap and the menu in line with the preferences and the
    /// current Accessibility permission.
    private func refresh() {
        let trusted = AXIsProcessTrusted()
        tap.settings = store.buttonSettings

        if store.enabled && trusted {
            tap.start()
        } else {
            // Stop promptly when permission is revoked: a live tap that macOS
            // no longer trusts can make mouse clicks stall.
            tap.stop()
        }

        // `AXIsProcessTrusted` can keep saying yes after the app is removed
        // from the list, so also treat a refused tap as missing permission.
        let needsPermission = !trusted || (store.enabled && !tap.isRunning)

        enabledItem.state = tap.isRunning ? .on : .off
        enabledItem.isEnabled = !needsPermission
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissionInfoItem.isHidden = !needsPermission
        permissionItem.isHidden = !needsPermission
        permissionSeparator.isHidden = !needsPermission

        if let button = statusItem.button {
            let symbol = tap.isRunning ? "computermouse.fill" : "computermouse"
            let description = tap.isRunning ? "\(appName) is on" : "\(appName) is off"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            image?.isTemplate = true
            button.image = image
            button.appearsDisabled = !tap.isRunning
            button.toolTip = needsPermission ? "\(appName) needs Accessibility access" : description
        }
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        permissionInfoItem.isEnabled = false

        let hideItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hideItem.toolTip = "Open \(appName) again to bring the icon back."

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let aboutItem = NSMenuItem(title: [appName, version].compactMap { $0 }.joined(separator: " "), action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")

        let quitItem = NSMenuItem(title: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q")

        let items: [NSMenuItem] = [
            permissionInfoItem,
            permissionItem,
            permissionSeparator,
            enabledItem,
            .separator(),
            settingsItem,
            .separator(),
            loginItem,
            hideItem,
            .separator(),
            aboutItem,
            quitItem,
        ]
        for item in items {
            if item.action != nil { item.target = self }
            menu.addItem(item)
        }
        return menu
    }

    /// Never visible, because the app has no Dock icon, but it is what makes
    /// ⌘W, ⌘Q and ⌘, work while the settings window is open.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q").target = self
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        return mainMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        store.enabled.toggle()
        refresh()
    }

    @objc private func showSettings() {
        settingsWindow.show(model: settingsModel)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the Launch at Login setting"
            alert.informativeText = "\(error.localizedDescription)\n\nMove \(appName) to the Applications folder and try again, or add it under System Settings › General › Login Items."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refresh()
    }

    @objc private func hideMenuBarIcon() {
        statusItem.isVisible = false
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
