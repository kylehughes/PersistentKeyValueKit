import Foundation
import XCTest

@testable import PersistentKeyValueKit

private final class MigrationResultBox: @unchecked Sendable {
    // The lock protects the result while the worker and test thread exchange it.
    private let lock = NSLock()
    private var value: Result<PersistentKeyMigrationReport, Error>?

    func load() -> Result<PersistentKeyMigrationReport, Error>? {
        lock.lock()

        defer {
            lock.unlock()
        }

        return value
    }

    func store(_ value: Result<PersistentKeyMigrationReport, Error>) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private final class GateMigrationStore: @unchecked Sendable {
    let base: InMemoryPersistentKeyValueStore
    let blockedKeyID: String
    let entered: DispatchSemaphore
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity
    let resume: DispatchSemaphore

    private let gateLock = NSLock()
    private var blockNext = true

    init(
        base: InMemoryPersistentKeyValueStore,
        blockedKeyID: String,
        entered: DispatchSemaphore,
        resume: DispatchSemaphore
    ) {
        self.base = base
        migrationIdentity = base.migrationIdentity
        self.blockedKeyID = blockedKeyID
        self.entered = entered
        self.resume = resume
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

extension GateMigrationStore: PersistentKeyValueMigrationBackend {
    typealias MigrationSnapshot = InMemoryPersistentKeyValueStore.MigrationSnapshot

    typealias MigrationWrite = InMemoryPersistentKeyValueStore.MigrationWrite

    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot? {
        gateLock.lock()
        let shouldBlock = write.keyID == blockedKeyID && blockNext

        if shouldBlock {
            blockNext = false
        }

        gateLock.unlock()
        if shouldBlock {
            entered.signal()

            guard resume.wait(timeout: .now() + 5) == .success else {
                throw TestError.timeout
            }
        }

        return try base.commitMigrationWrite(write, replacing: snapshot)
    }

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        try base.migrationSnapshot(for: keyID)
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        try base.migrationSnapshotIsCurrent(snapshot, for: keyID)
    }

    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value where Key: PersistentKeyProtocol {
        try base.migrationValue(for: key, in: snapshot)
    }

    func prepareMigrationWrite<Key>(
        _ value: Key.Value,
        for key: Key
    ) throws -> MigrationWrite where Key: PersistentKeyProtocol {
        try base.prepareMigrationWrite(value, for: key)
    }

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        try base.removeMigrationValue(for: keyID, matching: snapshot)
    }
}

// MARK: - PersistentKeyValueStore Extension

extension GateMigrationStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        .init(backend: self)
    }

    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        base.deregister(observer, for: key, context: context)
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        base.get(key)
    }

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        base.register(observer: observer, for: key, with: context, and: selector)
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        base.remove(key)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        base.set(key, to: value)
    }
}

private enum TestError: Error {
    case timeout
}

final class MigrationConcurrencyTests: XCTestCase {
    // MARK: Tests

    func testDisjointKeyCanMigrateWhileAnotherKeyIsBlocked() throws {
        let source = InMemoryPersistentKeyValueStore()
        let backing = InMemoryPersistentKeyValueStore()
        let blocked = PersistentKey<Int>("blocked-\(#function)", defaultValue: 0)
        let free = PersistentKey<Int>("free-\(#function)", defaultValue: 0)

        source.set(blocked, to: 1)
        source.set(free, to: 2)
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let destination = GateMigrationStore(
            base: backing,
            blockedKeyID: blocked.id,
            entered: entered,
            resume: resume
        )
        let result = MigrationResultBox()
        let finished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            defer {
                finished.signal()
            }

            result.store(
                Result {
                    try source.copy(blocked, to: destination, onConflict: .overwriteDestination)
                }
            )
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        defer {
            resume.signal()
        }

        let freeReport = try source.copy(free, to: destination, onConflict: .overwriteDestination)

        XCTAssertFalse(freeReport.hasFailures)
        XCTAssertEqual(destination.get(free), 2)
        resume.signal()

        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)

        guard let firstResult = result.load(), case .success(let firstReport) = firstResult else {
            return XCTFail("blocked migration failed")
        }

        XCTAssertFalse(firstReport.hasFailures)
    }

    func testSameKeyOverlapRejectedAndRetrySucceeds() throws {
        let source = InMemoryPersistentKeyValueStore()
        let backing = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 1)
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let destination = GateMigrationStore(
            base: backing,
            blockedKeyID: key.id,
            entered: entered,
            resume: resume
        )
        let result = MigrationResultBox()
        let workerSource = source
        let workerDestination = destination
        let workerKey = key
        let finished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            defer {
                finished.signal()
            }

            result.store(
                Result {
                    try workerSource.copy(workerKey, to: workerDestination, onConflict: .overwriteDestination)
                }
            )
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        defer {
            resume.signal()
        }

        XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: .overwriteDestination)) { error in
            XCTAssertEqual(error as? PersistentKeyMigrationError, .overlappingMigration)
        }

        resume.signal()

        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)

        guard let firstResult = result.load(), case .success(let firstReport) = firstResult else {
            return XCTFail("first migration failed")
        }

        XCTAssertFalse(firstReport.hasFailures)
        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .overwriteDestination))
    }

    func testSharedCompletionMarkerOverlapsDisjointMigrations() throws {
        let recorder = InMemoryPersistentKeyValueStore()
        let firstSource = InMemoryPersistentKeyValueStore()
        let secondSource = InMemoryPersistentKeyValueStore()
        let firstBacking = InMemoryPersistentKeyValueStore()
        let firstKey = PersistentKey<Int>("first-\(#function)", defaultValue: 0)
        let secondKey = PersistentKey<Int>("second-\(#function)", defaultValue: 0)

        firstSource.set(firstKey, to: 1)
        secondSource.set(secondKey, to: 2)
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let firstDestination = GateMigrationStore(
            base: firstBacking,
            blockedKeyID: firstKey.id,
            entered: entered,
            resume: resume
        )
        let secondDestination = InMemoryPersistentKeyValueStore()
        let id = #function
        let result = MigrationResultBox()
        let finished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            defer {
                finished.signal()
            }

            result.store(
                Result {
                    try firstSource.copy(
                        firstKey,
                        to: firstDestination,
                        onConflict: .overwriteDestination,
                        completion: .once(id: id, recordedIn: recorder)
                    )
                }
            )
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        defer {
            resume.signal()
        }

        XCTAssertThrowsError(
            try secondSource.copy(
                secondKey,
                to: secondDestination,
                onConflict: .overwriteDestination,
                completion: .once(id: id, recordedIn: recorder)
            )
        ) { error in
            XCTAssertEqual(error as? PersistentKeyMigrationError, .overlappingMigration)
        }

        resume.signal()

        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)

        guard let firstResult = result.load(), case .success(let firstReport) = firstResult else {
            return XCTFail("tracked migration failed")
        }

        XCTAssertFalse(firstReport.hasFailures)
    }
}
