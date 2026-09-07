import XCTest
import AppKit
import CoreGraphics
@testable import PereklukCore

// MARK: - Integration / E2E Tests

final class IntegrationTests: XCTestCase {

    private var delegate: AppDelegate!
    private var mockISM: MockInputSourceManager!
    private var mockReplacer: MockTextReplacer!
    private var fakePB: FakePasteboard!
    private var mockAX: MockAccessibilityReader!

    private let usLayout = "com.apple.keylayout.US"
    private let ruLayout = "com.apple.keylayout.Russian"

    override func setUp() {
        super.setUp()
        delegate = AppDelegate()
        mockISM = MockInputSourceManager()
        mockISM.sources = [usLayout, ruLayout]
        mockISM.currentId = usLayout

        mockReplacer = MockTextReplacer()
        fakePB = FakePasteboard()
        mockAX = MockAccessibilityReader()

        delegate.inputSourceManager = mockISM
        delegate.textReplacer = mockReplacer
        delegate.pasteboard = fakePB
        delegate.accessibilityReader = mockAX
    }

    override func tearDown() {
        delegate = nil
        mockISM = nil
        mockReplacer = nil
        fakePB = nil
        mockAX = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func dummyKeyStrokes(_ count: Int) -> [KeyStroke] {
        (0..<count).map { KeyStroke(keyCode: UInt16($0 % 50), shift: false, capsLock: false) }
    }

    private func waitForAsyncChain(timeout: TimeInterval = 2.0, verify: @escaping () -> Void) {
        let exp = expectation(description: "async chain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            verify()
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
    }

    private func wireFullPipeline() {
        delegate.keyboardMonitor.onSwitchTriggered = { [weak self] word, trailing in
            self?.delegate.handleSwitch(word, trailingSpaces: trailing)
        }
    }

    private func pressOptionAlone() {
        delegate.keyboardMonitor.handleFlagsChanged(flags: .maskAlternate)
        delegate.keyboardMonitor.handleFlagsChanged(flags: [])
    }

    private func typeKeyCodes(_ codes: [UInt16]) {
        for code in codes {
            delegate.keyboardMonitor.handleKeyDown(code, flags: [])
        }
    }

    // MARK: - Status Label

    func testStatusLabelDerivedFromLanguageNotSourceId() {
        // "Belarusian" contains "us" — substring matching on the source ID mislabeled it "En"
        XCTAssertEqual(AppDelegate.statusLabel(forLanguage: "ru"), "Ру")
        XCTAssertEqual(AppDelegate.statusLabel(forLanguage: "en"), "En")
        XCTAssertEqual(AppDelegate.statusLabel(forLanguage: "be"), "Be")
        XCTAssertEqual(AppDelegate.statusLabel(forLanguage: "uk"), "Uk")
        XCTAssertEqual(AppDelegate.statusLabel(forLanguage: "pt-BR"), "Pt")
    }

    // MARK: - Buffer Switch E2E

    func testBufferSwitch_ConvertsWordAndSwitchesLayout() {
        mockISM.keyStrokeConversions[ruLayout] = "привет"

        delegate.handleSwitch(dummyKeyStrokes(6), trailingSpaces: 0)

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 6)
            XCTAssertEqual(self.mockReplacer.pasteCount, 1)
            XCTAssertEqual(self.fakePB.string(forType: .string), "привет")
            XCTAssertEqual(self.mockISM.selectedSourceId, self.ruLayout)
        }
    }

    func testBufferSwitch_PreservesTrailingSpaces() {
        mockISM.keyStrokeConversions[ruLayout] = "слово"

        delegate.handleSwitch(dummyKeyStrokes(5), trailingSpaces: 2)

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 7) // 5 chars + 2 spaces
            XCTAssertEqual(self.fakePB.string(forType: .string), "слово  ")
            XCTAssertEqual(self.mockISM.selectedSourceId, self.ruLayout)
        }
    }

    func testBufferSwitch_NoConversion_DoesNothing() {
        delegate.handleSwitch(dummyKeyStrokes(3), trailingSpaces: 0)

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 0)
            XCTAssertEqual(self.mockReplacer.pasteCount, 0)
            XCTAssertNil(self.mockISM.selectedSourceId)
        }
    }

    func testBufferSwitch_DeadKeys_DeletesProducedCharCount() {
        // 2 keystrokes (dead ^ + e) produced a single "ê" on screen — delete 1 char, not 2
        mockISM.keyStrokeConversions[usLayout] = "ê"
        mockISM.keyStrokeConversions[ruLayout] = "хе"

        delegate.handleSwitch(dummyKeyStrokes(2), trailingSpaces: 0)

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 1)
            XCTAssertEqual(self.fakePB.string(forType: .string), "хе")
        }
    }

    func testSelectionSwitch_FileCopyInFinder_DoesNotPaste() {
        // Copy with a file selected puts file URLs on the pasteboard; pasting back would duplicate the file
        mockAX.selectedText = nil
        mockISM.textConversions["Report.pdf"] = "Кузщке.зва"
        mockAX.copyResult = true
        mockAX.onCopy = { [self] in
            fakePB.setString("Report.pdf", forType: .string)
            fakePB.setString("file:///Users/x/Report.pdf", forType: .fileURL)
        }

        delegate.handleSwitch([], trailingSpaces: 0)

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.pasteCount, 0)
            XCTAssertEqual(self.mockISM.selectNextSourceCallCount, 1)
        }
    }

    func testBufferSwitch_SingleLayout_DoesNothing() {
        mockISM.sources = [usLayout]

        delegate.handleSwitch(dummyKeyStrokes(6), trailingSpaces: 0)

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 0)
            XCTAssertEqual(self.mockReplacer.pasteCount, 0)
        }
    }

    // MARK: - Selection Switch E2E (AX Path)

    func testSelectionSwitch_AXPath_ConvertsViaAccessibility() {
        mockAX.selectedText = "ghbdtn"
        mockAX.setTextResult = true
        mockISM.layoutDetections["ghbdtn"] = (fromId: usLayout, toId: ruLayout)
        mockISM.textConversions["ghbdtn"] = "привет"

        delegate.handleSwitch([], trailingSpaces: 0)

        // AX path is synchronous
        XCTAssertEqual(mockAX.setText, "привет")
        XCTAssertEqual(mockReplacer.pasteCount, 0)
        XCTAssertEqual(mockAX.copyCount, 0)
        XCTAssertEqual(mockISM.selectedSourceId, ruLayout)
    }

    func testSelectionSwitch_AXReadSucceeds_AXWriteFails_FallsToClipboard() {
        mockAX.selectedText = "ghbdtn"
        mockAX.setTextResult = false
        mockISM.layoutDetections["ghbdtn"] = (fromId: usLayout, toId: ruLayout)
        mockISM.textConversions["ghbdtn"] = "привет"

        delegate.handleSwitch([], trailingSpaces: 0)

        XCTAssertEqual(mockReplacer.pasteCount, 1)
        XCTAssertEqual(fakePB.string(forType: .string), "привет")
        XCTAssertEqual(mockISM.selectedSourceId, ruLayout)
    }

    func testSelectionSwitch_AXPath_TextInOtherLayout_NoLayoutSwitchNeeded() {
        mockISM.currentId = ruLayout
        mockAX.selectedText = "ghbdtn"
        mockAX.setTextResult = true
        // fromId=US != currentId=RU → toId becomes currentId (RU)
        mockISM.layoutDetections["ghbdtn"] = (fromId: usLayout, toId: ruLayout)
        mockISM.textConversions["ghbdtn"] = "привет"

        delegate.handleSwitch([], trailingSpaces: 0)

        XCTAssertEqual(mockAX.setText, "привет")
        XCTAssertNil(mockISM.selectedSourceId) // toId == currentId → no switch
    }

    func testSelectionSwitch_NoSelection_JustSwitchesLayout() {
        mockAX.selectedText = nil

        delegate.handleSwitch([], trailingSpaces: 0)

        // AX nil → Copy menu item disabled → no clipboard round trip, straight to selectNextSource
        XCTAssertEqual(mockAX.copyCount, 1)
        XCTAssertEqual(mockISM.selectNextSourceCallCount, 1)
        XCTAssertEqual(mockReplacer.pasteCount, 0)
    }

    func testSelectionSwitch_AXReturnsEmpty_FallsToClipboard() {
        mockAX.selectedText = ""

        delegate.handleSwitch([], trailingSpaces: 0)

        XCTAssertEqual(mockAX.copyCount, 1)
        XCTAssertEqual(mockISM.selectNextSourceCallCount, 1)
    }

    func testSelectionSwitch_CopyEnabledButNothingCopied_JustSwitches() {
        mockAX.selectedText = nil
        mockAX.copyResult = true

        delegate.handleSwitch([], trailingSpaces: 0)

        // Copy item enabled but the app put nothing on the pasteboard → poll exhausts → selectNextSource
        waitForAsyncChain {
            XCTAssertEqual(self.mockISM.selectNextSourceCallCount, 1)
            XCTAssertEqual(self.mockReplacer.pasteCount, 0)
        }
    }

    // MARK: - Selection Switch E2E (Clipboard Path)

    func testSelectionSwitch_ClipboardPath_CopiesConvertsAndPastes() {
        mockAX.selectedText = nil
        mockISM.layoutDetections["ghbdtn"] = (fromId: usLayout, toId: ruLayout)
        mockISM.textConversions["ghbdtn"] = "привет"

        // Simulate the Copy menu action putting text on clipboard
        mockAX.copyResult = true
        mockAX.onCopy = { [self] in
            fakePB.clearContents()
            fakePB.setString("ghbdtn", forType: .string)
        }

        delegate.handleSwitch([], trailingSpaces: 0)

        waitForAsyncChain {
            XCTAssertEqual(self.mockAX.copyCount, 1)
            XCTAssertEqual(self.mockReplacer.pasteCount, 1)
            XCTAssertEqual(self.fakePB.string(forType: .string), "привет")
            XCTAssertEqual(self.mockISM.selectedSourceId, self.ruLayout)
        }
    }

    func testSelectionSwitch_ClipboardPath_NoConversion_JustSwitches() {
        mockAX.selectedText = nil

        mockAX.copyResult = true
        mockAX.onCopy = { [self] in
            fakePB.clearContents()
            fakePB.setString("12345", forType: .string)
        }

        delegate.handleSwitch([], trailingSpaces: 0)

        waitForAsyncChain {
            XCTAssertEqual(self.mockISM.selectNextSourceCallCount, 1)
            XCTAssertEqual(self.mockReplacer.pasteCount, 0)
        }
    }

    // MARK: - Multi-Layout Selection

    func testSelectionSwitch_ThreeLayouts_DetectsCorrectSource() {
        mockISM.sources = [usLayout, ruLayout, "com.apple.keylayout.German"]
        mockISM.currentId = usLayout
        mockAX.selectedText = "руский"
        mockAX.setTextResult = true
        mockISM.layoutDetections["руский"] = (fromId: ruLayout, toId: usLayout)
        mockISM.textConversions["руский"] = "hecrbq"

        delegate.handleSwitch([], trailingSpaces: 0)

        XCTAssertEqual(mockAX.setText, "hecrbq")
        XCTAssertNil(mockISM.selectedSourceId) // fromId != currentId → toId = currentId → no switch
    }

    // MARK: - Full Pipeline (KeyboardMonitor → AppDelegate → Mocks)

    func testFullPipeline_TypeWordThenOption() {
        mockISM.keyStrokeConversions[ruLayout] = "привет"
        wireFullPipeline()

        typeKeyCodes([5, 4, 11, 2, 17, 45]) // g h b d t n
        pressOptionAlone()

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 6)
            XCTAssertEqual(self.mockReplacer.pasteCount, 1)
            XCTAssertEqual(self.fakePB.string(forType: .string), "привет")
            XCTAssertEqual(self.mockISM.selectedSourceId, self.ruLayout)
        }
    }

    func testFullPipeline_TwoWords_OnlyLastWordConverted() {
        mockISM.keyStrokeConversions[ruLayout] = "ыдщцщ"
        wireFullPipeline()

        typeKeyCodes([4, 14, 37, 37, 31]) // h e l l o
        delegate.keyboardMonitor.handleKeyDown(VKey.space.rawValue, flags: [])
        typeKeyCodes([1, 37, 31, 9, 31]) // s l o v o
        pressOptionAlone()

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 5) // only "slovo"
            XCTAssertEqual(self.mockReplacer.pasteCount, 1)
        }
    }

    func testFullPipeline_WordWithTrailingSpace() {
        mockISM.keyStrokeConversions[ruLayout] = "слово"
        wireFullPipeline()

        typeKeyCodes([1, 37, 31, 9, 31]) // s l o v o
        delegate.keyboardMonitor.handleKeyDown(VKey.space.rawValue, flags: [])
        pressOptionAlone()

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 6) // 5 chars + 1 space
            XCTAssertEqual(self.fakePB.string(forType: .string), "слово ")
        }
    }

    func testFullPipeline_EmptyBuffer_TriggersSelectionSwitch() {
        mockAX.selectedText = nil
        wireFullPipeline()

        pressOptionAlone()

        waitForAsyncChain {
            XCTAssertEqual(self.mockISM.selectNextSourceCallCount, 1)
        }
    }

    func testFullPipeline_TypeThenBackspace() {
        mockISM.keyStrokeConversions[ruLayout] = "при"
        wireFullPipeline()

        typeKeyCodes([5, 4, 11, 2, 17, 45]) // 6 keys
        for _ in 0..<3 {
            delegate.keyboardMonitor.handleKeyDown(VKey.delete.rawValue, flags: [])
        }
        pressOptionAlone()

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 3)
            XCTAssertEqual(self.mockReplacer.pasteCount, 1)
        }
    }

    func testFullPipeline_OptionPlusKey_DoesNotTrigger() {
        var triggered = false
        delegate.keyboardMonitor.onSwitchTriggered = { _, _ in triggered = true }

        delegate.keyboardMonitor.handleKeyDown(0, flags: [])
        delegate.keyboardMonitor.handleFlagsChanged(flags: .maskAlternate)
        delegate.keyboardMonitor.handleKeyDown(1, flags: .maskAlternate)
        delegate.keyboardMonitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    func testFullPipeline_MouseClickClearsBuffer_ThenOption() {
        mockAX.selectedText = nil
        wireFullPipeline()

        typeKeyCodes([5, 4, 11])
        delegate.keyboardMonitor.handleMouseDown()
        pressOptionAlone()

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 0)
            XCTAssertEqual(self.mockISM.selectNextSourceCallCount, 1)
        }
    }

    // MARK: - Full Pipeline with Configurable Trigger Key

    func testFullPipeline_CapsLockTrigger_ConvertsWord() {
        mockISM.keyStrokeConversions[ruLayout] = "привет"
        delegate.keyboardMonitor.triggerKey = .capsLock
        wireFullPipeline()

        typeKeyCodes([5, 4, 11, 2, 17, 45]) // g h b d t n
        delegate.keyboardMonitor.handleFlagsChanged(flags: .maskAlphaShift)

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 6)
            XCTAssertEqual(self.mockReplacer.pasteCount, 1)
            XCTAssertEqual(self.fakePB.string(forType: .string), "привет")
        }
    }

    func testFullPipeline_RightOptionOnly_LeftOptionIgnored() {
        mockISM.keyStrokeConversions[ruLayout] = "привет"
        delegate.keyboardMonitor.triggerKey = .rightOption
        wireFullPipeline()

        typeKeyCodes([5, 4, 11, 2, 17, 45]) // g h b d t n

        // Left Option should NOT trigger
        let leftFlags = CGEventFlags(rawValue: TriggerKey.deviceLAltMask | CGEventFlags.maskAlternate.rawValue)
        delegate.keyboardMonitor.handleFlagsChanged(flags: leftFlags)
        delegate.keyboardMonitor.handleFlagsChanged(flags: [])

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 0)
            XCTAssertEqual(self.mockReplacer.pasteCount, 0)
        }
    }

    func testFullPipeline_RightOptionOnly_RightOptionWorks() {
        mockISM.keyStrokeConversions[ruLayout] = "привет"
        delegate.keyboardMonitor.triggerKey = .rightOption
        wireFullPipeline()

        typeKeyCodes([5, 4, 11, 2, 17, 45]) // g h b d t n

        let rightFlags = CGEventFlags(rawValue: TriggerKey.deviceRAltMask | CGEventFlags.maskAlternate.rawValue)
        delegate.keyboardMonitor.handleFlagsChanged(flags: rightFlags)
        delegate.keyboardMonitor.handleFlagsChanged(flags: [])

        waitForAsyncChain {
            XCTAssertEqual(self.mockReplacer.deletedCharCount, 6)
            XCTAssertEqual(self.mockReplacer.pasteCount, 1)
        }
    }

    func testFullPipeline_CapsLockTrigger_EmptyBuffer_SelectionSwitch() {
        delegate.keyboardMonitor.triggerKey = .capsLock
        mockAX.selectedText = nil
        wireFullPipeline()

        delegate.keyboardMonitor.handleFlagsChanged(flags: .maskAlphaShift)

        waitForAsyncChain {
            XCTAssertEqual(self.mockISM.selectNextSourceCallCount, 1)
        }
    }
}
