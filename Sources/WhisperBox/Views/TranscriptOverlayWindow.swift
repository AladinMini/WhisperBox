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
        w.ignoresMouseEvents = true
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
            let width: CGFloat = 400
            let height: CGFloat = 120
            let x = screen.visibleFrame.maxX - width - 20
            let y = screen.visibleFrame.maxY - height - 10
            window?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        case .subtitle:
            let width: CGFloat = 700
            let height: CGFloat = 80
            let x = screen.frame.midX - width / 2
            let y: CGFloat = 80
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
                        .lineLimit(2)
                }
            }

            if !viewModel.responseText.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(viewModel.responseText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(1)
            }

            if !viewModel.responseText.isEmpty {
                Text(viewModel.responseText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.black.opacity(0.75))
        )
    }
}
