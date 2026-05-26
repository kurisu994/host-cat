import AppKit
import SwiftUI

/// Name input dialog (used for creating groups, creating nodes, and renaming nodes).
struct NameInputDialog: View {
    let title: String
    let placeholder: String
    let confirmTitle: String
    @Binding var name: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)

                FocusedNameTextField(
                    placeholder: placeholder,
                    text: $name,
                    onSubmit: submit
                )
                .frame(height: 24)

                HStack {
                    Button(L.dialogCancel, role: .cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(confirmTitle) {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                }
            }
            .padding(24)
            .frame(width: 360)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        }
    }

    private var canSubmit: Bool {
        !name.isEmpty
    }

    @MainActor
    private func submit() {
        guard canSubmit else { return }
        onSubmit()
    }
}

/// NSTextField wrapper that handles focus acquisition and IME compatibility for menu bar apps.
struct FocusedNameTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.bezelStyle = .roundedBezel
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit(_:))
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit

        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }

        // While the input method is composing (e.g., during pinyin input), do not force-sync stringValue to avoid interrupting the IME.
        let hasMarkedText = (textField.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if !hasMarkedText, textField.stringValue != text {
            textField.stringValue = text
        }

        context.coordinator.focus(textField)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        private var didRequestFocus = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            // While the input method is composing characters (e.g., Chinese pinyin), skip updating the binding
            // to avoid triggering SwiftUI rebuilds that would interrupt the IME state via updateNSView.
            if let editor = textField.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
            text.wrappedValue = textField.stringValue
        }

        @objc func submit(_ sender: NSTextField) {
            text.wrappedValue = sender.stringValue
            onSubmit()
        }

        func focus(_ textField: NSTextField) {
            guard !didRequestFocus else { return }
            didRequestFocus = true

            Task { @MainActor in
                // Menu bar apps need a slightly longer delay; retry multiple times.
                for delay in [0, 10, 50, 100, 200, 400] {
                    if delay > 0 {
                        try? await Task.sleep(for: .milliseconds(delay))
                    }
                    if focusNow(textField) {
                        return
                    }
                }
            }
        }

        private func focusNow(_ textField: NSTextField) -> Bool {
            guard let window = textField.window else { return false }
            guard textField.currentEditor() == nil else { return true }

            // Menu bar apps default to .accessory activation policy;
            // temporarily switch to .regular to reliably acquire keyboard focus.
            let app = NSApplication.shared
            if app.activationPolicy() != .regular {
                app.setActivationPolicy(.regular)
            }
            app.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.makeFirstResponder(textField)
            textField.selectText(nil)
            return textField.currentEditor() != nil
        }
    }
}
