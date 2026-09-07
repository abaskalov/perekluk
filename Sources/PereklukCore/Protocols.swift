import AppKit

// MARK: - PasteboardProviding

/// Abstracts NSPasteboard for dependency injection and testing.
public protocol PasteboardProviding: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult func clearContents() -> Int
    @discardableResult func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    @discardableResult func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PasteboardProviding {}

// MARK: - TextReplacing

/// Abstracts simulated keyboard events (backspace, copy, paste) for testability.
public protocol TextReplacing {
    func deleteChars(count: Int)
    func sendCopy()
    func sendPaste()
}

// MARK: - InputSourceManaging

/// Abstracts InputSourceManager using String source IDs for testability.
/// Hides TISInputSource and UCKeyboardLayout details behind high-level operations.
public protocol InputSourceManaging {
    /// Returns the ID of the currently active keyboard source.
    func currentSourceId() -> String?

    /// Returns the primary BCP-47 language code of the active source (e.g. "ru", "en").
    func currentSourceLanguage() -> String?

    /// Returns IDs of all enabled keyboard input sources.
    func enabledSourceIds() -> [String]

    /// Selects a keyboard source by its string ID.
    func selectSource(_ id: String)

    /// Selects any source that is not the current one (cycle).
    func selectNextSource()

    /// Returns the ID of a source other than the excluded one, or nil.
    func otherSourceId(excluding currentId: String) -> String?

    /// Converts keystrokes to text using the target layout.
    /// Falls back to the source layout for characters unmappable in the target.
    func convertKeyStrokes(_ keystrokes: [KeyStroke], fromSourceId: String, toSourceId: String) -> String?

    /// Converts a text string from one layout to another.
    func convertText(_ text: String, fromSourceId: String, toSourceId: String) -> String?

    /// Detects which of the candidate layouts the text was typed in.
    /// Returns (fromId = highest scoring, toId = second highest) or nil if ambiguous.
    func detectTextLayout(for text: String, candidateIds: [String]) -> (fromId: String, toId: String)?
}
