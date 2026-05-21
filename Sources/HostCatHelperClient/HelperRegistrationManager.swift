import Foundation
import HostCatCore
import ServiceManagement
import os.log

/// Helper 注册和开机自启动管理
///
/// 负责：
/// 1. Privileged Helper 的 `SMAppService.daemon` 注册、状态检测和审批引导
/// 2. 主应用的 `SMAppService.mainApp` 开机自启动管理
@MainActor
public final class HelperRegistrationManager: ObservableObject {
    /// Helper daemon 注册状态
    @Published public var helperStatus: SMAppService.Status = .notRegistered
    /// 最近一次操作的错误信息
    @Published public var lastError: String?

    private let helperService: SMAppService
    private let logger = Logger(subsystem: "com.hostcat.app", category: "HelperRegistrationManager")

    public init() {
        helperService = SMAppService.daemon(plistName: "com.hostcat.helper.plist")
        refreshHelperStatus()
    }

    // MARK: - Helper 注册

    /// 注册 Privileged Helper
    ///
    /// 首次注册时 macOS 会在「系统设置 > 登录项」中创建审批项，
    /// 用户需手动启用后 Helper 才能正常工作。
    public func registerHelper() {
        lastError = nil
        do {
            try helperService.register()
            refreshHelperStatus()
            logger.info("Helper 注册成功，当前状态: \(String(describing: self.helperStatus))")
        } catch {
            lastError = "Helper 注册失败：\(error.localizedDescription)"
            logger.error("Helper 注册失败: \(error.localizedDescription)")
            refreshHelperStatus()
        }
    }

    /// 刷新 Helper 注册状态
    public func refreshHelperStatus() {
        helperStatus = helperService.status
        logger.debug("Helper 状态: \(String(describing: self.helperStatus))")
    }

    /// 打开系统设置引导用户审批
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
        logger.info("已引导用户打开系统设置 > 登录项")
    }

    /// Helper 是否处于可用状态
    public var isHelperReady: Bool {
        helperStatus == .enabled
    }

    /// Helper 是否需要用户在系统设置中审批
    public var isHelperRequiresApproval: Bool {
        helperStatus == .requiresApproval
    }

    /// Helper 状态的中文描述
    public var helperStatusDescription: String {
        switch helperStatus {
        case .notRegistered:
            "未注册"
        case .enabled:
            "已启用"
        case .requiresApproval:
            "需要审批"
        case .notFound:
            "未找到"
        @unknown default:
            "未知状态"
        }
    }

    // MARK: - 开机自启动

    /// 当前是否启用开机自启动
    public var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 切换开机自启动状态
    ///
    /// - Parameter enabled: true 启用，false 禁用
    public func setLaunchAtLogin(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("开机自启动已启用")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("开机自启动已禁用")
            }
        } catch {
            lastError = "开机自启动设置失败：\(error.localizedDescription)"
            logger.error("开机自启动设置失败: \(error.localizedDescription)")
        }
    }
}
