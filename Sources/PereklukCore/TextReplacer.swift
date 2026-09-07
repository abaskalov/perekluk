import CoreGraphics

public final class TextReplacer: TextReplacing {
    public static let markerUserData: Int64 = 0x50_45_52_4B

    private let eventSource: CGEventSource?

    public init() {
        eventSource = CGEventSource(stateID: .privateState)
        eventSource?.userData = Self.markerUserData
    }

    public func deleteChars(count: Int) {
        for _ in 0..<count {
            postBackspace()
        }
    }

    private func postBackspace() {
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: VKey.delete.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: VKey.delete.rawValue, keyDown: false) else { return }
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

    public func sendPaste() {
        postKeyCombo(code: VKey.v.rawValue, command: true)
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
