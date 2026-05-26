import AppKit
import SwiftUI

/// NSViewRepresentable helper that automatically focuses the window when it appears.
struct WindowFocusView: NSViewRepresentable {
    let title: String

    func makeNSView(context _: Context) -> NSView {
        FocusHostingView(title: title)
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? FocusHostingView else { return }
        view.title = title
    }

    private final class FocusHostingView: NSView {
        var title: String

        init(title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusWindowIfAvailable()
        }

        func focusWindowIfAvailable() {
            guard let window else { return }
            WindowFocus.focusOnce(window: window)
        }
    }
}

/// Window activation and focus management utility.
@MainActor
enum WindowFocus {
    private static var focusedWindowIDs: Set<ObjectIdentifier> = []

    static func focusSoon(title: String) {
        focus(title: title)
        Task { @MainActor in
            focus(title: title)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            focus(title: title)
        }
    }

    static func focus(title: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let window = NSApplication.shared.windows.first(where: { $0.title == title }) else { return }
        focus(window: window)
    }

    static func focusOnce(window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard focusedWindowIDs.insert(windowID).inserted else { return }
        focus(window: window)
    }

    static func focus(window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
