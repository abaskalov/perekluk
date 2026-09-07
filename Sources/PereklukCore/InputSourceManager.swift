import Carbon
import AppKit

public final class InputSourceManager: InputSourceManaging {

    // Retains the CFData itself: TISGetInputSourceProperty returns memory owned by the
    // input source, and a cached raw pointer would dangle once the source is released
    private var layoutCache: [String: CFData] = [:]

    public init() {}

    public func invalidateCache() {
        layoutCache.removeAll()
    }

    public func getEnabledKeyboardSources() -> [TISInputSource] {
        let properties: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true as Any,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(properties, false)?.takeRetainedValue() else {
            return []
        }
        return sourceList as! [TISInputSource]
    }

    public func getCurrentSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    public func sourceId(for source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    public func getOtherSource() -> TISInputSource? {
        guard let current = getCurrentSource(),
              let currentId = sourceId(for: current) else {
            return nil
        }

        let sources = getEnabledKeyboardSources()
        return sources.first { source in
            sourceId(for: source) != currentId
        }
    }

    public func select(_ source: TISInputSource) {
        TISSelectInputSource(source)
    }

    public func selectNextSource() {
        if let other = getOtherSource() {
            select(other)
        }
    }

    // MARK: - Text Language Detection

    /// Determines which of the two enabled layouts the text was typed in
    /// by comparing characters against each layout's unique character set.
    /// Returns `(from: sourceLayout, to: targetLayout)` or `nil` if ambiguous.
    public func detectTextLayout(
        for text: String,
        sourceA: TISInputSource,
        sourceB: TISInputSource
    ) -> (from: TISInputSource, to: TISInputSource)? {
        guard let layoutA = getLayoutData(for: sourceA),
              let layoutB = getLayoutData(for: sourceB) else { return nil }

        var charsA = Set<String>()
        var charsB = Set<String>()
        for kc: UInt16 in 0...50 {
            for shift in [false, true] {
                if let ch = translateKeyCode(kc, shift: shift, capsLock: false, layoutData: layoutA) {
                    charsA.insert(ch)
                }
                if let ch = translateKeyCode(kc, shift: shift, capsLock: false, layoutData: layoutB) {
                    charsB.insert(ch)
                }
            }
        }

        let uniqueA = charsA.subtracting(charsB)
        let uniqueB = charsB.subtracting(charsA)

        var scoreA = 0
        var scoreB = 0
        for char in text {
            let s = String(char)
            if uniqueA.contains(s) { scoreA += 1 }
            if uniqueB.contains(s) { scoreB += 1 }
        }

        if scoreA > scoreB { return (from: sourceA, to: sourceB) }
        if scoreB > scoreA { return (from: sourceB, to: sourceA) }
        return nil
    }

    // MARK: - Key Translation

    public func getLayoutData(for source: TISInputSource) -> UnsafePointer<UCKeyboardLayout>? {
        let data: CFData
        if let id = sourceId(for: source), let cached = layoutCache[id] {
            data = cached
        } else {
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return nil
            }
            data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
            if let id = sourceId(for: source) {
                layoutCache[id] = data
            }
        }

        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    }

    public func convertText(_ text: String, fromSource: TISInputSource, toSource: TISInputSource) -> String? {
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

    public func translateKeyCode(
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

    // MARK: - Dead Key Sequence Translation

    /// Translates a keystroke sequence through a layout with full dead key state.
    /// Dead key combos (e.g. ^ + e → ê) produce composed characters.
    /// Trailing dead key state is flushed via Space (OBS/OpenJDK pattern).
    public func translateKeySequence(
        _ keystrokes: [KeyStroke],
        layoutData: UnsafePointer<UCKeyboardLayout>
    ) -> String {
        var deadKeyState: UInt32 = 0
        var result = ""
        let kbType = UInt32(LMGetKbdType())

        for stroke in keystrokes {
            var modifierState: UInt32 = 0
            if stroke.shift { modifierState |= UInt32(shiftKey >> 8) & 0xFF }
            if stroke.capsLock { modifierState |= UInt32(alphaLock >> 8) & 0xFF }

            let maxLength = 4
            var actualLength = 0
            var chars = [UniChar](repeating: 0, count: maxLength)

            let status = UCKeyTranslate(
                layoutData,
                stroke.keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                kbType,
                0,
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )

            if status == noErr && actualLength > 0 {
                result += String(utf16CodeUnits: chars, count: actualLength)
            }
        }

        if deadKeyState != 0 {
            let maxLength = 4
            var actualLength = 0
            var chars = [UniChar](repeating: 0, count: maxLength)

            UCKeyTranslate(
                layoutData,
                VKey.space.rawValue,
                UInt16(kUCKeyActionDown),
                0,
                kbType,
                0,
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )

            if actualLength > 0 {
                result += String(utf16CodeUnits: chars, count: actualLength)
            }
        }

        return result
    }

    // MARK: - InputSourceManaging Protocol

    public func currentSourceId() -> String? {
        guard let source = getCurrentSource() else { return nil }
        return sourceId(for: source)
    }

    public func currentSourceLanguage() -> String? {
        guard let source = getCurrentSource(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let languages = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]
        return languages?.first
    }

    public func enabledSourceIds() -> [String] {
        getEnabledKeyboardSources().compactMap { sourceId(for: $0) }
    }

    public func selectSource(_ id: String) {
        guard let source = findSource(byId: id) else { return }
        select(source)
    }

    public func otherSourceId(excluding currentId: String) -> String? {
        let ids = enabledSourceIds().sorted()
        guard let idx = ids.firstIndex(of: currentId) else {
            return ids.first { $0 != currentId }
        }
        let nextIdx = (idx + 1) % ids.count
        return ids[nextIdx] == currentId ? nil : ids[nextIdx]
    }

    public func convertKeyStrokes(
        _ keystrokes: [KeyStroke],
        fromSourceId: String,
        toSourceId: String
    ) -> String? {
        guard let toSource = findSource(byId: toSourceId),
              let toLayout = getLayoutData(for: toSource) else { return nil }

        let result = translateKeySequence(keystrokes, layoutData: toLayout)
        return result.isEmpty ? nil : result
    }

    public func convertText(_ text: String, fromSourceId: String, toSourceId: String) -> String? {
        guard let fromSource = findSource(byId: fromSourceId),
              let toSource = findSource(byId: toSourceId) else { return nil }
        return convertText(text, fromSource: fromSource, toSource: toSource)
    }

    public func detectTextLayout(
        for text: String,
        candidateIds: [String]
    ) -> (fromId: String, toId: String)? {
        let scores = scoreSourcesForText(text, candidateIds: candidateIds)
        guard scores.count >= 2 else { return nil }
        if scores[0].score == scores[1].score { return nil }
        if scores[0].score == 0 { return nil }
        return (fromId: scores[0].id, toId: scores[1].id)
    }

    public func scoreSourcesForText(
        _ text: String,
        candidateIds: [String]
    ) -> [(id: String, score: Int)] {
        var charSets: [String: Set<String>] = [:]
        for id in candidateIds {
            guard let source = findSource(byId: id),
                  let layout = getLayoutData(for: source) else { continue }
            var chars = Set<String>()
            for kc: UInt16 in 0...VKey.maxPrintableRawValue {
                for shift in [false, true] {
                    if let ch = translateKeyCode(kc, shift: shift, capsLock: false, layoutData: layout) {
                        chars.insert(ch)
                    }
                }
            }
            charSets[id] = chars
        }

        var uniqueChars: [String: Set<String>] = [:]
        for id in candidateIds {
            guard let chars = charSets[id] else { continue }
            let othersChars = candidateIds
                .filter { $0 != id }
                .reduce(Set<String>()) { $0.union(charSets[$1] ?? []) }
            uniqueChars[id] = chars.subtracting(othersChars)
        }

        var scores: [(id: String, score: Int)] = []
        for id in candidateIds {
            let unique = uniqueChars[id] ?? []
            var score = 0
            for char in text {
                if unique.contains(String(char)) { score += 1 }
            }
            scores.append((id: id, score: score))
        }

        return scores.sorted { $0.score > $1.score }
    }

    private func findSource(byId id: String) -> TISInputSource? {
        getEnabledKeyboardSources().first { sourceId(for: $0) == id }
    }
}
