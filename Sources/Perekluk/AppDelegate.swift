import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyboardMonitor = KeyboardMonitor()
    private let inputSourceManager = InputSourceManager()
    private let textReplacer = TextReplacer()

    private var appStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AXIsProcessTrusted() {
            startApp()
        } else {
            requestAccessibilityAndWait()
        }
    }

    // MARK: - Accessibility

    private func requestAccessibilityAndWait() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.startApp()
            }
        }
    }

    private func startApp() {
        guard !appStarted else { return }
        appStarted = true
        setupStatusItem()
        setupKeyboardMonitor()
        observeInputSourceChanges()
        updateStatusItemTitle()
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
        guard let currentSource = inputSourceManager.getCurrentSource(),
              let otherSource = inputSourceManager.getOtherSource(),
              let otherLayout = inputSourceManager.getLayoutData(for: otherSource) else {
            return
        }

        let currentLayout = inputSourceManager.getLayoutData(for: currentSource)

        var newText = ""
        for stroke in buffer {
            if let char = inputSourceManager.translateKeyCode(
                stroke.keyCode,
                shift: stroke.shift,
                capsLock: stroke.capsLock,
                layoutData: otherLayout
            ) {
                newText += char
            } else if let currentLayout,
                      let original = inputSourceManager.translateKeyCode(
                stroke.keyCode,
                shift: stroke.shift,
                capsLock: stroke.capsLock,
                layoutData: currentLayout
            ) {
                newText += original
            }
        }

        guard !newText.isEmpty else { return }

        textReplacer.replaceText(deleteCount: buffer.count, newText: newText) { [self] in
            inputSourceManager.select(otherSource)
        }
    }

    // MARK: - Selection Switch

    private func handleSelectionSwitch() {
        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount
        let savedContent = pasteboard.string(forType: .string)

        textReplacer.sendCopy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
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

            let restoreChangeCount = pasteboard.changeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard pasteboard.changeCount == restoreChangeCount else { return }
                pasteboard.clearContents()
                if let saved = savedContent {
                    pasteboard.setString(saved, forType: .string)
                }
            }
        }
    }
}
