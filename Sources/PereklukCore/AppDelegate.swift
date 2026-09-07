import AppKit
import Carbon
import ServiceManagement

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem?
    let keyboardMonitor = KeyboardMonitor()
    var inputSourceManager: InputSourceManaging = InputSourceManager()
    var textReplacer: TextReplacing = TextReplacer()
    var pasteboard: PasteboardProviding = NSPasteboard.general
    var accessibilityReader: AccessibilityReading = AccessibilityReader()

    private var appStarted = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        observeInputSourceChanges()
        observeAppActivation()
        updateStatusItemTitle()
        startUninstallWatcher()
        registerLoginItemOnFirstLaunch()

        setupKeyboardMonitor()
    }

    // MARK: - Accessibility

    private func requestAccessibilityAndWait() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Poll by attempting the tap itself: AXIsProcessTrusted() can stay false
        // in a running process after the grant on macOS 13+
        Timer.scheduledTimer(withTimeInterval: Timing.accessibilityCheckInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.keyboardMonitor.start() {
                timer.invalidate()
            }
        }
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

        let triggerItem = NSMenuItem(title: "Trigger Key", action: nil, keyEquivalent: "")
        triggerItem.submenu = buildTriggerKeySubmenu()
        menu.addItem(triggerItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Launch at Login

    private static let didRegisterLoginItemKey = "didRegisterLoginItem"

    private func registerLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.didRegisterLoginItemKey) else { return }
        // No bundle (swift run) — SMAppService cannot register a bare executable
        guard Bundle.main.bundleIdentifier != nil else { return }
        // Translocated run (opened from DMG/Downloads) would record a random read-only path
        guard !Bundle.main.bundlePath.contains("/AppTranslocation/") else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: Self.didRegisterLoginItemKey)
        } catch {
            // Retry on next launch (e.g. app translocated on first run from DMG)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        } else {
            try? service.register()
            // A manual toggle is an explicit choice — stop the first-launch auto-register
            UserDefaults.standard.set(true, forKey: Self.didRegisterLoginItemKey)
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        sender.state = (service.status == .enabled) ? .on : .off
    }

    private func buildTriggerKeySubmenu() -> NSMenu {
        let submenu = NSMenu()
        let current = Settings.triggerKey
        for key in TriggerKey.allCases {
            let item = NSMenuItem(title: key.displayName, action: #selector(triggerKeySelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key.rawValue
            item.state = (key == current) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func triggerKeySelected(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let newKey = TriggerKey(rawValue: rawValue) else { return }
        Settings.triggerKey = newKey
        keyboardMonitor.triggerKey = newKey

        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item.representedObject as? String == rawValue) ? .on : .off
            }
        }
    }

    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeAppDidChange(_ notification: Notification) {
        keyboardMonitor.clearBuffer()
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
        guard let language = inputSourceManager.currentSourceLanguage() else { return }
        statusItem.button?.title = Self.statusLabel(forLanguage: language)
    }

    public static func statusLabel(forLanguage language: String) -> String {
        language.hasPrefix("ru") ? "Ру" : String(language.prefix(2)).capitalized
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Uninstall Watcher

    private func startUninstallWatcher() {
        let path = Bundle.main.bundlePath
        Timer.scheduledTimer(withTimeInterval: Timing.uninstallCheckInterval, repeats: true) { timer in
            if !FileManager.default.fileExists(atPath: path) {
                timer.invalidate()
                NSApp.terminate(nil)
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        guard !FileManager.default.fileExists(atPath: Bundle.main.bundlePath) else { return }
        try? SMAppService.mainApp.unregister()
        let bundleId = Bundle.main.bundleIdentifier ?? "com.perekluk.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleId]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Keyboard Monitor

    private func setupKeyboardMonitor() {
        keyboardMonitor.triggerKey = Settings.triggerKey
        keyboardMonitor.onSwitchTriggered = { [weak self] word, trailingSpaces in
            self?.handleSwitch(word, trailingSpaces: trailingSpaces)
        }
        if !keyboardMonitor.start() {
            requestAccessibilityAndWait()
        }
    }

    func handleSwitch(_ word: [KeyStroke], trailingSpaces: Int) {
        if word.isEmpty {
            handleSelectionSwitch()
        } else {
            handleBufferSwitch(word, trailingSpaces: trailingSpaces)
        }
    }

    // MARK: - Clipboard Helpers

    private func savePasteboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
        return (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    private func scheduleRestore(_ saved: [[(NSPasteboard.PasteboardType, Data)]], afterCharCount charCount: Int) {
        let restoreChangeCount = pasteboard.changeCount
        let delay = Timing.clipboardRestoreDelay(charCount: charCount)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard pasteboard.changeCount == restoreChangeCount else { return }
            guard !saved.isEmpty else { return }
            pasteboard.clearContents()
            let items = saved.map { itemData -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in itemData { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - Buffer Switch

    private func handleBufferSwitch(_ buffer: [KeyStroke], trailingSpaces: Int) {
        guard let currentId = inputSourceManager.currentSourceId(),
              let otherId = inputSourceManager.otherSourceId(excluding: currentId) else { return }

        guard var newText = inputSourceManager.convertKeyStrokes(
            buffer, fromSourceId: currentId, toSourceId: otherId
        ), !newText.isEmpty else { return }

        if trailingSpaces > 0 {
            newText += String(repeating: " ", count: trailingSpaces)
        }

        // Dead keys compose: N keystrokes may have produced fewer on-screen characters,
        // so count what the current layout rendered, not the keystrokes
        let typedText = inputSourceManager.convertKeyStrokes(
            buffer, fromSourceId: currentId, toSourceId: currentId
        )
        let deleteCount = (typedText?.count ?? buffer.count) + trailingSpaces
        let saved = savePasteboard()
        let deleteDelay = Timing.deleteDelay(charCount: deleteCount)

        DispatchQueue.main.asyncAfter(deadline: .now() + deleteDelay) { [self] in
            textReplacer.deleteChars(count: deleteCount)

            DispatchQueue.main.asyncAfter(deadline: .now() + deleteDelay) { [self] in
                pasteboard.clearContents()
                pasteboard.setString(newText, forType: .string)
                textReplacer.sendPaste()
                inputSourceManager.selectSource(otherId)
                scheduleRestore(saved, afterCharCount: deleteCount)
            }
        }
    }

    // MARK: - Selection Switch

    private func handleSelectionSwitch() {
        if let axText = accessibilityReader.getSelectedText(), !axText.isEmpty {
            handleSelectionConversion(axText, usedClipboard: false)
        } else {
            let savedChangeCount = pasteboard.changeCount
            let saved = savePasteboard()
            textReplacer.sendCopy()

            pollPasteboard(savedChangeCount: savedChangeCount) { [self] selectedText in
                // Cmd+C in Finder & co. copies files, not text; converting and pasting
                // the name back would duplicate the file into the folder
                let copiedFiles = pasteboard.string(forType: .fileURL) != nil
                guard let selectedText, !selectedText.isEmpty, !copiedFiles else {
                    if pasteboard.changeCount != savedChangeCount {
                        scheduleRestore(saved, afterCharCount: 0)
                    }
                    inputSourceManager.selectNextSource()
                    return
                }
                handleSelectionConversion(selectedText, usedClipboard: true, savedClipboard: saved)
            }
        }
    }

    private func handleSelectionConversion(
        _ selectedText: String,
        usedClipboard: Bool,
        savedClipboard: [[(NSPasteboard.PasteboardType, Data)]] = []
    ) {
        guard let currentId = inputSourceManager.currentSourceId() else {
            inputSourceManager.selectNextSource()
            return
        }

        let allIds = inputSourceManager.enabledSourceIds()
        guard allIds.count >= 2 else {
            inputSourceManager.selectNextSource()
            return
        }

        let fromId: String
        let toId: String

        if let detected = inputSourceManager.detectTextLayout(
            for: selectedText, candidateIds: allIds
        ) {
            fromId = detected.fromId
            toId = (detected.fromId == currentId)
                ? detected.toId
                : currentId
        } else {
            fromId = currentId
            toId = inputSourceManager.otherSourceId(excluding: currentId) ?? allIds.first { $0 != currentId }!
        }

        guard let converted = inputSourceManager.convertText(
            selectedText, fromSourceId: fromId, toSourceId: toId
        ) else {
            inputSourceManager.selectNextSource()
            return
        }

        if !usedClipboard && accessibilityReader.setSelectedText(converted) {
            if toId != currentId {
                inputSourceManager.selectSource(toId)
            }
        } else {
            pasteboard.clearContents()
            pasteboard.setString(converted, forType: .string)
            textReplacer.sendPaste()

            if toId != currentId {
                inputSourceManager.selectSource(toId)
            }

            if usedClipboard {
                scheduleRestore(savedClipboard, afterCharCount: converted.count)
            }
        }
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        // Login item state can change outside the app (System Settings, approval flow)
        launchAtLoginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    private func pollPasteboard(
        savedChangeCount: Int,
        attempt: Int = 0,
        completion: @escaping (String?) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pasteboardPollInterval) { [self] in
            if pasteboard.changeCount != savedChangeCount {
                completion(pasteboard.string(forType: .string))
                return
            }
            if attempt + 1 < Timing.pasteboardPollMaxAttempts {
                self.pollPasteboard(
                    savedChangeCount: savedChangeCount,
                    attempt: attempt + 1,
                    completion: completion
                )
            } else {
                completion(nil)
            }
        }
    }
}
