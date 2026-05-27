import Foundation

/// Localization string wrapper for the HostCat Core module.
///
/// The Core module does not depend on SwiftUI; it uses Foundation's NSLocalizedString for localization.
/// SwiftPM resources live in `Bundle.module`; Xcode framework resources live in the framework bundle.
public enum LC {
    // MARK: - Model Defaults
    public static var defaultNodeName: String { localize("default.node_name") }

    // MARK: - Parser Errors
    public static func parserInvalidIPAddress(lineNumber: Int, value: String) -> String {
        String(format: localize("error.parser.invalid_ip"), lineNumber, value)
    }

    public static func parserMissingHostname(lineNumber: Int) -> String {
        String(format: localize("error.parser.missing_hostname"), lineNumber)
    }

    public static func parserInvalidHostname(lineNumber: Int, value: String) -> String {
        String(format: localize("error.parser.invalid_hostname"), lineNumber, value)
    }

    public static var parserEmptyContent: String { localize("error.parser.empty_content") }

    // MARK: - Write Errors
    public static var writeErrorFileImmutable: String { localize("write.error.file_immutable") }
    public static var writeErrorHashMismatch: String { localize("write.error.hash_mismatch") }
    public static func writeErrorContentValidationFailed(_ detail: String) -> String {
        String(format: localize("write.error.content_validation_failed"), detail)
    }
    public static func writeErrorTempFileCreationFailed(_ detail: String) -> String {
        String(format: localize("write.error.temp_file_creation_failed"), detail)
    }
    public static func writeErrorWriteFailed(_ detail: String) -> String {
        String(format: localize("write.error.write_failed"), detail)
    }
    public static func writeErrorRenameFailed(_ detail: String) -> String {
        String(format: localize("write.error.rename_failed"), detail)
    }
    public static func writeErrorPermissionSetFailed(_ detail: String) -> String {
        String(format: localize("write.error.permission_set_failed"), detail)
    }
    public static func writeErrorDNSRefreshFailed(_ detail: String) -> String {
        String(format: localize("write.error.dns_refresh_failed"), detail)
    }

    // MARK: - Backup Errors
    public static var backupErrorDirectoryCreationFailed: String { localize("backup.error.directory_creation_failed") }
    public static var backupErrorWriteFailed: String { localize("backup.error.write_failed") }
    public static var backupErrorCleanupFailed: String { localize("backup.error.cleanup_failed") }

    // MARK: - Config Errors
    public static func configErrorUnsupportedVersion(_ version: Int) -> String {
        String(format: localize("config.error.unsupported_version"), version)
    }
    public static func configErrorAtomicReplaceFailed(errno: Int32) -> String {
        String(format: localize("config.error.atomic_replace_failed"), errno)
    }
    public static var configErrorInvalidJSON: String { localize("config.error.invalid_json") }

    // MARK: - Recovery Reasons
    public static var recoveryInvalidJSON: String { localize("recovery.invalid_json") }
    public static func recoveryUnsupportedVersion(_ version: Int) -> String {
        String(format: localize("recovery.unsupported_version"), version)
    }

    // MARK: - Logger Messages
    public static func logMergeSuccess(records: Int, duplicates: Int) -> String {
        String(format: localize("log.merge_success"), records, duplicates)
    }
    public static func logMergeConflicts(count: Int) -> String {
        String(format: localize("log.merge_conflicts"), count)
    }
    public static func logMergeFailed(_ message: String) -> String {
        String(format: localize("log.merge_failed"), message)
    }
    public static func logWriteSuccess(hashPrefix: String) -> String {
        String(format: localize("log.write_success"), hashPrefix)
    }
    public static func logWriteFailed(_ message: String) -> String {
        String(format: localize("log.write_failed"), message)
    }
    public static func logBackupCreated(_ filename: String) -> String {
        String(format: localize("log.backup_created"), filename)
    }
    public static func logBackupFailed(_ message: String) -> String {
        String(format: localize("log.backup_failed"), message)
    }
    public static func logBackupCleaned(_ filename: String) -> String {
        String(format: localize("log.backup_cleaned"), filename)
    }
    public static func logBackupCleanFailed(_ filename: String) -> String {
        String(format: localize("log.backup_clean_failed"), filename)
    }

    // MARK: - Helper Messages
    public static var helperNotInstalled: String { localize("helper.not_installed") }
    public static var helperConnectionFailed: String { localize("helper.connection_failed") }
    public static var helperRegistrationFailed: String { localize("helper.registration_failed") }
    public static var helperAuthenticationFailed: String { localize("helper.authentication_failed") }
    public static func helperUnavailable(_ reason: String) -> String {
        String(format: localize("helper.unavailable"), reason)
    }
    public static var helperNotRegistered: String { localize("helper.not_registered") }
    public static var helperRequiresApproval: String { localize("helper.requires_approval") }
    public static var helperConnectionInterrupted: String { localize("helper.connection_interrupted") }
    public static var helperConnectionInvalidated: String { localize("helper.connection_invalidated") }
    public static var helperRequestTimedOut: String { localize("helper.request_timed_out") }
    public static func helperUnexpectedReply(_ detail: String) -> String {
        String(format: localize("helper.unexpected_reply"), detail)
    }
    public static var helperProxyUnavailable: String { localize("helper.proxy_unavailable") }
    public static var helperReplyMissingSuccess: String { localize("helper.reply_missing_success") }
    public static var helperReplyMissingFinalHash: String { localize("helper.reply_missing_final_hash") }

    // MARK: - MenuBarViewModel Messages
    public static var configSaveFailed: String { localize("menubar.config_save_failed") }
    public static var externalModificationDetected: String { localize("menubar.external_modification") }
    public static func conflictsDetected(_ count: Int) -> String {
        String(format: localize("menubar.conflicts_detected"), count)
    }
    public static func hostsNotApplied(_ message: String) -> String {
        String(format: localize("menubar.hosts_not_applied"), message)
    }

    // MARK: - Logger Messages (MenuBarViewModel)
    public static var logConfigPersistSuccess: String { localize("log.config_persist_success") }
    public static func logConfigPersistFailed(_ message: String) -> String {
        String(format: localize("log.config_persist_failed"), message)
    }
    public static var logDraftPersistSuccess: String { localize("log.draft_persist_success") }
    public static func logDraftPersistFailed(_ message: String) -> String {
        String(format: localize("log.draft_persist_failed"), message)
    }
    public static func logMergePreview(_ records: Int, _ duplicates: Int) -> String {
        String(format: localize("log.merge_preview"), records, duplicates)
    }
    public static func logPreviewConflicts(_ count: Int) -> String {
        String(format: localize("log.preview_conflicts"), count)
    }
    public static func logPreviewMergeFailed(_ message: String) -> String {
        String(format: localize("log.preview_merge_failed"), message)
    }
    public static var logExternalModification: String { localize("log.external_modification") }
    public static func logApplyFailed(_ prefix: String, _ message: String) -> String {
        String(format: localize("log.apply_failed"), prefix, message)
    }

    // MARK: - HelperRegistrationManager Messages
    public static var helperStatusNotRegistered: String { localize("helper.status.not_registered") }
    public static var helperStatusEnabled: String { localize("helper.status.enabled") }
    public static var helperStatusRequiresApproval: String { localize("helper.status.requires_approval") }
    public static var helperStatusNotFound: String { localize("helper.status.not_found") }
    public static func helperRegisterFailed(_ detail: String) -> String {
        String(format: localize("helper.register_failed"), detail)
    }
    public static func launchAtLoginFailed(_ detail: String) -> String {
        String(format: localize("helper.launch_at_login_failed"), detail)
    }
    public static var errorUnknown: String { localize("error.unknown") }

    // MARK: - Resource Resolution

    static func localizedString(
        _ key: String,
        userDefaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        localizedString(
            key,
            language: AppLanguage.stored(in: userDefaults),
            preferredLanguages: preferredLanguages
        )
    }

    static func localizedString(
        _ key: String,
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let bundle = language.localizedBundle(
            in: resourceBundle,
            preferredLanguages: preferredLanguages
        )
        return bundle.localizedString(forKey: key, value: key, table: "LocalizableCore")
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: HostCatCoreBundleToken.self)
        #endif
    }

    private static func localize(_ key: String) -> String {
        localizedString(key)
    }
}

private final class HostCatCoreBundleToken {}
