import SwiftUI
import AppKit

struct HotkeyRecorder: View {
    @Binding var hotkey: String
    @State private var isRecording = false
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    @State private var recordedKey: String = ""

    var body: some View {
        Button(action: {
            isRecording.toggle()
            if isRecording {
                recordedModifiers = []
                recordedKey = ""
            }
        }) {
            HStack {
                if isRecording {
                    Text(currentStrokeString.isEmpty ? "请按下按键..." : currentStrokeString)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(hotkey.isEmpty ? "点击录制" : hotkey)
                }

                if isRecording {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(minWidth: 120)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRecording ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .background(HotkeyMonitorView(isRecording: $isRecording) { modifiers, key in
            self.recordedModifiers = modifiers
            self.recordedKey = key
            self.hotkey = formatRimeHotkey(modifiers: modifiers, key: key)
            self.isRecording = false
        })
    }

    private var currentStrokeString: String {
        formatRimeHotkey(modifiers: recordedModifiers, key: recordedKey)
    }

    private func formatRimeHotkey(modifiers: NSEvent.ModifierFlags, key: String) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.command) { parts.append("Command") }

        if !key.isEmpty {
            parts.append(key)
        }

        return parts.joined(separator: "+")
    }
}

private struct HotkeyMonitorView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCaptured: (NSEvent.ModifierFlags, String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            context.coordinator.startMonitoring(onCaptured: onCaptured)
        } else {
            context.coordinator.stopMonitoring()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording)
    }

    class Coordinator: NSObject {
        @Binding var isRecording: Bool
        var monitor: Any?

        init(isRecording: Binding<Bool>) {
            _isRecording = isRecording
        }

        func startMonitoring(onCaptured: @escaping (NSEvent.ModifierFlags, String) -> Void) {
            stopMonitoring()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if event.type == .flagsChanged {
                    // Just update UI if we wanted to show modifiers being held
                    return event
                }

                if event.type == .keyDown {
                    let modifiers = event.modifierFlags
                    let key = self.translateKey(event: event)

                    if !key.isEmpty {
                        onCaptured(modifiers, key)
                        return nil // Swallow the event
                    }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func translateKey(event: NSEvent) -> String {
            // Rime specific key names
            switch event.keyCode {
            case 50: return "grave"
            case 36: return "Return"
            case 48: return "Tab"
            case 49: return "space"
            case 51: return "BackSpace"
            case 53: return "Escape"
            case 123: return "Left"
            case 124: return "Right"
            case 125: return "Down"
            case 126: return "Up"
            case 116: return "Page_Up"
            case 121: return "Page_Down"
            case 115: return "Home"
            case 119: return "End"
            case 117: return "Delete"
            case 122: return "F1"
            case 120: return "F2"
            case 99: return "F3"
            case 118: return "F4"
            case 96: return "F5"
            case 97: return "F6"
            case 98: return "F7"
            case 100: return "F8"
            case 101: return "F9"
            case 109: return "F10"
            case 103: return "F11"
            case 111: return "F12"
            default:
                if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    let char = chars.first!
                    if char == "`" { return "grave" }
                    return String(char)
                }
                return ""
            }
        }
    }
}
