import XCTest
@testable import HostCatCore

final class BackupStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testBackupNamingContainsTimestamp() throws {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 3)
        let content = "127.0.0.1 localhost"

        let backupURL = try store.createBackup(content: content)

        let filename = backupURL.lastPathComponent
        XCTAssertTrue(filename.hasPrefix("hosts_"))
        XCTAssertTrue(filename.hasSuffix(".bak"))
    }

    func testListBackupsSortedByDate() throws {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 5)

        _ = try store.createBackup(content: "content1")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.createBackup(content: "content2")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.createBackup(content: "content3")

        let backups = store.listBackups()

        XCTAssertEqual(backups.count, 3)
        // 按时间倒序：最新的在前
        let dates = backups.compactMap { BackupStore.extractDate(from: $0) }
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testMaxBackupsEnforced() throws {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 2)

        _ = try store.createBackup(content: "content1")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.createBackup(content: "content2")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.createBackup(content: "content3")

        let backups = store.listBackups()

        XCTAssertEqual(backups.count, 2)
    }

    func testReadBackupContent() throws {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 3)
        let content = "127.0.0.1 localhost\n::1 localhost"

        let backupURL = try store.createBackup(content: content)

        let readContent = store.readBackup(at: backupURL)
        XCTAssertEqual(readContent, content)
    }

    func testReadNonExistentBackupReturnsNil() {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 3)
        let fakeURL = tempDir.appendingPathComponent("hosts_2099-01-01_000000.bak")

        let readContent = store.readBackup(at: fakeURL)
        XCTAssertNil(readContent)
    }

    func testOldestBackupRemovedWhenExceedingMax() throws {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 2)

        let backup1 = try store.createBackup(content: "oldest")
        Thread.sleep(forTimeInterval: 0.01)
        let backup2 = try store.createBackup(content: "middle")
        Thread.sleep(forTimeInterval: 0.01)
        let backup3 = try store.createBackup(content: "newest")

        let backups = store.listBackups()
        let backupNames = Set(backups.map(\.lastPathComponent))

        XCTAssertEqual(backups.count, 2)
        XCTAssertFalse(backupNames.contains(backup1.lastPathComponent))
        XCTAssertTrue(backupNames.contains(backup2.lastPathComponent))
        XCTAssertTrue(backupNames.contains(backup3.lastPathComponent))
    }

    func testRapidBackupsUseUniqueNames() throws {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 5)

        let backup1 = try store.createBackup(content: "content1")
        let backup2 = try store.createBackup(content: "content2")
        let backup3 = try store.createBackup(content: "content3")

        XCTAssertEqual(Set([backup1.lastPathComponent, backup2.lastPathComponent, backup3.lastPathComponent]).count, 3)
        XCTAssertEqual(store.listBackups().count, 3)
    }
}
