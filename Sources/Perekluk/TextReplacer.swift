import CoreGraphics

final class TextReplacer {
    static let markerUserData: Int64 = 0x50_45_52_4B

    private let eventSource: CGEventSource?

    init() {
        eventSource = CGEventSource(stateID: .privateState)
        eventSource?.userData = Self.markerUserData
    }

    func deleteChars(count: Int) {
        for _ in 0..<count {
            postBackspace()
        }
    }

    private func postBackspace() {
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: false) else { return }
        // Explicit DEL character — terminals need the unicode string to know
        // what byte to send to the PTY (regular text fields use keyCode directly)
        var delChar: UniChar = 0x7F
        down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &delChar)
        // Strip modifier flags so terminals don't interpret this as Alt+Backspace
        let modifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
        down.flags = down.flags.subtracting(modifiers)
        up.flags = up.flags.subtracting(modifiers)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func sendCopy() {
        postKeyCombo(code: 8, command: true) // 8 = C
    }

    func sendPaste() {
        postKeyCombo(code: 9, command: true) // 9 = V
    }

    private func postKeyCombo(code: CGKeyCode, command: Bool) {
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: false) else { return }
        if command {
            down.flags = .maskCommand
            up.flags = .maskCommand
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postKey(code: CGKeyCode, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: keyDown) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
