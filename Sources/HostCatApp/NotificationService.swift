import AppKit
import HostCatCore
import os.log
import UserNotifications

/// 把写入流程事件转成系统通知。
///
/// - 偏好（成功 / 失败 / 外部修改）每次发送前从 `UserDefaults` 读取，设置页改动立即生效。
/// - 授权在用户首次需要通知时懒请求；被拒绝后不再打扰，设置页提供跳转系统设置的入口。
/// - 点击通知弹出菜单栏菜单（菜单里能看到错误信息，并可进入编辑器处理）。
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private static let logger = Logger(subsystem: "com.hostcat.app", category: "notification")

    private let center: UNUserNotificationCenter?

    private override init() {
        // 非 .app 打包运行（如 swift run）时 UNUserNotificationCenter 会崩溃，需规避。
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
    }

    /// 启动时挂载代理，使应用处于前台时通知也能以横幅展示、点击能回调。
    func bootstrap() {
        center?.delegate = self
    }

    /// 根据当前偏好决定是否发送通知。
    func handle(_ event: ApplyNotificationEvent) {
        guard NotificationPreferences.load().shouldNotify(for: event) else { return }
        guard let center else { return }

        Task {
            guard await ensureAuthorized(center) else { return }
            let content = UNMutableNotificationContent()
            switch event {
            case .applied:
                content.title = L.notificationApplySuccessTitle
                content.body = L.notificationApplySuccessBody
            case let .failed(message):
                content.title = L.notificationApplyFailedTitle
                content.body = message
                content.sound = .default
            case let .appliedWithWarning(message):
                content.title = L.notificationApplyWarningTitle
                content.body = message
                content.sound = .default
            case .externalModification:
                content.title = L.notificationExternalModificationTitle
                content.body = L.notificationExternalModificationBody
                content.sound = .default
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                Self.logger.error("发送通知失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 读取授权状态；未决定时弹出系统授权请求。
    func ensureAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            Self.logger.info("通知授权结果：\(granted, privacy: .public)")
            return granted
        default:
            return false
        }
    }

    /// 设置页打开某个通知开关时主动触发授权请求，返回当前是否被系统禁止。
    func requestAuthorizationIfNeeded() async -> Bool {
        guard let center else { return true }
        return await ensureAuthorized(center)
    }

    /// 当前是否已被系统拒绝，用于设置页提示。
    func isDenied() async -> Bool {
        guard let center else { return false }
        return await center.notificationSettings().authorizationStatus == .denied
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            MenuBarStatusItemOpener.open()
        }
    }
}
