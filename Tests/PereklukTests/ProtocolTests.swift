import XCTest
import Carbon
@testable import PereklukCore

final class ProtocolTests: XCTestCase {

    // MARK: - InputSourceManager conforms to InputSourceManaging

    func testCurrentSourceIdMatchesDirectApi() {
        let manager = InputSourceManager()
        let directId: String? = {
            guard let source = manager.getCurrentSource() else { return nil }
            return manager.sourceId(for: source)
        }()
        XCTAssertEqual(manager.currentSourceId(), directId)
    }

    func testEnabledSourceIdsMatchesDirectApi() {
        let manager = InputSourceManager()
        let directIds = manager.getEnabledKeyboardSources().compactMap { manager.sourceId(for: $0) }
        XCTAssertEqual(manager.enabledSourceIds(), directIds)
    }

    func testOtherSourceIdExcludesCurrent() {
        let manager = InputSourceManager()
        guard let currentId = manager.currentSourceId() else { return }
        if let otherId = manager.otherSourceId(excluding: currentId) {
            XCTAssertNotEqual(otherId, currentId)
        }
    }

    func testConvertKeyStrokesProducesResult() {
        let manager = InputSourceManager()
        let ids = manager.enabledSourceIds()
        guard ids.count >= 2 else { return }

        let keystrokes = [VKey.h, .e, .l, .l, .o].map {
            KeyStroke(keyCode: $0.rawValue, shift: false, capsLock: false)
        }

        let result = manager.convertKeyStrokes(keystrokes, fromSourceId: ids[0], toSourceId: ids[1])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 5)
    }

    func testConvertKeyStrokesMatchesManualLoop() {
        let manager = InputSourceManager()
        let sources = manager.getEnabledKeyboardSources()
        guard sources.count >= 2,
              let fromId = manager.sourceId(for: sources[0]),
              let toId = manager.sourceId(for: sources[1]),
              let toLayout = manager.getLayoutData(for: sources[1]) else { return }

        let fromLayout = manager.getLayoutData(for: sources[0])

        let keystrokes = [VKey.h, .e, .l, .l, .o].map {
            KeyStroke(keyCode: $0.rawValue, shift: false, capsLock: false)
        }

        var manualResult = ""
        for stroke in keystrokes {
            if let char = manager.translateKeyCode(stroke.keyCode, shift: stroke.shift, capsLock: stroke.capsLock, layoutData: toLayout) {
                manualResult += char
            } else if let fromLayout,
                      let original = manager.translateKeyCode(stroke.keyCode, shift: stroke.shift, capsLock: stroke.capsLock, layoutData: fromLayout) {
                manualResult += original
            }
        }

        let protocolResult = manager.convertKeyStrokes(keystrokes, fromSourceId: fromId, toSourceId: toId)
        XCTAssertEqual(protocolResult, manualResult)
    }

    func testConvertTextViaProtocolMatchesDirect() {
        let manager = InputSourceManager()
        let sources = manager.getEnabledKeyboardSources()
        guard sources.count >= 2,
              let idA = manager.sourceId(for: sources[0]),
              let idB = manager.sourceId(for: sources[1]) else { return }

        let direct = manager.convertText("hello", fromSource: sources[0], toSource: sources[1])
        let viaProtocol = manager.convertText("hello", fromSourceId: idA, toSourceId: idB)
        XCTAssertEqual(viaProtocol, direct)
    }

    func testDetectTextLayoutViaProtocol() {
        let manager = InputSourceManager()
        let sources = manager.getEnabledKeyboardSources()
        guard sources.count >= 2,
              let idA = manager.sourceId(for: sources[0]),
              let idB = manager.sourceId(for: sources[1]),
              let layoutA = manager.getLayoutData(for: sources[0]),
              let layoutB = manager.getLayoutData(for: sources[1]) else { return }

        var charsA = Set<String>()
        for kc: UInt16 in 0...VKey.maxPrintableRawValue {
            if let ch = manager.translateKeyCode(kc, shift: false, capsLock: false, layoutData: layoutA) { charsA.insert(ch) }
        }
        var charsB = Set<String>()
        for kc: UInt16 in 0...VKey.maxPrintableRawValue {
            if let ch = manager.translateKeyCode(kc, shift: false, capsLock: false, layoutData: layoutB) { charsB.insert(ch) }
        }

        let uniqueA = charsA.subtracting(charsB)
        guard !uniqueA.isEmpty else { return }

        let testText = uniqueA.prefix(5).joined()
        let result = manager.detectTextLayout(for: testText, candidateIds: [idA, idB])
        XCTAssertNotNil(result)
        if let result {
            XCTAssertEqual(result.fromId, idA)
            XCTAssertEqual(result.toId, idB)
        }
    }

    // MARK: - Mock verification

    func testFakePasteboardStoresAndRetrieves() {
        let fake = FakePasteboard()
        XCTAssertEqual(fake.changeCount, 0)
        fake.setString("test", forType: .string)
        XCTAssertEqual(fake.changeCount, 1)
        XCTAssertEqual(fake.string(forType: .string), "test")
        fake.clearContents()
        XCTAssertNil(fake.string(forType: .string))
        XCTAssertEqual(fake.changeCount, 2)
    }

    func testMockTextReplacerTracksActions() {
        let mock = MockTextReplacer()
        mock.deleteChars(count: 5)
        mock.sendPaste()
        XCTAssertEqual(mock.deletedCharCount, 5)
        XCTAssertEqual(mock.pasteCount, 1)
    }

    func testMockInputSourceManagerDefaults() {
        let mock = MockInputSourceManager()
        XCTAssertEqual(mock.currentSourceId(), "com.apple.keylayout.US")
        XCTAssertEqual(mock.enabledSourceIds().count, 2)
        XCTAssertEqual(mock.otherSourceId(excluding: "com.apple.keylayout.US"), "com.apple.keylayout.Russian")
    }

    func testMockInputSourceManagerSelectUpdatesState() {
        let mock = MockInputSourceManager()
        mock.selectSource("com.apple.keylayout.Russian")
        XCTAssertEqual(mock.currentSourceId(), "com.apple.keylayout.Russian")
        XCTAssertEqual(mock.selectedSourceId, "com.apple.keylayout.Russian")
    }

    func testMockInputSourceManagerSelectNextCycles() {
        let mock = MockInputSourceManager()
        mock.selectNextSource()
        XCTAssertEqual(mock.currentSourceId(), "com.apple.keylayout.Russian")
        XCTAssertEqual(mock.selectNextSourceCallCount, 1)
    }

    func testMockInputSourceManagerConvertKeyStrokes() {
        let mock = MockInputSourceManager()
        mock.keyStrokeConversions["com.apple.keylayout.Russian"] = "ghbdtn"
        let keystrokes = [KeyStroke(keyCode: VKey.h.rawValue, shift: false, capsLock: false)]
        let result = mock.convertKeyStrokes(keystrokes, fromSourceId: "com.apple.keylayout.US", toSourceId: "com.apple.keylayout.Russian")
        XCTAssertEqual(result, "ghbdtn")
    }

    func testMockInputSourceManagerConvertText() {
        let mock = MockInputSourceManager()
        mock.textConversions["привет"] = "ghbdtn"
        let result = mock.convertText("привет", fromSourceId: "com.apple.keylayout.Russian", toSourceId: "com.apple.keylayout.US")
        XCTAssertEqual(result, "ghbdtn")
    }

    func testMockInputSourceManagerDetectLayout() {
        let mock = MockInputSourceManager()
        mock.layoutDetections["привет"] = (fromId: "com.apple.keylayout.Russian", toId: "com.apple.keylayout.US")
        let result = mock.detectTextLayout(for: "привет", candidateIds: ["com.apple.keylayout.Russian", "com.apple.keylayout.US"])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fromId, "com.apple.keylayout.Russian")
    }

    // MARK: - Multi-layout cycling

    func testOtherSourceIdCyclesDeterministically() {
        let mock = MockInputSourceManager()
        mock.sources = ["a.layout.A", "b.layout.B", "c.layout.C"]
        mock.currentId = "a.layout.A"

        let first = mock.otherSourceId(excluding: "a.layout.A")
        let second = mock.otherSourceId(excluding: "b.layout.B")
        let third = mock.otherSourceId(excluding: "c.layout.C")

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
        XCTAssertNotEqual(first, "a.layout.A")
        XCTAssertNotEqual(second, "b.layout.B")
        XCTAssertNotEqual(third, "c.layout.C")
    }

    func testOtherSourceIdReturnNilForSingleLayout() {
        let mock = MockInputSourceManager()
        mock.sources = ["only.one"]
        XCTAssertNil(mock.otherSourceId(excluding: "only.one"))
    }

    func testScoreSourcesForTextWithRealLayouts() {
        let manager = InputSourceManager()
        let sources = manager.getEnabledKeyboardSources()
        guard sources.count >= 2,
              let layoutA = manager.getLayoutData(for: sources[0]),
              let layoutB = manager.getLayoutData(for: sources[1]) else { return }

        let idA = manager.sourceId(for: sources[0])!
        let idB = manager.sourceId(for: sources[1])!

        var charsA = Set<String>()
        var charsB = Set<String>()
        for kc: UInt16 in 0...VKey.maxPrintableRawValue {
            if let ch = manager.translateKeyCode(kc, shift: false, capsLock: false, layoutData: layoutA) { charsA.insert(ch) }
            if let ch = manager.translateKeyCode(kc, shift: false, capsLock: false, layoutData: layoutB) { charsB.insert(ch) }
        }

        let uniqueA = charsA.subtracting(charsB)
        guard !uniqueA.isEmpty else { return }

        let testText = uniqueA.prefix(5).joined()
        let scores = manager.scoreSourcesForText(testText, candidateIds: [idA, idB])
        XCTAssertEqual(scores.count, 2)
        XCTAssertEqual(scores[0].id, idA, "Layout with unique chars should score highest")
        XCTAssertGreaterThan(scores[0].score, scores[1].score)
    }

    func testDetectTextLayoutReturnsNilForAmbiguousText() {
        let manager = InputSourceManager()
        let ids = manager.enabledSourceIds()
        guard ids.count >= 2 else { return }

        let result = manager.detectTextLayout(for: " ", candidateIds: ids)
        XCTAssertNil(result, "Space-only text should be ambiguous")
    }

    func testDetectTextLayoutNeedsAtLeastTwoCandidates() {
        let manager = InputSourceManager()
        let ids = manager.enabledSourceIds()
        guard let first = ids.first else { return }

        let result = manager.detectTextLayout(for: "test", candidateIds: [first])
        XCTAssertNil(result, "Single candidate should return nil")
    }
}
