import AppKit
import Carbon.HIToolbox

/// 全局快捷键的可持久化值类型。
///
/// - `keyCode`：macOS 虚拟键码（`kVK_*`），跟物理按键位置绑定，与键盘布局无关。
/// - `carbonModifiers`：Carbon 风格 modifier mask（`cmdKey`/`shiftKey`/`optionKey`/`controlKey` 组合）。
///   存 Carbon 风格而不是 Cocoa 风格是因为 `RegisterEventHotKey` 直接吃 Carbon mask，避免每次注册都做转换。
struct Shortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    /// 从用户在录制框中按下的 `NSEvent` 构造快捷键。
    ///
    /// 必须包含至少一个 modifier（⌘/⌥/⌃/⇧），否则返回 nil —— 单字母快捷键会跟正常输入冲突。
    init?(event: NSEvent) {
        let cocoaFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbon = Shortcut.carbonModifiers(from: cocoaFlags)
        guard carbon != 0 else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// 把 Cocoa `NSEvent.ModifierFlags` 转成 Carbon `RegisterEventHotKey` 需要的 mask。
    static func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if cocoa.contains(.command) { result |= UInt32(cmdKey) }
        if cocoa.contains(.option) { result |= UInt32(optionKey) }
        if cocoa.contains(.control) { result |= UInt32(controlKey) }
        if cocoa.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// 录制框和提示信息使用的可读符号串，例如 `⌃⌥⌘K`。
    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += Shortcut.keyCodeDisplay(keyCode)
        return s
    }

    /// 把虚拟键码翻译成显示用字符。
    /// - 优先匹配特殊键符号表（功能键 / 方向键 / Esc 等）。
    /// - 普通字符键走 `UCKeyTranslate`，根据当前键盘布局取无 modifier 时的可见字符。
    /// - 翻译失败时退化成 `#<keyCode>`，避免崩溃。
    static func keyCodeDisplay(_ keyCode: UInt32) -> String {
        if let symbol = specialKeySymbols[Int(keyCode)] {
            return symbol
        }
        if let translated = translate(keyCode: keyCode) {
            return translated
        }
        return "#\(keyCode)"
    }

    private static let specialKeySymbols: [Int: String] = [
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Space: "␣",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_DownArrow: "↓",
        kVK_UpArrow: "↑",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    /// 使用当前键盘布局把虚拟键码翻译成显示字符（不应用任何 modifier）。
    private static func translate(keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRef).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let keyLayout = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var deadKeyState: UInt32 = 0
        var actualStringLength = 0
        var chars: [UniChar] = [0, 0, 0, 0]

        let status = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &actualStringLength,
            &chars
        )
        guard status == noErr, actualStringLength > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: actualStringLength)
        return string.uppercased()
    }
}
