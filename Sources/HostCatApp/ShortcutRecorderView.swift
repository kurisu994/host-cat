import AppKit
import Carbon.HIToolbox
import SwiftUI

/// SwiftUI 中嵌入的快捷键录制框。
///
/// 视觉：圆角矩形 + 居中显示当前快捷键 / placeholder，已绑定时尾部出现清除按钮。
/// 交互：单击进入录制态（边框高亮）→ 按下任意带 modifier 的组合键即写入；Esc 取消。
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    /// 当 placeholder 文案需要随系统语言切换时由外部传入；NSView 拿不到 SwiftUI 环境。
    let idlePlaceholder: String
    let recordingPlaceholder: String

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.idlePlaceholder = idlePlaceholder
        view.recordingPlaceholder = recordingPlaceholder
        view.shortcut = shortcut
        view.onChange = { newValue in
            // updateNSView 同时也会写回 binding，需要避免反复重绘
            if newValue != shortcut {
                shortcut = newValue
            }
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.idlePlaceholder = idlePlaceholder
        nsView.recordingPlaceholder = recordingPlaceholder
        if nsView.shortcut != shortcut {
            nsView.shortcut = shortcut
        }
    }
}

/// 录制框底层 AppKit 视图。负责键盘捕获、绘制和与 SwiftUI 之间的回调桥接。
final class ShortcutRecorderNSView: NSView {
    var shortcut: Shortcut? {
        didSet { refresh() }
    }

    var onChange: ((Shortcut?) -> Void)?

    var idlePlaceholder: String = "" {
        didSet { refresh() }
    }
    var recordingPlaceholder: String = "" {
        didSet { refresh() }
    }

    private var isRecording = false {
        didSet { refresh() }
    }

    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        clearButton.title = ""
        clearButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: nil
        )
        clearButton.imagePosition = .imageOnly
        clearButton.isBordered = false
        clearButton.bezelStyle = .inline
        clearButton.target = self
        clearButton.action = #selector(handleClear)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16)
        ])

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 24) }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Esc 退出录制态，不修改已有快捷键
        if Int(event.keyCode) == kVK_Escape {
            window?.makeFirstResponder(nil)
            return
        }
        // 必须带 modifier，否则发出系统提示音并继续等待
        guard let newShortcut = Shortcut(event: event) else {
            NSSound.beep()
            return
        }
        shortcut = newShortcut
        onChange?(newShortcut)
        window?.makeFirstResponder(nil)
    }

    @objc private func handleClear() {
        shortcut = nil
        onChange?(nil)
        window?.makeFirstResponder(nil)
    }

    private func refresh() {
        if let shortcut {
            label.stringValue = shortcut.displayString
            label.textColor = .labelColor
            clearButton.isHidden = false
        } else {
            label.stringValue = isRecording ? recordingPlaceholder : idlePlaceholder
            label.textColor = .secondaryLabelColor
            clearButton.isHidden = true
        }
        layer?.borderColor = (
            isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        ).cgColor
    }
}
