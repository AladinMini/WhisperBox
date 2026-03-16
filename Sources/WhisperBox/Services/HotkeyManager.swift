import Cocoa

final class HotkeyManager {
    var onToggle: (() -> Void)?
    var rightOptionDown = false
    var configuredKeyCode: Int = 61  // Right Option
    var configuredModifiers: Int = 0

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

    guard let userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    let targetKeyCode = manager.configuredKeyCode
    let targetModifiers = manager.configuredModifiers

    // Standalone modifier key (e.g. Right Option, Left Shift)
    let standaloneModifierCodes = [58, 61, 56, 60, 59, 62, 55, 54]
    let isStandaloneModifier = targetModifiers == 0 && standaloneModifierCodes.contains(targetKeyCode)

    if isStandaloneModifier && type == .flagsChanged {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == Int64(targetKeyCode) {
            let flags = event.flags
            let hasModifier = !flags.intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand]).isEmpty
            if hasModifier && !manager.rightOptionDown {
                manager.rightOptionDown = true
                DispatchQueue.main.async {
                    manager.onToggle?()
                }
            } else if !hasModifier {
                manager.rightOptionDown = false
            }
        }
        return Unmanaged.passRetained(event)
    }

    // Regular key + modifier combo (e.g. ⌥Space, ⌘⇧R)
    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    if Int(keyCode) == targetKeyCode {
        let requiredMods = NSEvent.ModifierFlags(rawValue: UInt(targetModifiers))
        let currentMods = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).intersection([.control, .option, .shift, .command])

        if currentMods == requiredMods {
            DispatchQueue.main.async {
                manager.onToggle?()
            }
            return nil
        }
    }

    return Unmanaged.passRetained(event)
}
