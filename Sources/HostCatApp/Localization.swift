import SwiftUI

/// HostCat 本地化字符串封装
///
/// 提供类型安全的本地化字符串访问，避免在 UI 代码中直接使用字符串字面量。
/// 所有 key 需同时在 en.lproj/Localizable.strings 和 zh-Hans.lproj/Localizable.strings 中定义。
enum L {
    // MARK: - App
    static let appName = localize("app.name")
    static let aboutHostCat = localize("app.menu.about")
    static let quitHostCat = localize("app.menu.quit")

    // MARK: - Menu Bar
    static let openHostCat = localize("menubar.open")
    static let quit = localize("menubar.quit")
    static let statusActive = localize("menubar.status.active")
    static let statusInactive = localize("menubar.status.inactive")
    static let statusDefault = localize("menubar.status.default")
    static let statusGroups = localize("menubar.status.groups")
    static let statusNoGroups = localize("menubar.status.no_groups")
    static let statusNodes = localize("menubar.status.nodes")
    static let statusNoActiveNodes = localize("menubar.status.no_active_nodes")
    static let statusLastApplied = localize("menubar.status.last_applied")
    static let statusNever = localize("menubar.status.never")
    static let statusJustNow = localize("menubar.status.just_now")
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
    static let sidebarDefault = localize("sidebar.default")
    static let sidebarGroups = localize("sidebar.groups")
    static let sidebarAddGroup = localize("sidebar.add_group")
    static let sidebarGroupOptions = localize("sidebar.group_options")
    static let sidebarRenameGroup = localize("sidebar.rename_group")
    static let sidebarDeleteGroup = localize("sidebar.delete_group")
    static let sidebarMoveUp = localize("sidebar.move_up")
    static let sidebarMoveDown = localize("sidebar.move_down")
    static let sidebarAddNode = localize("sidebar.add_node")
    static let sidebarNodeOptions = localize("sidebar.node_options")
    static let sidebarRenameNode = localize("sidebar.rename_node")
    static let sidebarDeleteNode = localize("sidebar.delete_node")
    static let sidebarActivate = localize("sidebar.activate")
    static let sidebarDeactivate = localize("sidebar.deactivate")
    static let sidebarSingleSelect = localize("sidebar.single_select")
    static let sidebarMultiSelect = localize("sidebar.multi_select")
    static let sidebarEmptyState = localize("sidebar.empty_state")
    static let sidebarDragHint = localize("sidebar.drag_hint")

    // MARK: - Editor
    static let editorTitle = localize("editor.title")
    static let editorDefaultNode = localize("editor.default_node")
    static let editorNodeEditor = localize("editor.node_editor")
    static let editorPlaceholder = localize("editor.placeholder")
    static let editorApply = localize("editor.apply")
    static let editorApplyTooltip = localize("editor.apply_tooltip")
    static let editorDiscard = localize("editor.discard")
    static let editorDiscardTooltip = localize("editor.discard_tooltip")
    static let editorPreview = localize("editor.preview")
    static let editorPreviewTooltip = localize("editor.preview_tooltip")
    static let editorErrors = localize("editor.errors")
    static let editorLine = localize("editor.line")
    static let editorErrorIPInvalid = localize("editor.error.ip_invalid")
    static let editorErrorHostnameMissing = localize("editor.error.hostname_missing")
    static let editorErrorHostnameInvalid = localize("editor.error.hostname_invalid")
    static let editorSaved = localize("editor.saved")
    static let editorUnsaved = localize("editor.unsaved")
    static let editorParsing = localize("editor.parsing")
    static let editorNoErrors = localize("editor.no_errors")
    static func editorRecordsCount(_ count: Int) -> String {
        String(format: localize("editor.records_count"), count)
    }
    static func editorDuplicatesCount(_ count: Int) -> String {
        String(format: localize("editor.duplicates_count"), count)
    }

    // MARK: - Preview
    static let previewTitle = localize("preview.title")
    static let previewMergedHosts = localize("preview.merged_hosts")
    static let previewRecords = localize("preview.records")
    static let previewDuplicates = localize("preview.duplicates")
    static let previewConflicts = localize("preview.conflicts")
    static let previewNoConflicts = localize("preview.no_conflicts")
    static let previewCopy = localize("preview.copy")
    static let previewCopied = localize("preview.copied")
    static let previewClose = localize("preview.close")

    // MARK: - Helper Setup
    static let helperTitle = localize("helper.title")
    static let helperDescription = localize("helper.description")
    static let helperInstall = localize("helper.install")
    static let helperReinstall = localize("helper.reinstall")
    static let helperStatusInstalled = localize("helper.status.installed")
    static let helperStatusNotInstalled = localize("helper.status.not_installed")
    static let helperStatusChecking = localize("helper.status.checking")
    static let helperErrorInstallFailed = localize("helper.error.install_failed")
    static let helperErrorNotRegistered = localize("helper.error.not_registered")

    // MARK: - Backup & Restore
    static let backupTitle = localize("backup.title")
    static let backupDescription = localize("backup.description")
    static let backupCreate = localize("backup.create")
    static let backupRestore = localize("backup.restore")
    static let backupDelete = localize("backup.delete")
    static let backupNoBackups = localize("backup.no_backups")
    static let backupConfirmRestore = localize("backup.confirm_restore")
    static let backupConfirmDelete = localize("backup.confirm_delete")
    static let backupRestored = localize("backup.restored")
    static let backupCreated = localize("backup.created")
    static let backupDeleted = localize("backup.deleted")

    // MARK: - External Modification Alert
    static let alertExternalModificationTitle = localize("alert.external_modification.title")
    static let alertExternalModificationMessage = localize("alert.external_modification.message")
    static let alertExternalModificationReload = localize("alert.external_modification.reload")
    static let alertExternalModificationIgnore = localize("alert.external_modification.ignore")

    // MARK: - Dialogs
    static let dialogOK = localize("dialog.ok")
    static let dialogCancel = localize("dialog.cancel")
    static let dialogSave = localize("dialog.save")
    static let dialogDelete = localize("dialog.delete")
    static let dialogRename = localize("dialog.rename")
    static let dialogAdd = localize("dialog.add")
    static let dialogCreate = localize("dialog.create")
    static let dialogNamePlaceholder = localize("dialog.name_placeholder")
    static let dialogConfirmDelete = localize("dialog.confirm_delete")
    static let dialogConfirmDiscard = localize("dialog.confirm_discard")

    // MARK: - Errors
    static let errorGeneric = localize("error.generic")
    static let errorWriteFailed = localize("error.write_failed")
    static let errorMergeFailed = localize("error.merge_failed")
    static let errorConflicts = localize("error.conflicts")
    static let errorParserEmptyContent = localize("error.parser.empty_content")
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
    static let dnsRefreshSuccess = localize("dns.refresh.success")
    static let dnsRefreshFailed = localize("dns.refresh.failed")

    // MARK: - Config
    static let configLoadFailed = localize("config.load.failed")
    static let configSaveFailed = localize("config.save.failed")
    static let configRecovered = localize("config.recovered")

    // MARK: - Private

    private static func localize(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }
}

// MARK: - SwiftUI Text 便捷扩展

extension Text {
    init(_ localized: L.Type, keyPath: KeyPath<L.Type, String>) {
        self.init(localized[keyPath: keyPath])
    }
}
