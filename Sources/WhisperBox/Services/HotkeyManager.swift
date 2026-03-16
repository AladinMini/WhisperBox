import Cocoa

final class HotkeyManager {
    var onToggle: (() -> Void)?
    var rightOptionDown = false

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyCallback,
            userInfo: userInfo
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    deinit {
        stop()
    }
}

// C-compatible callback function
private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle tap disabled events (system can disable taps)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo, let tap = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue().eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    // Detect Right Option key press via flagsChanged event
    if type == .flagsChanged {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // keycode 61 = Right Option key
        if keyCode == 61 {
            let flags = event.flags
            let isPressed = flags.contains(.maskAlternate)
            if let userInfo {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                if isPressed && !manager.rightOptionDown {
                    manager.rightOptionDown = true
                    DispatchQueue.main.async {
                        manager.onToggle?()
                    }
                } else if !isPressed {
                    manager.rightOptionDown = false
                }
            }
        }
        return Unmanaged.passRetained(event)
    }

    // Also keep Option+Space as fallback
    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    let isOptionPressed = flags.contains(.maskAlternate)
    let isSpace = keyCode == 49
    let noOtherModifiers = !flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskShift)

    if isSpace && isOptionPressed && noOtherModifiers {
        if let userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onToggle?()
            }
        }
        return nil
    }

    return Unmanaged.passRetained(event)
}
