import AppKit
import Carbon.HIToolbox
import OSLog

/// 基于 Carbon `RegisterEventHotKey` 的全局快捷键监听器。
///
/// 这是 Apple 官方稳定 API（10.3 起），不需要"输入监控"或"辅助功能"授权。
/// `MenuBarExtra` 没有公开「以编程方式弹出菜单」的 SwiftUI API，
/// 这里只负责监听快捷键并把回调派发到 main actor，弹菜单的动作由调用方负责。
@MainActor
final class CarbonHotKeyMonitor {
    static let shared = CarbonHotKeyMonitor()

    private static let logger = Logger(subsystem: "com.hostcat.app", category: "carbon-hotkey")

    /// 用一个 four-char code 作为 hot key signature，避免和其他 app 的注册冲突。
    /// 'HOST' = 0x484f5354
    private static let signature: OSType = 0x484f5354

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?

    private init() {}

    /// 注册或替换当前全局快捷键。重复调用会先解除旧 hot key，再注册新的。
    /// - Parameters:
    ///   - shortcut: 要监听的快捷键；传 nil 等价于只解绑。
    ///   - handler: 快捷键按下时在 main actor 上执行的回调。
    func register(shortcut: Shortcut?, handler: @escaping @MainActor () -> Void) {
        unregister()
        self.handler = handler

        guard let shortcut else { return }

        installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            Self.logger.info("已注册全局快捷键 \(shortcut.displayString, privacy: .public)")
        } else {
            Self.logger.warning("注册全局快捷键失败，OSStatus=\(status, privacy: .public)")
        }
    }

    /// 解绑当前 hot key，但保留 EventHandler（重新注册时复用）。
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// 收到 Carbon 回调时由 C 回调函数转入此方法触发用户 handler。
    fileprivate func dispatchHotKey() {
        handler?()
    }

    /// 安装一次性的 application-wide EventHandler，把 `kEventHotKeyPressed` 事件路由到 `dispatchHotKey`。
    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventHandler,
            1,
            &spec,
            selfPtr,
            &eventHandlerRef
        )
    }
}

/// Carbon EventHandler 的 C 回调入口。Carbon 已经把事件投递到主线程，
/// 因此可以用 `MainActor.assumeIsolated` 安全地进入 main actor 隔离域调用 monitor。
private let carbonHotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
    guard let eventRef, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return noErr }

    let monitor = Unmanaged<CarbonHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.dispatchHotKey()
    }
    return noErr
}
