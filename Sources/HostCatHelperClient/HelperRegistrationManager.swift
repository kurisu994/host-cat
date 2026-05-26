import Combine
import Foundation
import HostCatCore
import ServiceManagement
import os.log

/// Helper registration and launch-at-login management.
///
/// Responsibilities:
/// 1. Privileged Helper `SMAppService.daemon` registration, status detection, and approval guidance.
/// 2. Main app `SMAppService.mainApp` launch-at-login management.
@MainActor
public final class HelperRegistrationManager: ObservableObject {
    /// Helper daemon registration status.
    @Published public var helperStatus: SMAppService.Status = .notRegistered
    /// Error message from the most recent operation.
    @Published public var lastError: String?

    private let helperService: SMAppService
    private let logger = Logger(subsystem: "com.hostcat.app", category: "HelperRegistrationManager")

    public init() {
        helperService = SMAppService.daemon(plistName: "com.hostcat.helper.plist")
        refreshHelperStatus()
    }

    // MARK: - Helper Registration

    /// Registers the Privileged Helper.
    ///
    /// On first registration, macOS creates an approval entry in System Settings > Login Items,
    /// which the user must enable for the Helper to work.
    public func registerHelper() {
        lastError = nil
        do {
            try helperService.register()
            refreshHelperStatus()
            logger.info("Helper registered successfully, current status: \(String(describing: self.helperStatus))")
        } catch {
            lastError = LC.helperRegisterFailed + "：\(error.localizedDescription)"
            logger.error("Helper registration failed: \(error.localizedDescription)")
            refreshHelperStatus()
        }
    }

    /// Refreshes the Helper registration status.
    public func refreshHelperStatus() {
        helperStatus = helperService.status
        logger.debug("Helper status: \(String(describing: self.helperStatus))")
    }

    /// Opens System Settings to guide the user through approval.
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
        logger.info("Guided user to open System Settings > Login Items")
    }

    /// Whether the Helper is in an available state.
    public var isHelperReady: Bool {
        helperStatus == .enabled
    }

    /// Whether the Helper requires user approval in System Settings.
    public var isHelperRequiresApproval: Bool {
        helperStatus == .requiresApproval
    }

    /// Localized description of the Helper status.
    public var helperStatusDescription: String {
        switch helperStatus {
        case .notRegistered:
            LC.helperStatusNotRegistered
        case .enabled:
            LC.helperStatusEnabled
        case .requiresApproval:
            LC.helperStatusRequiresApproval
        case .notFound:
            LC.helperStatusNotFound
        @unknown default:
            LC.errorUnknown
        }
    }

    // MARK: - Launch at Login

    /// Whether launch-at-login is currently enabled.
    public var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggles launch-at-login state.
    ///
    /// - Parameter enabled: true to enable, false to disable.
    public func setLaunchAtLogin(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Launch at login enabled")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Launch at login disabled")
            }
        } catch {
            lastError = LC.launchAtLoginFailed + "：\(error.localizedDescription)"
            logger.error("Launch at login setting failed: \(error.localizedDescription)")
        }
    }
}
