import Foundation

public enum VKey: UInt16 {
    case a = 0
    case s = 1
    case d = 2
    case f = 3
    case h = 4
    case g = 5
    case z = 6
    case x = 7
    case c = 8
    case v = 9
    case b = 11
    case q = 12
    case w = 13
    case e = 14
    case r = 15
    case y = 16
    case t = 17
    case one = 18
    case two = 19
    case three = 20
    case four = 21
    case six = 22
    case five = 23
    case equal = 24
    case nine = 25
    case seven = 26
    case minus = 27
    case eight = 28
    case zero = 29
    case rightBracket = 30
    case o = 31
    case u = 32
    case leftBracket = 33
    case i = 34
    case p = 35
    case `return` = 36
    case l = 37
    case j = 38
    case quote = 39
    case k = 40
    case semicolon = 41
    case backslash = 42
    case comma = 43
    case slash = 44
    case n = 45
    case m = 46
    case period = 47
    case tab = 48
    case space = 49
    case grave = 50
    case delete = 51
    case escape = 53
    case enterNumpad = 76

    public static let maxPrintableRawValue: UInt16 = 50
}

// MARK: - Trigger Key

public enum TriggerKey: String, CaseIterable {
    case bothOptions = "bothOptions"
    case leftOption = "leftOption"
    case rightOption = "rightOption"
    case fn = "fn"
    case capsLock = "capsLock"

    public var displayName: String {
        switch self {
        case .bothOptions:  return "Both Options ⌥"
        case .leftOption:   return "Left Option ⌥"
        case .rightOption:  return "Right Option ⌥"
        case .fn:           return "fn 🌐"
        case .capsLock:     return "Caps Lock ⇪"
        }
    }

    // Device-level modifier masks (IOKit/IOLLEvent.h)
    static let deviceLAltMask: UInt64 = 0x00000020
    static let deviceRAltMask: UInt64 = 0x00000040
}

// MARK: - Settings

public enum Settings {
    private static let triggerKeyKey = "triggerKey"

    public static var triggerKey: TriggerKey {
        get {
            guard let raw = UserDefaults.standard.string(forKey: triggerKeyKey),
                  let key = TriggerKey(rawValue: raw) else { return .bothOptions }
            return key
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: triggerKeyKey)
        }
    }
}

// MARK: - System Keyboard Settings

public enum SystemKeyboardSettings {
    private static let hiToolboxDomain = "com.apple.HIToolbox"
    private static let fnUsageKey = "AppleFnUsageType"

    /// "Press 🌐 key to" in System Settings > Keyboard. An absent value is the macOS
    /// default, which switches the input source or opens the emoji picker on a lone press.
    public static var globeKeyDoesNothing: Bool {
        UserDefaults(suiteName: hiToolboxDomain)?.object(forKey: fnUsageKey) as? Int == 0
    }

    public static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}

// MARK: - Timing

public enum Timing {
    public static let deleteBase: TimeInterval = 0.03
    public static let deletePerChar: TimeInterval = 0.003
    public static let clipboardRestoreBase: TimeInterval = 0.2
    public static let clipboardRestorePerChar: TimeInterval = 0.005
    public static let pasteboardPollInterval: TimeInterval = 0.02
    public static let pasteboardPollMaxAttempts = 10
    public static let accessibilityCheckInterval: TimeInterval = 1.0
    public static let uninstallCheckInterval: TimeInterval = 5.0

    public static func deleteDelay(charCount: Int) -> TimeInterval {
        deleteBase + deletePerChar * TimeInterval(max(0, charCount - 1))
    }

    public static func clipboardRestoreDelay(charCount: Int) -> TimeInterval {
        clipboardRestoreBase + clipboardRestorePerChar * TimeInterval(max(0, charCount - 1))
    }
}
