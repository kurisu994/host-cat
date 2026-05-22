import Foundation

/// HostCat App 与 Privileged Helper 之间使用的 code signing requirement。
public enum HostCatCodeSigningRequirements {
    public static let appBundleIdentifier = "com.hostcat.app"
    public static let helperBundleIdentifier = "com.hostcat.helper"
    public static let teamIdentifierInfoKey = "HostCatTeamIdentifier"

    private static let unconfiguredTeamIdentifier = "HOSTCAT_TEAM_ID_NOT_CONFIGURED"

    public static func appRequirement(teamIdentifier: String) -> String {
        fullRequirement(identifier: appBundleIdentifier, teamIdentifier: teamIdentifier)
    }

    public static func helperRequirement(teamIdentifier: String) -> String {
        fullRequirement(identifier: helperBundleIdentifier, teamIdentifier: teamIdentifier)
    }

    public static func teamIdentifier(from bundle: Bundle = .main) -> String {
        guard let value = bundle.object(forInfoDictionaryKey: teamIdentifierInfoKey) as? String else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fullRequirement(identifier: String, teamIdentifier: String) -> String {
        let normalizedTeamIdentifier = teamIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTeamIdentifier = normalizedTeamIdentifier.isEmpty
            ? unconfiguredTeamIdentifier
            : normalizedTeamIdentifier

        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(effectiveTeamIdentifier)\""
    }
}
