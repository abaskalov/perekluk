import CoreGraphics

final class TextReplacer {
    static let markerUserData: Int64 = 0x50_45_52_4B

    private let eventSource: CGEventSource?

    init() {
        eventSource = CGEventSource(stateID: .privateState)
        eventSource?.userData = Self.markerUserData
    }

    func replaceText(deleteCount: Int, newText: String, then: (() -> Void)? = nil) {
        for _ in 0..<deleteCount {
            postKey(code: 51, keyDown: true)  // 51 = Backspace
            postKey(code: 51, keyDown: false)
        }

        // Let the target app process backspaces before typing replacement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
            for char in newText {
                postCharacter(char)
            }
            then?()
        }
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

    private func postCharacter(_ char: Character) {
        var utf16 = Array(String(char).utf16)
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else {
            return
        }
        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyDown.post(tap: .cghidEventTap)

        guard let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
            return
        }
        keyUp.post(tap: .cghidEventTap)
    }
}
