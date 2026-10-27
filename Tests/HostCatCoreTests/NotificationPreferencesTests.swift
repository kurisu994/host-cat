import XCTest
@testable import HostCatCore

final class NotificationPreferencesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "HostCatTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsNotifyOnFailureAndExternalModificationButNotSuccess() {
        let prefs = NotificationPreferences.load(from: makeDefaults())

        XCTAssertFalse(prefs.shouldNotify(for: .applied))
        XCTAssertTrue(prefs.shouldNotify(for: .failed("x")))
        XCTAssertTrue(prefs.shouldNotify(for: .appliedWithWarning("x")))
        XCTAssertTrue(prefs.shouldNotify(for: .externalModification))
    }

    /// 写入成功但有警告（如 DNS 未确认刷新）属于需要用户留意的问题，跟随「失败时通知」开关。
    func testAppliedWithWarningFollowsFailurePreference() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NotificationPreferences.notifyOnFailureKey)

        let prefs = NotificationPreferences.load(from: defaults)

        XCTAssertFalse(prefs.shouldNotify(for: .appliedWithWarning("x")))
    }

    func testLoadReadsStoredValues() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: NotificationPreferences.notifyOnSuccessKey)
        defaults.set(false, forKey: NotificationPreferences.notifyOnFailureKey)
        defaults.set(false, forKey: NotificationPreferences.notifyOnExternalModificationKey)

        let prefs = NotificationPreferences.load(from: defaults)

        XCTAssertTrue(prefs.shouldNotify(for: .applied))
        XCTAssertFalse(prefs.shouldNotify(for: .failed("x")))
        XCTAssertFalse(prefs.shouldNotify(for: .externalModification))
    }
}
