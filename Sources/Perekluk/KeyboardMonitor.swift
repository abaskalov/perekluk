import CoreGraphics
import Carbon

struct KeyStroke {
    let keyCode: UInt16
    let shift: Bool
    let capsLock: Bool
}

final class KeyboardMonitor {
    var onSwitchTriggered: (([KeyStroke]) -> Void)?

    private(set) var buffer: [KeyStroke] = []
    var eventTap: CFMachPort?

    var optionDown = false
    var optionAlone = false

    private let maxBufferSize = 64

    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            print("[Perekluk] Failed to create event tap. Accessibility permissions required.")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func clearBuffer() {
        buffer.removeAll(keepingCapacity: true)
    }

    func handleKeyDown(_ keyCode: UInt16, flags: CGEventFlags) {
        if optionDown {
            optionAlone = false
            return
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return
        }

        if Self.wordBoundaryKeys.contains(keyCode) {
            clearBuffer()
            return
        }

        // 51 = Backspace — undo the last buffered keystroke
        if keyCode == 51 {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
            return
        }

        // keyCodes 0..50 are printable characters on standard layouts
        guard keyCode <= 50 else { return }

        let shift = flags.contains(.maskShift)
        let capsLock = flags.contains(.maskAlphaShift)
        buffer.append(KeyStroke(keyCode: keyCode, shift: shift, capsLock: capsLock))

        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
    }

    func handleFlagsChanged(flags: CGEventFlags) {
        let optionPressed = flags.contains(.maskAlternate)

        if optionPressed && !optionDown {
            optionDown = true
            optionAlone = true
        } else if !optionPressed && optionDown {
            if optionAlone {
                onSwitchTriggered?(buffer)
            }
            optionDown = false
            optionAlone = false
        }
    }

    func handleMouseDown() {
        clearBuffer()
    }

    // MARK: - Key Constants

    private static let wordBoundaryKeys: Set<UInt16> = [
        49, // Space
        36, // Return
        76, // Enter (numpad)
        48, // Tab
        53, // Escape
    ]
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = monitor.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    if event.getIntegerValueField(.eventSourceUserData) == TextReplacer.markerUserData {
        return Unmanaged.passUnretained(event)
    }

    switch type {
    case .keyDown:
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        monitor.handleKeyDown(keyCode, flags: event.flags)

    case .flagsChanged:
        monitor.handleFlagsChanged(flags: event.flags)

    case .leftMouseDown, .rightMouseDown:
        monitor.handleMouseDown()

    default:
        break
    }

    return Unmanaged.passUnretained(event)
}
