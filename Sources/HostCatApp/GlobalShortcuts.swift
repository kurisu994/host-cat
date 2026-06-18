import AppKit
import KeyboardShortcuts
import OSLog

/// 全局快捷键名称定义。
///
/// 仅声明键名，默认不绑定具体快捷键，由用户在「设置 > 通用 > 快捷键」中录入。
extension KeyboardShortcuts.Name {
    /// 弹出菜单栏菜单的全局快捷键。
    static let toggleMenuBar = Self("toggleMenuBar")
}

/// 全局快捷键注册与触发的入口。
///
/// 当前只承载「打开菜单栏」一个键，后续如需新增（例如直接打开编辑器）可在此扩展。
enum GlobalShortcutManager {
    private static let logger = Logger(subsystem: "com.hostcat.app", category: "global-shortcuts")

    /// 一次性注册所有全局快捷键回调，重复调用会被忽略。
    @MainActor
    static func registerHandlers() {
        guard !hasRegistered else { return }
        hasRegistered = true

        KeyboardShortcuts.onKeyDown(for: .toggleMenuBar) {
            MenuBarStatusItemOpener.open()
        }
    }

    @MainActor private static var hasRegistered = false
}

/// 通过遍历 `NSApp.windows` 查找 MenuBarExtra 对应的 `NSStatusBarWindow`，
/// 调用其内部的 `NSStatusBarButton.performClick(_:)` 模拟点击弹出菜单。
///
/// SwiftUI 的 `MenuBarExtra` 没有公开「打开菜单」的 API，但底层仍然是 `NSStatusItem`，
/// 其 button 会被宿主到一个类名为 `NSStatusBarWindow` 的窗口里。
/// 这里只依赖窗口类名和 button subview 结构，不触碰任何私有 API。
enum MenuBarStatusItemOpener {
    private static let logger = Logger(subsystem: "com.hostcat.app", category: "menubar-opener")

    @MainActor
    static func open() {
        guard let button = locateStatusButton() else {
            logger.warning("未找到 MenuBarExtra 对应的 NSStatusBarButton，快捷键无法弹出菜单")
            NSSound.beep()
            return
        }
        button.performClick(nil)
    }

    @MainActor
    private static func locateStatusButton() -> NSButton? {
        for window in NSApplication.shared.windows {
            // SwiftUI MenuBarExtra 内部窗口类名以 "NSStatusBarWindow" 开头。
            let className = String(describing: type(of: window))
            guard className.contains("StatusBar") else { continue }
            if let button = firstButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    @MainActor
    private static func firstButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton {
            return button
        }
        for subview in view.subviews {
            if let button = firstButton(in: subview) {
                return button
            }
        }
        return nil
    }
}
