// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MacMouseButtonsCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: SettingsModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "MacMouseButtons Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // A menu bar app isn't active when its menu is used, so the window
        // would otherwise open behind whatever is in front.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Side Buttons") {
                ButtonRow(button: .button4, model: model)
                ButtonRow(button: .button5, model: model)
            }

            Section("Wheel") {
                ButtonRow(button: .middle, model: model)
                ButtonRow(button: .tiltLeft, model: model)
                ButtonRow(button: .tiltRight, model: model)
            }

            Section {
                ButtonRow(button: .button6, model: model)
                ButtonRow(button: .button7, model: model)
                ButtonRow(button: .button8, model: model)
            } header: {
                Text("Extra Buttons")
            } footer: {
                Text("Back and Forward work as three-finger swipes, so they navigate in almost any app with a history. If Logitech's own software is running, it may handle some buttons before MacMouseButtons sees them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Picker("Trigger when the button is", selection: $model.triggerOnMouseDown) {
                    Text("Pressed").tag(true)
                    Text("Released").tag(false)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ButtonRow: View {
    let button: MouseButton
    @ObservedObject var model: SettingsModel

    private var action: ButtonAction { model.action(for: button) }

    var body: some View {
        Picker(button.name, selection: Binding(
            get: { ActionKind(action) },
            set: { model.setAction($0.action(current: action), for: button) }
        )) {
            ForEach(ActionKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }

        if case .shortcut(let shortcut) = action {
            LabeledContent("Shortcut") {
                ShortcutRecorder(shortcut: shortcut) { model.setAction(.shortcut($0), for: button) }
            }
        }
    }
}

/// A button that, once clicked, takes the next key press as the shortcut.
private struct ShortcutRecorder: View {
    let shortcut: KeyShortcut?
    let onRecord: (KeyShortcut) -> Void

    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        Button(recorder.isRecording ? "Press keys… (Esc to cancel)" : shortcut?.label ?? "Record Shortcut") {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start(onRecord: onRecord)
            }
        }
        .onDisappear { recorder.stop() }
    }
}

@MainActor
private final class KeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func start(onRecord: @escaping (KeyShortcut) -> Void) {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors are always called on the main thread.
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated {
                let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
                let isPlainEscape = event.keyCode == 53 && modifiers.isEmpty
                if !isPlainEscape {
                    onRecord(KeyShortcut(event: event))
                }
                self?.stop()
            }
            // Swallow the key so it doesn't also type or beep.
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
