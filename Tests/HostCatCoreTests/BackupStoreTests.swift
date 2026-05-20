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

    func testBackupNamingContainsTimestamp() {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 3)
        let content = "127.0.0.1 localhost"

        let backupURL = store.createBackup(content: content)

        XCTAssertNotNil(backupURL)
        let filename = backupURL!.lastPathComponent
        XCTAssertTrue(filename.hasPrefix("hosts_"))
        XCTAssertTrue(filename.hasSuffix(".bak"))
    }

    func testListBackupsSortedByDate() {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 5)

        _ = store.createBackup(content: "content1")
        Thread.sleep(forTimeInterval: 0.01)
        _ = store.createBackup(content: "content2")
        Thread.sleep(forTimeInterval: 0.01)
        _ = store.createBackup(content: "content3")

        let backups = store.listBackups()

        XCTAssertEqual(backups.count, 3)
        // 按时间倒序：最新的在前
        let dates = backups.compactMap { BackupStore.extractDate(from: $0) }
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testMaxBackupsEnforced() {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 2)

        _ = store.createBackup(content: "content1")
        Thread.sleep(forTimeInterval: 0.01)
        _ = store.createBackup(content: "content2")
        Thread.sleep(forTimeInterval: 0.01)
        _ = store.createBackup(content: "content3")

        let backups = store.listBackups()

        XCTAssertEqual(backups.count, 2)
    }

    func testReadBackupContent() {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 3)
        let content = "127.0.0.1 localhost\n::1 localhost"

        let backupURL = store.createBackup(content: content)
        XCTAssertNotNil(backupURL)

        let readContent = store.readBackup(at: backupURL!)
        XCTAssertEqual(readContent, content)
    }

    func testReadNonExistentBackupReturnsNil() {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 3)
        let fakeURL = tempDir.appendingPathComponent("hosts_2099-01-01_000000.bak")

        let readContent = store.readBackup(at: fakeURL)
        XCTAssertNil(readContent)
    }

    func testOldestBackupRemovedWhenExceedingMax() {
        let store = BackupStore(backupDirectory: tempDir, maxBackups: 2)

        let backup1 = store.createBackup(content: "oldest")
        Thread.sleep(forTimeInterval: 0.01)
        let backup2 = store.createBackup(content: "middle")
        Thread.sleep(forTimeInterval: 0.01)
        let backup3 = store.createBackup(content: "newest")

        let backups = store.listBackups()

        XCTAssertEqual(backups.count, 2)
        XCTAssertFalse(backups.contains(backup1!))
        XCTAssertTrue(backups.contains(backup2!) || backups.contains(backup3!))
    }
}
