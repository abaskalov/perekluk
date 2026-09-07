import XCTest
import CoreGraphics
@testable import PereklukCore

final class KeyboardMonitorTests: XCTestCase {
    private var monitor: KeyboardMonitor!

    override func setUp() {
        super.setUp()
        monitor = KeyboardMonitor()
    }

    // MARK: - Buffer: basic keystroke accumulation

    func testBufferAccumulatesKeystrokes() {
        typeKeys([VKey.h, .e, .l, .l, .o])
        XCTAssertEqual(monitor.buffer.count, 5)
        XCTAssertEqual(monitor.buffer.map(\.keyCode), [VKey.h, .e, .l, .l, .o].map(\.rawValue))
    }

    func testBufferCapturesShiftState() {
        monitor.handleKeyDown(VKey.a.rawValue, flags: .maskShift)
        XCTAssertTrue(monitor.buffer[0].shift)
        XCTAssertFalse(monitor.buffer[0].capsLock)
    }

    func testBufferCapturesCapsLockState() {
        monitor.handleKeyDown(VKey.a.rawValue, flags: .maskAlphaShift)
        XCTAssertFalse(monitor.buffer[0].shift)
        XCTAssertTrue(monitor.buffer[0].capsLock)
    }

    // MARK: - Buffer: clear on word boundaries

    func testReturnClearsBuffer() {
        typeKeys([VKey.a, .b, .c])
        monitor.handleKeyDown(VKey.return.rawValue, flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    func testTabClearsBuffer() {
        typeKeys([VKey.a, .b])
        monitor.handleKeyDown(VKey.tab.rawValue, flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    func testEscapeClearsBuffer() {
        typeKeys([VKey.a])
        monitor.handleKeyDown(VKey.escape.rawValue, flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    func testEnterNumpadClearsBuffer() {
        typeKeys([VKey.a])
        monitor.handleKeyDown(VKey.enterNumpad.rawValue, flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    // MARK: - Buffer: space does NOT clear, adds to buffer

    func testSpaceAddsToBuffer() {
        typeKeys([VKey.a, .b, .c])
        monitor.handleKeyDown(VKey.space.rawValue, flags: [])
        XCTAssertEqual(monitor.buffer.count, 4)
        XCTAssertEqual(monitor.buffer.last?.keyCode, VKey.space.rawValue)
    }

    // MARK: - Buffer: command/control clear

    func testCommandKeyClearsBuffer() {
        typeKeys([VKey.a, .b])
        monitor.handleKeyDown(VKey.c.rawValue, flags: .maskCommand)
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    func testControlKeyClearsBuffer() {
        typeKeys([VKey.a, .b])
        monitor.handleKeyDown(VKey.c.rawValue, flags: .maskControl)
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    // MARK: - Buffer: backspace

    func testBackspaceRemovesLastKeystroke() {
        typeKeys([VKey.a, .b, .c])
        monitor.handleKeyDown(VKey.delete.rawValue, flags: [])
        XCTAssertEqual(monitor.buffer.count, 2)
        XCTAssertEqual(monitor.buffer.map(\.keyCode), [VKey.a, .b].map(\.rawValue))
    }

    func testBackspaceOnEmptyBufferDoesNotCrash() {
        monitor.handleKeyDown(VKey.delete.rawValue, flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    // MARK: - Buffer: mouse click clears

    func testMouseDownClearsBuffer() {
        typeKeys([VKey.a, .b, .c])
        monitor.handleMouseDown()
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    // MARK: - Buffer: high keycodes clear buffer

    func testHighKeyCodeClearsBuffer() {
        typeKeys([VKey.a, .b])
        monitor.handleKeyDown(55, flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    // MARK: - Buffer: overflow protection

    func testBufferOverflowTrimsOldEntries() {
        for i: UInt16 in 0..<70 {
            monitor.handleKeyDown(i % VKey.maxPrintableRawValue, flags: [])
        }
        XCTAssertLessThanOrEqual(monitor.buffer.count, 64)
    }

    // MARK: - Buffer: trigger key suppresses buffering

    func testKeysWhileTriggerDownAreNotBuffered() {
        monitor.handleFlagsChanged(flags: .maskAlternate)
        XCTAssertTrue(monitor.triggerDown)
        monitor.handleKeyDown(VKey.a.rawValue, flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    func testTriggerDownSetsAloneToFalseOnKey() {
        monitor.handleFlagsChanged(flags: .maskAlternate)
        XCTAssertTrue(monitor.triggerAlone)
        monitor.handleKeyDown(VKey.a.rawValue, flags: [])
        XCTAssertFalse(monitor.triggerAlone)
    }

    // MARK: - Buffer stays in sync with the screen

    func testTypingWhileTriggerDownClearsBuffer() {
        // Option+8 types "•" on screen but is not buffered — stale buffer would desync deletes
        typeKeys([VKey.h, .e, .y])
        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleKeyDown(VKey.eight.rawValue, flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    func testOptionModifiedKeyClearsBuffer() {
        // With Caps Lock as trigger, Option-modified chars reach handleKeyDown unbuffered-able
        monitor.triggerKey = .capsLock
        typeKeys([VKey.h, .e, .y])
        monitor.handleKeyDown(VKey.eight.rawValue, flags: .maskAlternate)
        XCTAssertTrue(monitor.buffer.isEmpty)
    }

    // MARK: - Modifier chords do not fire the trigger

    func testShiftPressedWhileOptionDownDoesNotTrigger() {
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [.maskAlternate, .maskShift])
        monitor.handleFlagsChanged(flags: .maskShift)

        XCTAssertFalse(triggered)
    }

    func testOptionPressedDuringShiftChordDoesNotTrigger() {
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskShift)
        monitor.handleFlagsChanged(flags: [.maskAlternate, .maskShift])
        monitor.handleFlagsChanged(flags: .maskShift)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    func testMouseClickWhileOptionDownDoesNotTrigger() {
        // Option+click (open in new window, option-drag) is not a trigger tap
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleMouseDown()
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    func testTapDisabledClearsBufferAndTriggerState() {
        // While the tap was dead keystrokes reached the screen unbuffered — replaying
        // a stale backspace count would eat wrong text
        typeKeys([VKey.h, .e, .y])
        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleTapDisabled()
        XCTAssertTrue(monitor.buffer.isEmpty)
        XCTAssertFalse(monitor.triggerDown)
    }

    func testCapsLockFlagDoesNotCancelTriggerAlone() {
        // Caps Lock enabled while typing keeps maskAlphaShift set — must not break the trigger
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: [.maskAlternate, .maskAlphaShift])
        monitor.handleFlagsChanged(flags: .maskAlphaShift)

        XCTAssertTrue(triggered)
    }

    // MARK: - extractLastWord via handleFlagsChanged

    func testOptionTriggersCallbackWithWord() {
        var receivedWord: [KeyStroke] = []
        var receivedSpaces = -1
        monitor.onSwitchTriggered = { word, spaces in
            receivedWord = word
            receivedSpaces = spaces
        }

        typeKeys([VKey.h, .e, .l, .l, .o])
        simulateOptionPress()

        XCTAssertEqual(receivedWord.count, 5)
        XCTAssertEqual(receivedSpaces, 0)
    }

    func testWordPlusSpaceThenOption() {
        var receivedWord: [KeyStroke] = []
        var receivedSpaces = -1
        monitor.onSwitchTriggered = { word, spaces in
            receivedWord = word
            receivedSpaces = spaces
        }

        typeKeys([VKey.h, .e, .l, .l, .o, .space])
        simulateOptionPress()

        XCTAssertEqual(receivedWord.count, 5)
        XCTAssertEqual(receivedWord.map(\.keyCode), [VKey.h, .e, .l, .l, .o].map(\.rawValue))
        XCTAssertEqual(receivedSpaces, 1)
    }

    func testTwoWordsThenOption() {
        var receivedWord: [KeyStroke] = []
        var receivedSpaces = -1
        monitor.onSwitchTriggered = { word, spaces in
            receivedWord = word
            receivedSpaces = spaces
        }

        typeKeys([VKey.h, .i, .space, .b, .y, .e])
        simulateOptionPress()

        XCTAssertEqual(receivedWord.count, 3)
        XCTAssertEqual(receivedWord.map(\.keyCode), [VKey.b, .y, .e].map(\.rawValue))
        XCTAssertEqual(receivedSpaces, 0)
    }

    func testTwoWordsPlusSpaceThenOption() {
        var receivedWord: [KeyStroke] = []
        var receivedSpaces = -1
        monitor.onSwitchTriggered = { word, spaces in
            receivedWord = word
            receivedSpaces = spaces
        }

        typeKeys([VKey.h, .i, .space, .b, .y, .e, .space])
        simulateOptionPress()

        XCTAssertEqual(receivedWord.count, 3)
        XCTAssertEqual(receivedWord.map(\.keyCode), [VKey.b, .y, .e].map(\.rawValue))
        XCTAssertEqual(receivedSpaces, 1)
    }

    func testMultipleTrailingSpaces() {
        var receivedWord: [KeyStroke] = []
        var receivedSpaces = -1
        monitor.onSwitchTriggered = { word, spaces in
            receivedWord = word
            receivedSpaces = spaces
        }

        typeKeys([VKey.a, .b, .space, .space, .space])
        simulateOptionPress()

        XCTAssertEqual(receivedWord.count, 2)
        XCTAssertEqual(receivedSpaces, 3)
    }

    func testOnlySpacesThenOption() {
        var receivedWord: [KeyStroke] = []
        var receivedSpaces = -1
        monitor.onSwitchTriggered = { word, spaces in
            receivedWord = word
            receivedSpaces = spaces
        }

        typeKeys([VKey.space, .space])
        simulateOptionPress()

        XCTAssertTrue(receivedWord.isEmpty)
        XCTAssertEqual(receivedSpaces, 2)
    }

    func testEmptyBufferThenOption() {
        var receivedWord: [KeyStroke] = []
        var receivedSpaces = -1
        monitor.onSwitchTriggered = { word, spaces in
            receivedWord = word
            receivedSpaces = spaces
        }

        simulateOptionPress()

        XCTAssertTrue(receivedWord.isEmpty)
        XCTAssertEqual(receivedSpaces, 0)
    }

    // MARK: - Option key alone detection

    func testOptionPlusKeyDoesNotTrigger() {
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleKeyDown(VKey.a.rawValue, flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    func testOptionAloneTriggers() {
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertTrue(triggered)
    }

    func testDoubleOptionPressDoesNotDoubleBuffer() {
        var triggerCount = 0
        monitor.onSwitchTriggered = { _, _ in triggerCount += 1 }

        typeKeys([VKey.a, .b, .c])
        simulateOptionPress()
        simulateOptionPress()

        XCTAssertEqual(triggerCount, 2)
    }

    // MARK: - Helpers

    private func typeKeys(_ keys: [VKey]) {
        for key in keys {
            monitor.handleKeyDown(key.rawValue, flags: [])
        }
    }

    private func simulateOptionPress() {
        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])
    }
}
