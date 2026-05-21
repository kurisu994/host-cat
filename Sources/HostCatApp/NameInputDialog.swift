import AppKit
import SwiftUI

/// 名称输入弹窗（用于新建分组、新建节点、重命名节点）
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
                    Button("取消", role: .cancel) {
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

/// NSTextField 封装，处理菜单栏应用的焦点获取和输入法兼容
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

        // 输入法正在组合（如拼音输入中），不要强制同步 stringValue，否则会打断 IME
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
            // 输入法正在组合字符时（如中文拼音），跳过更新 binding，
            // 避免触发 SwiftUI 重建导致 updateNSView 打断 IME 状态
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
                // 菜单栏应用延迟稍长，多试几次
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

            // 菜单栏应用默认 activation policy 是 .accessory，
            // 必须临时切到 .regular 才能可靠获取键盘焦点
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
