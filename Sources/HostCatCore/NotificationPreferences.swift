import Foundation

/// hosts 写入流程对外广播的事件，由 App 层决定是否转成系统通知。
public enum ApplyNotificationEvent: Equatable, Sendable {
    /// hosts 写入成功。
    case applied
    /// 写入失败（含冲突、Helper 不可用等），附带可展示的原因。
    case failed(String)
    /// hosts 已写入，但有需要用户留意的问题（如 DNS 未确认刷新），附带说明。
    case appliedWithWarning(String)
    /// 检测到 /etc/hosts 被外部修改。
    case externalModification
}

/// 通知偏好：成功通知默认关闭，失败与外部修改默认开启。
public struct NotificationPreferences: Equatable, Sendable {
    public static let notifyOnSuccessKey = "HostCat.notifyOnSuccess"
    public static let notifyOnFailureKey = "HostCat.notifyOnFailure"
    public static let notifyOnExternalModificationKey = "HostCat.notifyOnExternalModification"

    public static let defaultNotifyOnSuccess = false
    public static let defaultNotifyOnFailure = true
    public static let defaultNotifyOnExternalModification = true

    public var notifyOnSuccess: Bool
    public var notifyOnFailure: Bool
    public var notifyOnExternalModification: Bool

    public init(
        notifyOnSuccess: Bool = defaultNotifyOnSuccess,
        notifyOnFailure: Bool = defaultNotifyOnFailure,
        notifyOnExternalModification: Bool = defaultNotifyOnExternalModification
    ) {
        self.notifyOnSuccess = notifyOnSuccess
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnExternalModification = notifyOnExternalModification
    }

    /// 从 UserDefaults 读取；未设置的键使用默认值。
    public static func load(from userDefaults: UserDefaults = .standard) -> NotificationPreferences {
        func value(_ key: String, default fallback: Bool) -> Bool {
            userDefaults.object(forKey: key) as? Bool ?? fallback
        }
        return NotificationPreferences(
            notifyOnSuccess: value(notifyOnSuccessKey, default: defaultNotifyOnSuccess),
            notifyOnFailure: value(notifyOnFailureKey, default: defaultNotifyOnFailure),
            notifyOnExternalModification: value(
                notifyOnExternalModificationKey,
                default: defaultNotifyOnExternalModification
            )
        )
    }

    /// 该事件在当前偏好下是否需要发送通知。
    public func shouldNotify(for event: ApplyNotificationEvent) -> Bool {
        switch event {
        case .applied: notifyOnSuccess
        case .failed, .appliedWithWarning: notifyOnFailure
        case .externalModification: notifyOnExternalModification
        }
    }
}
