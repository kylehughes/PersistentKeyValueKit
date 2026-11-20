//
//  MigrationConcurrencyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

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

// `gateLock` protects `blockNext`; the backing store and semaphores provide their own synchronization.
// Semaphore waits and backing-store operations run after releasing `gateLock`.
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

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        false
    }

    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        base.migrationKeyIdentity(keyID)
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

extension GateMigrationStore: ForwardingPersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        .init(backend: self)
    }
}

private enum TestError: Error {
    case timeout
}

final class MigrationConcurrencyTests: XCTestCase {
    // MARK: Tests

    func test_disjointKey_canMigrateWhileAnotherKeyIsBlocked() throws {
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
        let finished = DispatchGroup()
        finished.enter()

        DispatchQueue.global().async {
            defer {
                finished.leave()
            }

            result.store(
                Result {
                    try source.copy(blocked, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
                }
            )
        }

        defer {
            resume.signal()
            XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        }

        guard entered.wait(timeout: .now() + 5) == .success else {
            return XCTFail("Blocked migration did not enter")
        }

        let freeReport = try source.copy(free, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertFalse(freeReport.hasFailures)
        XCTAssertEqual(destination.get(free), 2)
        resume.signal()

        guard finished.wait(timeout: .now() + 5) == .success else {
            return XCTFail("Blocked migration did not finish")
        }

        guard let firstResult = result.load(), case .success(let firstReport) = firstResult else {
            return XCTFail("blocked migration failed")
        }

        XCTAssertFalse(firstReport.hasFailures)
    }

    func test_sameKeyOverlap_isRejectedAndRetrySucceeds() throws {
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
        let finished = DispatchGroup()
        finished.enter()

        DispatchQueue.global().async {
            defer {
                finished.leave()
            }

            result.store(
                Result {
                    try workerSource.copy(
                        workerKey,
                        to: workerDestination,
                        onConflict: .overwriteDestination,
                        tracking: .untracked
                    )
                }
            )
        }

        defer {
            resume.signal()
            XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        }

        guard entered.wait(timeout: .now() + 5) == .success else {
            return XCTFail("First migration did not enter")
        }

        XCTAssertThrowsError(
            try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
        ) { error in
            XCTAssertEqual(error as? PersistentKeyMigrationError, .overlappingMigration)
        }

        resume.signal()

        guard finished.wait(timeout: .now() + 5) == .success else {
            return XCTFail("First migration did not finish")
        }

        guard let firstResult = result.load(), case .success(let firstReport) = firstResult else {
            return XCTFail("first migration failed")
        }

        XCTAssertFalse(firstReport.hasFailures)
        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked))
    }

    func test_sharedCompletionMarker_overlapsDisjointMigrations() throws {
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
        let finished = DispatchGroup()
        finished.enter()

        DispatchQueue.global().async {
            defer {
                finished.leave()
            }

            result.store(
                Result {
                    try firstSource.copy(
                        firstKey,
                        to: firstDestination,
                        onConflict: .overwriteDestination,
                        tracking: .once(id: id, recordedIn: recorder)
                    )
                }
            )
        }

        defer {
            resume.signal()
            XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        }

        guard entered.wait(timeout: .now() + 5) == .success else {
            return XCTFail("Tracked migration did not enter")
        }

        XCTAssertThrowsError(
            try secondSource.copy(
                secondKey,
                to: secondDestination,
                onConflict: .overwriteDestination,
                tracking: .once(id: id, recordedIn: recorder)
            )
        ) { error in
            XCTAssertEqual(error as? PersistentKeyMigrationError, .overlappingMigration)
        }

        resume.signal()

        guard finished.wait(timeout: .now() + 5) == .success else {
            return XCTFail("Tracked migration did not finish")
        }

        guard let firstResult = result.load(), case .success(let firstReport) = firstResult else {
            return XCTFail("tracked migration failed")
        }

        XCTAssertFalse(firstReport.hasFailures)
    }
}
