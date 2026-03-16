import SwiftUI
import Carbon.HIToolbox

struct HotkeyRecorderView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Hotkey:")
            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Press a key..." : hotkeyDisplayName)
                    .frame(minWidth: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onKeyPress { keyPress in
                guard isRecording else { return .ignored }
                // Map the key press
                return .handled
            }
        }
        .background(isRecording ? HotkeyCapture(keyCode: $keyCode, modifiers: $modifiers, isRecording: $isRecording) : nil)
    }

    private var hotkeyDisplayName: String {
        if keyCode == 61 && modifiers == 0 { return "Right ⌥" }
        if keyCode == 58 && modifiers == 0 { return "Left ⌥" }

        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }

        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: Int) -> String {
        let map: [Int: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
            53: "Esc", 126: "↑", 125: "↓", 123: "←", 124: "→",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z",
            7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E",
            15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            58: "Left ⌥", 61: "Right ⌥",
        ]
        return map[code] ?? "Key \(code)"
    }
}

struct HotkeyCapture: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> HotkeyCaptureView {
        let view = HotkeyCaptureView()
        view.onKeyCapture = { code, mods in
            keyCode = code
            modifiers = mods
            isRecording = false
        }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class HotkeyCaptureView: NSView {
    var onKeyCapture: ((Int, Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
        onKeyCapture?(Int(event.keyCode), Int(mods.rawValue))
    }

    override func flagsChanged(with event: NSEvent) {
        // Capture standalone modifier keys (like right option)
        let keyCode = Int(event.keyCode)
        // 58 = left option, 61 = right option, 56 = left shift, 60 = right shift
        // 59 = left control, 62 = right control, 55 = left cmd, 54 = right cmd
        let standaloneModifiers = [58, 61, 56, 60, 59, 62, 55, 54]
        if standaloneModifiers.contains(keyCode) {
            onKeyCapture?(keyCode, 0) // standalone modifier, no combo
        }
    }
}
