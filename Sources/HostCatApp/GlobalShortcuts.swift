import AppKit
import OSLog

/// 全局快捷键的持久化与运行时注册中心。
///
/// - 通过 `UserDefaults` 持久化用户绑定的 `Shortcut`（JSON 编码）。
/// - 任何修改都会立即同步给 `CarbonHotKeyMonitor` 重新注册，无需重启 app。
/// - `ObservableObject` 让 SwiftUI 设置页能直接以 `Binding` 形式编辑当前绑定。
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    private static let userDefaultsKey = "HostCat.shortcut.toggleMenuBar"
    private static let logger = Logger(subsystem: "com.hostcat.app", category: "shortcut-store")

    @Published var toggleMenuBar: Shortcut? {
        didSet {
            guard toggleMenuBar != oldValue else { return }
            persist()
            applyToMonitor()
        }
    }

    private init() {
        // 用 `_toggleMenuBar` 直接初始化绕过 didSet：恢复时不希望触发"再次写盘 + 重注册"。
        _toggleMenuBar = Published(initialValue: Self.load())
    }

    /// 应用启动后调用一次，把已持久化的快捷键挂到 Carbon。
    /// 之后通过 `toggleMenuBar` setter 自动维护。
    func bootstrap() {
        applyToMonitor()
    }

    private func applyToMonitor() {
        CarbonHotKeyMonitor.shared.register(shortcut: toggleMenuBar) {
            MenuBarStatusItemOpener.open()
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        guard let toggleMenuBar else {
            defaults.removeObject(forKey: Self.userDefaultsKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(toggleMenuBar)
            defaults.set(data, forKey: Self.userDefaultsKey)
        } catch {
            Self.logger.warning("快捷键持久化失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load() -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        do {
            return try JSONDecoder().decode(Shortcut.self, from: data)
        } catch {
            Self.logger.warning("读取已持久化快捷键失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
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
