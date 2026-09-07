import AppKit

public protocol AccessibilityReading {
    func getSelectedText() -> String?
    func setSelectedText(_ text: String) -> Bool
    /// Performs the frontmost app's Copy menu item. False when the app has no enabled
    /// Copy item, which for an auto-validating menu means nothing is selected.
    func performCopy() -> Bool
}

public final class AccessibilityReader: AccessibilityReading {

    public init() {}

    public func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRaw
        ) == .success else { return nil }

        let focused = focusedRaw as! AXUIElement
        var textRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &textRaw
        ) == .success else { return nil }

        let text = textRaw as? String
        return (text?.isEmpty == true) ? nil : text
    }

    public func setSelectedText(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRaw
        ) == .success else { return false }

        let focused = focusedRaw as! AXUIElement
        let result = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    // MARK: - Copy via menu action

    /// Copy goes through the app's own menu item, never a synthetic Cmd+C: Ghostty hands
    /// an unconsumed Cmd+C to the shell, which typed a stray "c" on every empty-buffer trigger.
    public func performCopy() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, of: appElement),
              let copyItem = findCopyItem(inMenuBar: menuBar),
              let enabled: Bool = attribute(kAXEnabledAttribute, of: copyItem), enabled else { return false }
        return AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success
    }

    // Edit is the fourth menu in nearly every app: check it first, then its neighbours
    private func findCopyItem(inMenuBar menuBar: AXUIElement) -> AXUIElement? {
        guard let menus: [AXUIElement] = attribute(kAXChildrenAttribute, of: menuBar) else { return nil }
        let editIndex = 3
        for index in menus.indices.sorted(by: { abs($0 - editIndex) < abs($1 - editIndex) }) {
            guard let submenus: [AXUIElement] = attribute(kAXChildrenAttribute, of: menus[index]),
                  let submenu = submenus.first,
                  let items: [AXUIElement] = attribute(kAXChildrenAttribute, of: submenu) else { continue }
            if let item = items.first(where: isCopyItem) { return item }
        }
        return nil
    }

    // AppKit exposes the action selector as the identifier; the plain Cmd+C key equivalent
    // covers menus built without AppKit selectors (Electron, Qt); the title covers apps that
    // route Cmd+C through their own key handling and leave the item without an equivalent (Ghostty)
    private func isCopyItem(_ item: AXUIElement) -> Bool {
        if let identifier: String = attribute(kAXIdentifierAttribute, of: item), identifier == "copy:" {
            return true
        }
        let cmdChar: String? = attribute(kAXMenuItemCmdCharAttribute, of: item)
        let modifiers: Int? = attribute(kAXMenuItemCmdModifiersAttribute, of: item)
        if cmdChar?.uppercased() == "C" && modifiers == 0 { return true }
        let title: String? = attribute(kAXTitleAttribute, of: item)
        return title.map(Self.copyTitles.contains) ?? false
    }

    private static let copyTitles: Set<String> = [
        "Copy", "Скопировать", "Копировать", "Копіювати", "Kopieren", "Copier", "Copiar", "Copia",
        "Kopiuj", "Kopiëren", "Kopiera", "Kopiér", "Kopioi", "Kopyala", "Másolás", "Kopírovat",
        "拷贝", "复制", "拷貝", "複製", "コピー", "복사",
    ]

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
