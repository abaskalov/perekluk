import Carbon
import AppKit

final class InputSourceManager {

    func getEnabledKeyboardSources() -> [TISInputSource] {
        let properties: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true as Any,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(properties, false)?.takeRetainedValue() else {
            return []
        }
        return sourceList as! [TISInputSource]
    }

    func getCurrentSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    func sourceId(for source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    func getOtherSource() -> TISInputSource? {
        guard let current = getCurrentSource(),
              let currentId = sourceId(for: current) else {
            return nil
        }

        let sources = getEnabledKeyboardSources()
        return sources.first { source in
            sourceId(for: source) != currentId
        }
    }

    func select(_ source: TISInputSource) {
        TISSelectInputSource(source)
    }

    func selectNextSource() {
        if let other = getOtherSource() {
            select(other)
        }
    }

    // MARK: - Key Translation

    func getLayoutData(for source: TISInputSource) -> UnsafePointer<UCKeyboardLayout>? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(ptr, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    }

    func convertText(_ text: String, fromSource: TISInputSource, toSource: TISInputSource) -> String? {
        guard let fromLayout = getLayoutData(for: fromSource),
              let toLayout = getLayoutData(for: toSource) else { return nil }

        var charMap: [String: (keyCode: UInt16, shift: Bool)] = [:]
        for kc: UInt16 in 0...50 {
            if let ch = translateKeyCode(kc, shift: false, capsLock: false, layoutData: fromLayout) {
                charMap[ch] = (kc, false)
            }
            if let ch = translateKeyCode(kc, shift: true, capsLock: false, layoutData: fromLayout) {
                charMap[ch] = (kc, true)
            }
        }

        var result = ""
        for char in text {
            let s = String(char)
            if let mapping = charMap[s],
               let converted = translateKeyCode(mapping.keyCode, shift: mapping.shift, capsLock: false, layoutData: toLayout) {
                result += converted
            } else {
                result += s
            }
        }
        return result.isEmpty ? nil : result
    }

    func translateKeyCode(
        _ keyCode: UInt16,
        shift: Bool,
        capsLock: Bool,
        layoutData: UnsafePointer<UCKeyboardLayout>
    ) -> String? {
        var modifierState: UInt32 = 0
        if shift {
            modifierState |= UInt32(shiftKey >> 8) & 0xFF
        }
        if capsLock {
            modifierState |= UInt32(alphaLock >> 8) & 0xFF
        }

        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var actualLength = 0
        var chars = [UniChar](repeating: 0, count: maxLength)

        let status = UCKeyTranslate(
            layoutData,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierState,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &chars
        )

        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: actualLength)
    }
}
