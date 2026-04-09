import AppKit
import SwiftUI

enum OverlayStyle: String, CaseIterable {
    case none = "none"
    case bubble = "bubble"
    case subtitle = "subtitle"

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .bubble: return "Floating Bubble"
        case .subtitle: return "Subtitles"
        }
    }
}

@MainActor
final class TranscriptOverlayWindow {
    private var window: NSWindow?
    private var hostingView: NSHostingView<TranscriptOverlayView>?
    private let viewModel = TranscriptOverlayViewModel()

    var style: OverlayStyle = .bubble {
        didSet {
            if style == .none {
                hide()
            } else {
                repositionWindow()
            }
        }
    }

    func show(userText: String? = nil, responseText: String? = nil) {
        if style == .none { return }

        if let t = userText { viewModel.userText = t }
        if let t = responseText { viewModel.responseText = t }
        viewModel.isVisible = true

        if window == nil {
            createWindow()
        }
        repositionWindow()
        window?.orderFrontRegardless()
    }

    func updateResponse(_ text: String) {
        if style == .none { return }
        viewModel.responseText = text
        if window == nil { createWindow() }
        repositionWindow()
        window?.orderFrontRegardless()
    }

    func hide() {
        viewModel.isVisible = false
        viewModel.userText = ""
        viewModel.responseText = ""
        window?.orderOut(nil)
    }

    private func createWindow() {
        let view = TranscriptOverlayView(viewModel: viewModel, style: style)
        let hosting = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.ignoresMouseEvents = false
        w.hasShadow = false
        w.contentView = hosting

        self.window = w
        self.hostingView = hosting
    }

    private func repositionWindow() {
        guard let screen = NSScreen.main else { return }

        // Update the view's style
        let view = TranscriptOverlayView(viewModel: viewModel, style: style)
        hostingView?.rootView = view

        switch style {
        case .bubble:
            let width: CGFloat = 450
            let height: CGFloat = 300
            let x = screen.visibleFrame.maxX - width - 20
            let y = screen.visibleFrame.maxY - height - 10
            window?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        case .subtitle:
            let width: CGFloat = 800
            let height: CGFloat = 200
            let x = screen.frame.midX - width / 2
            let y: CGFloat = 60
            window?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        case .none:
            break
        }
    }
}

@Observable
class TranscriptOverlayViewModel {
    var userText: String = ""
    var responseText: String = ""
    var isVisible: Bool = false
}

struct TranscriptOverlayView: View {
    @Bindable var viewModel: TranscriptOverlayViewModel
    let style: OverlayStyle

    var body: some View {
        if viewModel.isVisible {
            switch style {
            case .bubble:
                bubbleView
            case .subtitle:
                subtitleView
            case .none:
                EmptyView()
            }
        }
    }

    /// Show only the last few lines of text to keep it in view
    private func lastLines(_ text: String, count: Int) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "." })
        // For continuous text without newlines, do word-based truncation
        let words = text.split(separator: " ")
        if words.count > count * 12 {
            return words.suffix(count * 12).joined(separator: " ")
        }
        return text
    }

    private var bubbleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !viewModel.userText.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(viewModel.userText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                }
            }

            if !viewModel.responseText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(viewModel.responseText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id("bottom")
                    }
                    .onChange(of: viewModel.responseText) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button(action: {
                var text = ""
                if !viewModel.userText.isEmpty { text += "You: \(viewModel.userText)\n" }
                if !viewModel.responseText.isEmpty { text += "\(viewModel.responseText)" }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .padding(8)
    }

    private var subtitleView: some View {
        VStack(spacing: 4) {
            if !viewModel.userText.isEmpty {
                Text(viewModel.userText)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if !viewModel.responseText.isEmpty {
                // Show only last ~3 lines worth of words for subtitle style
                Text(lastLines(viewModel.responseText, count: 2))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.75))
        )
    }
}
