import Foundation
import XCTest
@testable import HostCatCore

final class AppLanguageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppLanguageTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStoredPreferenceDefaultsToSystemAndRoundTrips() {
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)

        AppLanguage.english.store(in: defaults)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .english)

        defaults.set("unsupported", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
    }

    func testEffectiveLocalizationUsesExplicitSelectionOrSupportedSystemLanguage() {
        XCTAssertEqual(
            AppLanguage.english.effectiveLocalizationIdentifier(preferredLanguages: ["zh-Hans"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.effectiveLocalizationIdentifier(preferredLanguages: ["en-US"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            AppLanguage.system.effectiveLocalizationIdentifier(preferredLanguages: ["en-US"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.system.effectiveLocalizationIdentifier(preferredLanguages: ["zh-Hans-CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            AppLanguage.system.effectiveLocalizationIdentifier(preferredLanguages: ["fr-FR"]),
            "zh-Hans"
        )
    }

    func testCoreLocalizationResolvesNewTextUsingStoredLanguageWithoutRestart() {
        AppLanguage.english.store(in: defaults)
        XCTAssertEqual(
            LC.localizedString("helper.status.enabled", userDefaults: defaults),
            "Enabled"
        )

        AppLanguage.simplifiedChinese.store(in: defaults)
        XCTAssertEqual(
            LC.localizedString("helper.status.enabled", userDefaults: defaults),
            "已启用"
        )
    }

    func testWriteErrorCanBeFormattedUsingRequestLanguage() {
        XCTAssertEqual(
            HostsWriteError.hashMismatch.description(in: .english),
            "The hosts file has been modified outside of HostCat."
        )
        XCTAssertEqual(
            HostsWriteError.hashMismatch.description(in: .simplifiedChinese),
            "hosts 文件已在 HostCat 之外被修改。"
        )
    }
}
