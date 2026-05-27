import Foundation

/// 应用界面支持的语言偏好；该偏好独立于 hosts 配置和备份数据。
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    /// `UserDefaults` 中保存界面语言偏好的键。
    public static let preferenceKey = "HostCat.appLanguage"

    private static let defaultLocalizationIdentifier = "zh-Hans"

    /// 从用户偏好读取语言；不存在或值不兼容时继续跟随系统。
    public static func stored(in userDefaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = userDefaults.string(forKey: preferenceKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }

        return language
    }

    /// 保存界面语言偏好。
    public func store(in userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.preferenceKey)
    }

    /// 返回本地化资源标识；系统不支持的语言回退到应用默认中文。
    public func effectiveLocalizationIdentifier(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        case .system:
            for rawIdentifier in preferredLanguages {
                let identifier = rawIdentifier
                    .replacingOccurrences(of: "_", with: "-")
                    .lowercased()

                if identifier == "en" || identifier.hasPrefix("en-") {
                    return "en"
                }

                if identifier == "zh"
                    || identifier == "zh-hans"
                    || identifier.hasPrefix("zh-hans-")
                    || identifier == "zh-cn"
                    || identifier.hasPrefix("zh-cn-")
                    || identifier == "zh-sg"
                    || identifier.hasPrefix("zh-sg-") {
                    return "zh-Hans"
                }
            }

            return Self.defaultLocalizationIdentifier
        }
    }

    /// SwiftUI 控件和格式化展示使用的有效 locale。
    public var locale: Locale {
        Locale(identifier: effectiveLocalizationIdentifier())
    }

    /// 在给定资源 bundle 中选择与当前偏好匹配的语言资源。
    public func localizedBundle(
        in baseBundle: Bundle,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bundle {
        let identifier = effectiveLocalizationIdentifier(preferredLanguages: preferredLanguages)
        guard let url = baseBundle.url(forResource: identifier, withExtension: "lproj"),
              let localizedBundle = Bundle(url: url) else {
            return baseBundle
        }

        return localizedBundle
    }
}
