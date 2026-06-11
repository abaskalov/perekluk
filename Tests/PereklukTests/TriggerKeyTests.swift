import XCTest
import CoreGraphics
@testable import PereklukCore

final class TriggerKeyTests: XCTestCase {

    private var monitor: KeyboardMonitor!

    override func setUp() {
        super.setUp()
        monitor = KeyboardMonitor()
    }

    // MARK: - TriggerKey enum

    func testDefaultTriggerKeyIsBothOptions() {
        XCTAssertEqual(monitor.triggerKey, .bothOptions)
    }

    func testAllCasesHasExpectedCount() {
        XCTAssertEqual(TriggerKey.allCases.count, 5)
    }

    func testDisplayNamesAreNonEmpty() {
        for key in TriggerKey.allCases {
            XCTAssertFalse(key.displayName.isEmpty)
        }
    }

    func testRawValueRoundTrip() {
        for key in TriggerKey.allCases {
            XCTAssertEqual(TriggerKey(rawValue: key.rawValue), key)
        }
    }

    // MARK: - Both Options (default, backward compat)

    func testBothOptions_LeftOptionTriggers() {
        monitor.triggerKey = .bothOptions
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertTrue(triggered)
    }

    func testBothOptions_OptionPlusKeyDoesNotTrigger() {
        monitor.triggerKey = .bothOptions
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleKeyDown(VKey.a.rawValue, flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    // MARK: - Left Option only

    func testLeftOption_LeftOptionTriggers() {
        monitor.triggerKey = .leftOption
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        let leftOptionFlags = CGEventFlags(rawValue: TriggerKey.deviceLAltMask | CGEventFlags.maskAlternate.rawValue)
        monitor.handleFlagsChanged(flags: leftOptionFlags)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertTrue(triggered)
    }

    func testLeftOption_RightOptionDoesNotTrigger() {
        monitor.triggerKey = .leftOption
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        let rightOptionFlags = CGEventFlags(rawValue: TriggerKey.deviceRAltMask | CGEventFlags.maskAlternate.rawValue)
        monitor.handleFlagsChanged(flags: rightOptionFlags)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    // MARK: - Right Option only

    func testRightOption_RightOptionTriggers() {
        monitor.triggerKey = .rightOption
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        let rightOptionFlags = CGEventFlags(rawValue: TriggerKey.deviceRAltMask | CGEventFlags.maskAlternate.rawValue)
        monitor.handleFlagsChanged(flags: rightOptionFlags)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertTrue(triggered)
    }

    func testRightOption_LeftOptionDoesNotTrigger() {
        monitor.triggerKey = .rightOption
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        let leftOptionFlags = CGEventFlags(rawValue: TriggerKey.deviceLAltMask | CGEventFlags.maskAlternate.rawValue)
        monitor.handleFlagsChanged(flags: leftOptionFlags)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    // MARK: - fn

    func testFn_FnTriggers() {
        monitor.triggerKey = .fn
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskSecondaryFn)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertTrue(triggered)
    }

    func testFn_FnPlusKeyDoesNotTrigger() {
        monitor.triggerKey = .fn
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskSecondaryFn)
        monitor.handleKeyDown(VKey.a.rawValue, flags: .maskSecondaryFn)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    func testFn_OptionDoesNotTrigger() {
        monitor.triggerKey = .fn
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    func testFn_ReturnsFalse_NoSuppression() {
        monitor.triggerKey = .fn
        monitor.onSwitchTriggered = { _, _ in }

        let suppress = monitor.handleFlagsChanged(flags: .maskSecondaryFn)
        XCTAssertFalse(suppress)
    }

    // MARK: - Caps Lock

    func testCapsLock_ToggleOnTriggers() {
        monitor.triggerKey = .capsLock
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlphaShift)

        XCTAssertTrue(triggered)
    }

    func testCapsLock_ToggleOffTriggers() {
        monitor.triggerKey = .capsLock
        var triggerCount = 0
        monitor.onSwitchTriggered = { _, _ in triggerCount += 1 }

        monitor.handleFlagsChanged(flags: .maskAlphaShift) // ON
        monitor.handleFlagsChanged(flags: [])              // OFF

        XCTAssertEqual(triggerCount, 2)
    }

    func testCapsLock_SameStateDoesNotTrigger() {
        monitor.triggerKey = .capsLock
        var triggerCount = 0
        monitor.onSwitchTriggered = { _, _ in triggerCount += 1 }

        monitor.handleFlagsChanged(flags: .maskAlphaShift) // ON → triggers
        monitor.handleFlagsChanged(flags: .maskAlphaShift) // same state → no trigger

        XCTAssertEqual(triggerCount, 1)
    }

    func testCapsLock_ReturnsTrue_ForSuppression() {
        monitor.triggerKey = .capsLock
        monitor.onSwitchTriggered = { _, _ in }

        let suppress = monitor.handleFlagsChanged(flags: .maskAlphaShift)
        XCTAssertTrue(suppress)
    }

    func testCapsLock_OptionDoesNotTrigger() {
        monitor.triggerKey = .capsLock
        var triggered = false
        monitor.onSwitchTriggered = { _, _ in triggered = true }

        monitor.handleFlagsChanged(flags: .maskAlternate)
        monitor.handleFlagsChanged(flags: [])

        XCTAssertFalse(triggered)
    }

    // MARK: - Modifier triggers return false (no suppression)

    func testModifierTrigger_ReturnsFalse() {
        monitor.triggerKey = .bothOptions
        monitor.onSwitchTriggered = { _, _ in }

        let suppress = monitor.handleFlagsChanged(flags: .maskAlternate)
        XCTAssertFalse(suppress)
    }

    // MARK: - Trigger key change resets state

    func testChangingTriggerKeyResetsState() {
        monitor.triggerKey = .bothOptions
        monitor.handleFlagsChanged(flags: .maskAlternate) // triggerDown = true

        XCTAssertTrue(monitor.triggerDown)

        monitor.triggerKey = .rightOption // should reset
        XCTAssertFalse(monitor.triggerDown)
        XCTAssertFalse(monitor.triggerAlone)
    }

    // MARK: - Caps Lock trigger with buffer

    func testCapsLock_TriggersWithBufferedWord() {
        monitor.triggerKey = .capsLock
        var receivedWord: [KeyStroke] = []
        monitor.onSwitchTriggered = { word, _ in receivedWord = word }

        monitor.handleKeyDown(VKey.h.rawValue, flags: [])
        monitor.handleKeyDown(VKey.i.rawValue, flags: [])
        monitor.handleFlagsChanged(flags: .maskAlphaShift)

        XCTAssertEqual(receivedWord.count, 2)
    }

    // MARK: - Settings persistence

    func testSettingsDefaultIsBothOptions() {
        UserDefaults.standard.removeObject(forKey: "triggerKey")
        XCTAssertEqual(Settings.triggerKey, .bothOptions)
    }

    func testSettingsRoundTrip() {
        let original = Settings.triggerKey
        defer { Settings.triggerKey = original }

        Settings.triggerKey = .capsLock
        XCTAssertEqual(Settings.triggerKey, .capsLock)

        Settings.triggerKey = .leftOption
        XCTAssertEqual(Settings.triggerKey, .leftOption)
    }
}
