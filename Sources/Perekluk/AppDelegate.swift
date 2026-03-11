import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyboardMonitor = KeyboardMonitor()
    private let inputSourceManager = InputSourceManager()
    private let textReplacer = TextReplacer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard checkAccessibility() else { return }
        setupStatusItem()
        setupKeyboardMonitor()
        observeInputSourceChanges()
        updateStatusItemTitle()
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Perekluk needs Accessibility access"
            alert.informativeText = "Open System Settings → Privacy & Security → Accessibility and enable Perekluk. Then relaunch the app."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Quit")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            NSApp.terminate(nil)
            return false
        }
        return true
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Perekluk", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func observeInputSourceChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }

    @objc private func inputSourceDidChange(_ notification: Notification) {
        updateStatusItemTitle()
    }

    private func updateStatusItemTitle() {
        guard let source = inputSourceManager.getCurrentSource(),
              let sourceId = inputSourceManager.sourceId(for: source) else { return }

        let label: String
        if sourceId.localizedCaseInsensitiveContains("russian") {
            label = "Ру"
        } else if sourceId.localizedCaseInsensitiveContains("english") || sourceId.localizedCaseInsensitiveContains("us") {
            label = "En"
        } else {
            label = String(sourceId.split(separator: ".").last?.prefix(2) ?? "??")
        }

        statusItem.button?.title = label
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Keyboard Monitor

    private func setupKeyboardMonitor() {
        keyboardMonitor.onSwitchTriggered = { [weak self] buffer in
            self?.handleSwitch(buffer)
        }
        keyboardMonitor.start()
    }

    private func handleSwitch(_ buffer: [KeyStroke]) {
        if buffer.isEmpty {
            handleSelectionSwitch()
        } else {
            handleBufferSwitch(buffer)
        }
    }

    // MARK: - Buffer Switch

    private func handleBufferSwitch(_ buffer: [KeyStroke]) {
        guard let otherSource = inputSourceManager.getOtherSource(),
              let layoutData = inputSourceManager.getLayoutData(for: otherSource) else {
            return
        }

        var newText = ""
        for stroke in buffer {
            if let char = inputSourceManager.translateKeyCode(
                stroke.keyCode,
                shift: stroke.shift,
                capsLock: stroke.capsLock,
                layoutData: layoutData
            ) {
                newText += char
            }
        }

        guard !newText.isEmpty else { return }

        textReplacer.replaceText(deleteCount: buffer.count, newText: newText)
        inputSourceManager.select(otherSource)
    }

    // MARK: - Selection Switch

    private func handleSelectionSwitch() {
        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount
        let savedContent = pasteboard.string(forType: .string)

        textReplacer.sendCopy()
        usleep(100_000)

        guard pasteboard.changeCount != savedChangeCount,
              let selectedText = pasteboard.string(forType: .string),
              !selectedText.isEmpty else {
            inputSourceManager.selectNextSource()
            return
        }

        guard let currentSource = inputSourceManager.getCurrentSource(),
              let otherSource = inputSourceManager.getOtherSource(),
              let converted = inputSourceManager.convertText(selectedText, fromSource: currentSource, toSource: otherSource) else {
            inputSourceManager.selectNextSource()
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        textReplacer.sendPaste()
        inputSourceManager.select(otherSource)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let saved = savedContent {
                pasteboard.setString(saved, forType: .string)
            }
        }
    }
}
