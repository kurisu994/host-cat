import HostCatCore
import SwiftUI

/// HostCat localization string wrapper.
///
/// Provides type-safe access to localized strings, avoiding raw string literals in UI code.
/// All keys must be defined in `Resources/Localizable.xcstrings` with both `en` and `zh-Hans` localizations.
enum L {
    // MARK: - App
    static var appName: String { localize("app.name") }
    static var aboutHostCat: String { localize("app.menu.about") }
    static var quitHostCat: String { localize("app.menu.quit") }

    // MARK: - Menu Bar
    static var openHostCat: String { localize("menubar.open") }
    static var quit: String { localize("menubar.quit") }
    static var statusActive: String { localize("menubar.status.active") }
    static var statusInactive: String { localize("menubar.status.inactive") }
    static var statusDefault: String { localize("menubar.status.default") }
    static var statusGroups: String { localize("menubar.status.groups") }
    static var statusNoGroups: String { localize("menubar.status.no_groups") }
    static var statusNodes: String { localize("menubar.status.nodes") }
    static var statusNoActiveNodes: String { localize("menubar.status.no_active_nodes") }
    static var statusLastApplied: String { localize("menubar.status.last_applied") }
    static var statusNever: String { localize("menubar.status.never") }
    static var statusJustNow: String { localize("menubar.status.just_now") }
    static func statusMinutesAgo(_ count: Int) -> String {
        String(format: localize("menubar.status.minutes_ago"), count)
    }
    static func statusHoursAgo(_ count: Int) -> String {
        String(format: localize("menubar.status.hours_ago"), count)
    }
    static func statusDaysAgo(_ count: Int) -> String {
        String(format: localize("menubar.status.days_ago"), count)
    }
    static func nodesCount(_ count: Int) -> String {
        String(format: localize("menubar.status.nodes_count"), count)
    }
    static func activeNodesCount(_ count: Int) -> String {
        String(format: localize("menubar.status.active_nodes_count"), count)
    }

    // MARK: - Sidebar
    static var sidebarDefault: String { localize("sidebar.default") }
    static var sidebarGroups: String { localize("sidebar.groups") }
    static var sidebarAddGroup: String { localize("sidebar.add_group") }
    static var sidebarGroupOptions: String { localize("sidebar.group_options") }
    static var sidebarRenameGroup: String { localize("sidebar.rename_group") }
    static var sidebarDeleteGroup: String { localize("sidebar.delete_group") }
    static var sidebarMoveUp: String { localize("sidebar.move_up") }
    static var sidebarMoveDown: String { localize("sidebar.move_down") }
    static var sidebarAddNode: String { localize("sidebar.add_node") }
    static var sidebarNodeOptions: String { localize("sidebar.node_options") }
    static var sidebarRenameNode: String { localize("sidebar.rename_node") }
    static var sidebarDeleteNode: String { localize("sidebar.delete_node") }
    static var sidebarActivate: String { localize("sidebar.activate") }
    static var sidebarDeactivate: String { localize("sidebar.deactivate") }
    static var sidebarSingleSelect: String { localize("sidebar.single_select") }
    static var sidebarMultiSelect: String { localize("sidebar.multi_select") }
    static var sidebarEmptyState: String { localize("sidebar.empty_state") }
    static var sidebarDragHint: String { localize("sidebar.drag_hint") }
    static var sidebarSearch: String { localize("sidebar.search") }
    static var sidebarSearchPlaceholder: String { localize("sidebar.search_placeholder") }
    static var sidebarNoResults: String { localize("sidebar.no_results") }
    static var sidebarNoResultsHint: String { localize("sidebar.no_results_hint") }

    // MARK: - Editor
    static var editorTitle: String { localize("editor.title") }
    static var editorDefaultNode: String { localize("editor.default_node") }
    static var editorNodeEditor: String { localize("editor.node_editor") }
    static var editorPlaceholder: String { localize("editor.placeholder") }
    static var editorApply: String { localize("editor.apply") }
    static var editorApplyTooltip: String { localize("editor.apply_tooltip") }
    static var editorDiscard: String { localize("editor.discard") }
    static var editorDiscardTooltip: String { localize("editor.discard_tooltip") }
    static var editorPreview: String { localize("editor.preview") }
    static var editorPreviewTooltip: String { localize("editor.preview_tooltip") }
    static var editorErrors: String { localize("editor.errors") }
    static var editorLine: String { localize("editor.line") }
    static var editorErrorIPInvalid: String { localize("editor.error.ip_invalid") }
    static var editorErrorHostnameMissing: String { localize("editor.error.hostname_missing") }
    static var editorErrorHostnameInvalid: String { localize("editor.error.hostname_invalid") }
    static var editorSaved: String { localize("editor.saved") }
    static var editorUnsaved: String { localize("editor.unsaved") }
    static var editorParsing: String { localize("editor.parsing") }
    static var editorApplying: String { localize("editor.applying") }
    static var editorNoErrors: String { localize("editor.no_errors") }
    static var editorSelectNode: String { localize("editor.select_node") }
    static func editorRecordsCount(_ count: Int) -> String {
        String(format: localize("editor.records_count"), count)
    }
    static func editorDuplicatesCount(_ count: Int) -> String {
        String(format: localize("editor.duplicates_count"), count)
    }
    static func editorSyntaxErrorsCount(_ count: Int) -> String {
        String(format: localize("editor.syntax_errors_count"), count)
    }
    static func editorCharactersCount(_ count: Int) -> String {
        String(format: localize("editor.characters_count"), count)
    }

    // MARK: - Preview
    static var previewTitle: String { localize("preview.title") }
    static var previewMergedHosts: String { localize("preview.merged_hosts") }
    static var previewRecords: String { localize("preview.records") }
    static var previewDuplicates: String { localize("preview.duplicates") }
    static var previewConflicts: String { localize("preview.conflicts") }
    static var previewNoConflicts: String { localize("preview.no_conflicts") }
    static var previewCopy: String { localize("preview.copy") }
    static var previewCopied: String { localize("preview.copied") }
    static var previewClose: String { localize("preview.close") }
    static var previewRefresh: String { localize("preview.refresh") }
    static var previewApply: String { localize("preview.apply") }
    static var previewNoContent: String { localize("preview.no_content") }
    static var previewConflictHint: String { localize("preview.conflict_hint") }
    static var previewExisting: String { localize("preview.existing") }
    static var previewConflicting: String { localize("preview.conflicting") }
    static var previewShowConflictDetails: String { localize("preview.show_conflict_details") }
    static func previewMergedDuplicatesCount(_ count: Int) -> String {
        String(format: localize("preview.merged_duplicates_count"), count)
    }
    static func previewConflictsCount(_ count: Int) -> String {
        String(format: localize("preview.conflicts_count"), count)
    }
    static func previewConflictLocation(hostname: String, nodeName: String) -> String {
        String(format: localize("preview.conflict_location"), hostname, nodeName)
    }

    // MARK: - Helper Setup
    static var helperTitle: String { localize("helper.title") }
    static var helperDescription: String { localize("helper.description") }
    static var helperInstall: String { localize("helper.install") }
    static var helperReinstall: String { localize("helper.reinstall") }
    static var helperStatusInstalled: String { localize("helper.status.installed") }
    static var helperStatusNotInstalled: String { localize("helper.status.not_installed") }
    static var helperStatusChecking: String { localize("helper.status.checking") }
    static var helperErrorInstallFailed: String { localize("helper.error.install_failed") }
    static var helperErrorNotRegistered: String { localize("helper.error.not_registered") }

    // MARK: - Helper Setup View
    static var helperSetupTitle: String { localize("helper.setup.title") }
    static var helperSetupDescription: String { localize("helper.setup.description") }
    static var helperCurrentStatus: String { localize("helper.current_status") }
    static var helperRegister: String { localize("helper.register") }
    static var helperRegisterHint: String { localize("helper.register_hint") }
    static var helperPendingApproval: String { localize("helper.pending_approval") }
    static var helperOpenSettings: String { localize("helper.open_settings") }
    static var helperEnabled: String { localize("helper.enabled") }
    static var helperRecoveryRetry: String { localize("helper.recovery.retry") }
    static var helperRecoveryDismiss: String { localize("helper.recovery.dismiss") }

    // MARK: - Backup & Restore View
    static var backupHistory: String { localize("backup.history") }
    static var backupCreateManual: String { localize("backup.create_manual") }
    static var backupSelectPreview: String { localize("backup.select_preview") }
    static var backupRestoreThis: String { localize("backup.restore_this") }
    static func backupCreateFailed(_ detail: String) -> String {
        String(format: localize("backup.create_failed"), detail)
    }
    static func backupRestoreFailed(_ detail: String) -> String {
        String(format: localize("backup.restore_failed"), detail)
    }

    // MARK: - Errors (additional)
    static var errorUnknown: String { localize("error.unknown") }
    static var errorEmptyHosts: String { localize("error.empty_hosts") }
    static var errorReadBackupFailed: String { localize("error.read_backup_failed") }
    static var errorOverwrite: String { localize("error.overwrite") }
    static var errorExternalModification: String { localize("error.external_modification") }
    static var errorExternalModificationMessage: String { localize("error.external_modification.message") }

    // MARK: - Backup & Restore
    static var backupTitle: String { localize("backup.title") }
    static var backupDescription: String { localize("backup.description") }
    static var backupCreate: String { localize("backup.create") }
    static var backupRestore: String { localize("backup.restore") }
    static var backupDelete: String { localize("backup.delete") }
    static var backupNoBackups: String { localize("backup.no_backups") }
    static var backupConfirmRestore: String { localize("backup.confirm_restore") }
    static var backupConfirmDelete: String { localize("backup.confirm_delete") }
    static var backupRestored: String { localize("backup.restored") }
    static var backupCreated: String { localize("backup.created") }
    static var backupDeleted: String { localize("backup.deleted") }

    // MARK: - External Modification Alert
    static var alertExternalModificationTitle: String { localize("alert.external_modification.title") }
    static var alertExternalModificationMessage: String { localize("alert.external_modification.message") }
    static var alertExternalModificationReload: String { localize("alert.external_modification.reload") }
    static var alertExternalModificationIgnore: String { localize("alert.external_modification.ignore") }

    // MARK: - Dialogs
    static var dialogOK: String { localize("dialog.ok") }
    static var dialogDone: String { localize("dialog.done") }
    static var dialogCancel: String { localize("dialog.cancel") }
    static var dialogSave: String { localize("dialog.save") }
    static var dialogDelete: String { localize("dialog.delete") }
    static var dialogRename: String { localize("dialog.rename") }
    static var dialogAdd: String { localize("dialog.add") }
    static var dialogCreate: String { localize("dialog.create") }
    static var dialogNamePlaceholder: String { localize("dialog.name_placeholder") }
    static var dialogConfirmDelete: String { localize("dialog.confirm_delete") }
    static var dialogConfirmDiscard: String { localize("dialog.confirm_discard") }
    static var dialogDeleteNodeTitle: String { localize("dialog.delete_node.title") }
    static var dialogDeleteNodeMessage: String { localize("dialog.delete_node.message") }
    static var dialogDeleteGroupTitle: String { localize("dialog.delete_group.title") }
    static var dialogDeleteGroupMessage: String { localize("dialog.delete_group.message") }

    // MARK: - Errors
    static var errorGeneric: String { localize("error.generic") }
    static var errorWriteFailed: String { localize("error.write_failed") }
    static var errorMergeFailed: String { localize("error.merge_failed") }
    static var errorConflicts: String { localize("error.conflicts") }
    static var errorParserEmptyContent: String { localize("error.parser.empty_content") }
    static func errorParserInvalidIP(line: Int, value: String) -> String {
        String(format: localize("error.parser.invalid_ip"), line, value)
    }
    static func errorParserMissingHostname(line: Int) -> String {
        String(format: localize("error.parser.missing_hostname"), line)
    }
    static func errorParserInvalidHostname(line: Int, value: String) -> String {
        String(format: localize("error.parser.invalid_hostname"), line, value)
    }

    // MARK: - DNS
    static var dnsRefreshSuccess: String { localize("dns.refresh.success") }
    static var dnsRefreshFailed: String { localize("dns.refresh.failed") }

    // MARK: - Config
    static var configLoadFailed: String { localize("config.load.failed") }
    static var configSaveFailed: String { localize("config.save.failed") }
    static var configRecovered: String { localize("config.recovered") }

    // MARK: - Preview (additional)
    static func previewTruncated(_ lines: Int) -> String {
        String(format: localize("preview.truncated"), lines)
    }
    static var previewClickFull: String { localize("preview.click_full") }

    // MARK: - MenuBarViewModel
    static var externalModificationDetected: String { localize("external.modification.detected") }
    static var externalModificationConfirm: String { localize("external.modification.confirm") }
    static var configRecoveredPrompt: String { localize("config.recovered.prompt") }
    static var logDraftPersistSuccess: String { localize("log.draft.persist.success") }
    static var logDraftPersistFailed: String { localize("log.draft.persist.failed") }
    static var logMergeSuccess: String { localize("log.merge.success") }
    static var logMergeFailed: String { localize("log.merge.failed") }

    // MARK: - Helper Status
    static var helperStatusNotRegistered: String { localize("helper.status.not_registered") }
    static var helperStatusEnabled: String { localize("helper.status.enabled") }
    static var helperStatusDisabled: String { localize("helper.status.disabled") }
    static var helperStatusUnknown: String { localize("helper.status.unknown") }
    static var helperRegisterFailed: String { localize("helper.register.failed") }
    static var launchAtLoginFailed: String { localize("launchatlogin.failed") }

    // MARK: - Settings
    static var settingsTitle: String { localize("settings.title") }
    static var settingsGeneral: String { localize("settings.general") }
    static var settingsHelper: String { localize("settings.helper") }
    static var settingsConfigInfo: String { localize("settings.config_info") }
    static var settingsDiagnostics: String { localize("settings.diagnostics") }
    static var settingsDiagnosticsDescription: String { localize("settings.diagnostics.description") }
    static var settingsLaunchAtLogin: String { localize("settings.launch_at_login") }
    static var settingsVersion: String { localize("settings.version") }
    static var settingsRefresh: String { localize("settings.refresh") }
    static var settingsHelperStatus: String { localize("settings.helper_status") }
    static var settingsConfigVersion: String { localize("settings.config_version") }
    static var settingsDefaultNode: String { localize("settings.default_node") }
    static var settingsGroupCount: String { localize("settings.group_count") }
    static var settingsLanguage: String { localize("settings.language") }
    static var languageSystem: String { localize("settings.language.system") }
    static var languageSimplifiedChinese: String { localize("settings.language.simplified_chinese") }
    static var languageEnglish: String { localize("settings.language.english") }
    static var settingsExportDiagnosticLogs: String { localize("settings.export_diagnostic_logs") }
    static var settingsExportingDiagnostics: String { localize("settings.exporting_diagnostics") }
    static func settingsDiagnosticExportSuccess(recordCount: Int, filename: String) -> String {
        String(format: localize("settings.diagnostic_export.success"), recordCount, filename)
    }
    static func settingsDiagnosticExportFailed(_ message: String) -> String {
        String(format: localize("settings.diagnostic_export.failed"), message)
    }

    // MARK: - Shortcuts
    static var settingsShortcuts: String { localize("settings.shortcuts") }
    static var settingsShortcutsDescription: String { localize("settings.shortcuts.description") }
    static var settingsShortcutToggleMenuBar: String { localize("settings.shortcut.toggle_menu_bar") }
    static var settingsShortcutToggleMenuBarHint: String { localize("settings.shortcut.toggle_menu_bar.hint") }

    // MARK: - Welcome / Privacy
    static var welcomeTitle: String { localize("welcome.title") }
    static var welcomeSubtitle: String { localize("welcome.subtitle") }
    static var welcomePointLocalTitle: String { localize("welcome.point.local.title") }
    static var welcomePointLocalBody: String { localize("welcome.point.local.body") }
    static var welcomePointHelperTitle: String { localize("welcome.point.helper.title") }
    static var welcomePointHelperBody: String { localize("welcome.point.helper.body") }
    static var welcomePointBackupTitle: String { localize("welcome.point.backup.title") }
    static var welcomePointBackupBody: String { localize("welcome.point.backup.body") }
    static var welcomePointDiagnosticsTitle: String { localize("welcome.point.diagnostics.title") }
    static var welcomePointDiagnosticsBody: String { localize("welcome.point.diagnostics.body") }
    static var welcomePrivacyButton: String { localize("welcome.privacy_button") }
    static var welcomeAcknowledge: String { localize("welcome.acknowledge") }
    static var welcomeFootnote: String { localize("welcome.footnote") }

    // MARK: - Private

    private static func localize(_ key: String) -> String {
        let bundle = AppLanguage.stored().localizedBundle(in: .main)
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

// MARK: - SwiftUI Text Convenience Extension

extension Text {
    init(_ localized: L.Type, keyPath: KeyPath<L.Type, String>) {
        self.init(localized[keyPath: keyPath])
    }
}
