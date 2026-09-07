import AppKit
@testable import PereklukCore

final class FakePasteboard: PasteboardProviding {
    private(set) var changeCount: Int = 0
    private var strings: [NSPasteboard.PasteboardType: String] = [:]

    var pasteboardItems: [NSPasteboardItem]? { nil }

    @discardableResult func clearContents() -> Int {
        strings.removeAll()
        changeCount += 1
        return changeCount
    }

    @discardableResult func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        strings[dataType] = string
        changeCount += 1
        return true
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        strings[dataType]
    }

    @discardableResult func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        changeCount += 1
        return true
    }
}

final class MockTextReplacer: TextReplacing {
    var deletedCharCount = 0
    var copyCount = 0
    var pasteCount = 0
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?

    func deleteChars(count: Int) { deletedCharCount += count }
    func sendCopy() { copyCount += 1; onCopy?() }
    func sendPaste() { pasteCount += 1; onPaste?() }
}

final class MockAccessibilityReader: AccessibilityReading {
    var selectedText: String?
    var setText: String?
    var setTextResult = false

    func getSelectedText() -> String? { selectedText }

    func setSelectedText(_ text: String) -> Bool {
        setText = text
        return setTextResult
    }
}

final class MockInputSourceManager: InputSourceManaging {
    var sources: [String] = ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
    var currentId: String? = "com.apple.keylayout.US"
    var selectedSourceId: String?
    var selectNextSourceCallCount = 0

    var keyStrokeConversions: [String: String] = [:]
    var textConversions: [String: String] = [:]
    var layoutDetections: [String: (fromId: String, toId: String)] = [:]
    var scoreResults: [(id: String, score: Int)] = []

    var currentLanguage: String? = "en"

    func currentSourceId() -> String? { currentId }
    func currentSourceLanguage() -> String? { currentLanguage }
    func enabledSourceIds() -> [String] { sources }

    func selectSource(_ id: String) {
        selectedSourceId = id
        currentId = id
    }

    func selectNextSource() {
        selectNextSourceCallCount += 1
        if let current = currentId, let other = otherSourceId(excluding: current) {
            currentId = other
        }
    }

    func otherSourceId(excluding currentId: String) -> String? {
        sources.first { $0 != currentId }
    }

    func convertKeyStrokes(_ keystrokes: [KeyStroke], fromSourceId: String, toSourceId: String) -> String? {
        keyStrokeConversions[toSourceId]
    }

    func convertText(_ text: String, fromSourceId: String, toSourceId: String) -> String? {
        textConversions[text]
    }

    func detectTextLayout(for text: String, candidateIds: [String]) -> (fromId: String, toId: String)? {
        layoutDetections[text]
    }
}
