import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationSetupValidationTests: XCTestCase {
    // MARK: Tests

    func testChainedRenameAcrossStoresIsAllowed() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let a = key(#function, "a")
        let b = key(#function, "b")
        let c = key(#function, "c")

        source.set(a, to: 1)
        source.set(b, to: 2)
        let report = try source.move(
            items: [.key(a, to: b), .key(b, to: c)],
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved])
        XCTAssertEqual(destination.get(b), 1)
        XCTAssertEqual(destination.get(c), 2)
    }

    func testDuplicateDestinationKeyIsRejected() throws {
        let source = MigrationFaultStore()
        let destination = MigrationFaultStore()
        let a = key(#function, "a")
        let b = key(#function, "b")
        let c = key(#function, "c")

        assertSetupError(
            .duplicateKey(c.id),
            try source.copy(
                items: [.key(a, to: c), .key(b, to: c)],
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [source, destination]
        )
    }

    func testDuplicateSourceKeyIsRejectedEvenWithDistinctDestinations() throws {
        let source = MigrationFaultStore()
        let destination = MigrationFaultStore()
        let a = key(#function, "a")
        let b = key(#function, "b")
        let c = key(#function, "c")

        assertSetupError(
            .duplicateKey(a.id),
            try source.move(
                items: [.key(a, to: b), .key(a, to: c)],
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [source, destination]
        )
        assertSetupError(
            .duplicateKey(a.id),
            try source.copy(
                items: [.key(a, to: b), .key(a, to: c)],
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [source, destination]
        )
    }

    func testEmptyBatchWithinOneStoreIsAllowed() throws {
        let store = InMemoryPersistentKeyValueStore()
        let report = try store.copy(items: [], to: store, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertTrue(report.outcomes.isEmpty)
        XCTAssertTrue(report.isComplete)
    }

    func testEmptyRecorderIdentityIsInternalInconsistency() throws {
        let source = MigrationFaultStore()
        let destination = MigrationFaultStore()
        let recorder = MigrationFaultStore(identifier: "")

        assertSetupError(
            .internalInconsistency,
            try source.copy(
                key(#function, "a"),
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: #function, recordedIn: recorder)
            ),
            stores: [source, destination, recorder]
        )
    }

    func testEmptyTrackingIdentifierIsRejectedForDestinationTracking() throws {
        let source = MigrationFaultStore()
        let destination = MigrationFaultStore()

        assertSetupError(
            .invalidMigrationIdentifier,
            try source.copy(
                key(#function, "a"),
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: "")
            ),
            stores: [source, destination]
        )
    }

    @available(watchOS 9.0, *)
    func testKeyIdentifierLimitIsCheckedAgainstTheStoreThatHoldsTheKey() throws {
        let memory = MigrationFaultStore()
        let cloud = UbiquitousKeyValueMigrationBackend(
            store: StrictMigrationUbiquitousStore(),
            identity: .init(namespace: "validation", identifier: UUID().uuidString)
        )
        let long = key(#function, String(repeating: "x", count: 129))
        let short = key(#function, "short")

        cloud.ubiquitousStore.set(Int64(1), forKey: short.id)
        assertSetupError(
            .keyIdentifierTooLong(long.id),
            try cloud.copy(
                items: [.key(short, to: short), .key(long, to: key(#function, "other"))],
                to: memory,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [memory]
        )
        XCTAssertNil(try memory.migrationSnapshot(for: short.id))
        assertSetupError(
            .keyIdentifierTooLong(long.id),
            try memory.copy(.key(short, to: long), to: cloud, onConflict: .overwriteDestination, tracking: .untracked),
            stores: [memory]
        )
        memory.set(long, to: 2)

        let fromLong = try memory.move(
            .key(long, to: short),
            to: cloud,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(fromLong.outcomes.map(\.status), [.moved])
        XCTAssertEqual(cloud.get(short), 2)

        let defaultsName = "MigrationSetupValidationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: defaultsName))

        defer {
            defaults.removePersistentDomain(forName: defaultsName)
        }

        cloud.set(short, to: 3)

        let toLong = try cloud.copy(
            .key(short, to: long),
            to: defaults,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(toLong.outcomes.map(\.status), [.copied])
        XCTAssertEqual(defaults.get(long), 3)
    }

    func testMarkerIdentifierLimitIsCheckedAgainstTheRecorder() throws {
        let source = MigrationFaultStore()
        let destination = MigrationFaultStore()
        let recorder = MigrationFaultStore()
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        let a = key(#function, "a")

        recorder.keyIDLimit = marker.id.count - 1
        assertSetupError(
            .keyIdentifierTooLong(marker.id),
            try source.copy(
                a,
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: #function, recordedIn: recorder)
            ),
            stores: [source, destination, recorder]
        )

        destination.keyIDLimit = marker.id.count - 1
        assertSetupError(
            .keyIdentifierTooLong(marker.id),
            try source.copy(a, to: destination, onConflict: .overwriteDestination, tracking: .once(id: #function)),
            stores: [source, destination]
        )

        let report = try source.copy(
            a,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: InMemoryPersistentKeyValueStore())
        )

        XCTAssertEqual(report.completion, .recorded)
    }

    func testOverlappingKeysWithinOneStoreAreRejected() throws {
        let store = MigrationFaultStore()
        let a = key(#function, "a")
        let b = key(#function, "b")
        let c = key(#function, "c")

        assertSetupError(
            .overlappingKeys(b.id),
            try store.move(
                items: [.key(a, to: b), .key(b, to: c)],
                to: store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [store]
        )
        assertSetupError(
            .overlappingKeys(b.id),
            try store.copy(
                items: [.key(b, to: c), .key(a, to: b)],
                to: store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [store]
        )
        assertSetupError(
            .overlappingKeys(b.id),
            try store.move(
                items: [.key(a, to: b), .key(b, to: a)],
                to: store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [store]
        )
    }

    func testRegistryClaimsSourceIDsInSourceAndDestinationIDsInDestination() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = MigrationFaultStore()
        let other = InMemoryPersistentKeyValueStore()
        let a = key(#function, "a")
        let b = key(#function, "b")
        var nested: [String: Result<PersistentKeyMigrationReport, any Error>] = [:]

        source.set(a, to: 1)
        other.set(a, to: 2)
        other.set(b, to: 3)
        destination.commitHook = { keyID in
            guard keyID == b.id, nested.isEmpty else {
                return
            }

            nested["destination.b"] = Result {
                try other.copy(b, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
            }
            nested["source.a"] = Result {
                try source.copy(a, to: other, onConflict: .overwriteDestination, tracking: .untracked)
            }
            nested["source.b"] = Result {
                try source.copy(b, to: other, onConflict: .overwriteDestination, tracking: .untracked)
            }
            nested["destination.a"] = Result {
                try other.copy(a, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
            }
        }

        let report = try source.copy(
            .key(a, to: b),
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.copied])
        XCTAssertThrowsError(try nested["destination.b"]?.get()) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .overlappingMigration)
        }
        XCTAssertThrowsError(try nested["source.a"]?.get()) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .overlappingMigration)
        }
        XCTAssertEqual(try nested["source.b"]?.get().outcomes.map(\.status), [.sourceAbsent])
        XCTAssertEqual(try nested["destination.a"]?.get().outcomes.map(\.status), [.copied])
        XCTAssertEqual(destination.get(a), 2)
        XCTAssertEqual(destination.get(b), 1)
    }

    func testReservedDestinationKeyIsRejected() throws {
        let source = MigrationFaultStore()
        let destination = MigrationFaultStore()
        let reserved = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        let flag = PersistentKey<Bool>("\(#function).flag", defaultValue: false)

        assertSetupError(
            .reservedKey(reserved.id),
            try source.copy(
                .key(flag, to: reserved),
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [source, destination]
        )
        assertSetupError(
            .reservedKey(reserved.id),
            try source.move(
                .key(reserved, to: flag),
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [source, destination]
        )
    }

    func testSameStoreIsRejectedWhenAnyItemMapsAKeyToItself() throws {
        let store = MigrationFaultStore()
        let a = key(#function, "a")
        let b = key(#function, "b")
        let c = key(#function, "c")

        assertSetupError(
            .sameStore,
            try store.copy(
                items: [.key(a, to: b), .key(c)],
                to: store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ),
            stores: [store]
        )
        assertSetupError(
            .sameStore,
            try store.move(.key(c, to: c), to: store, onConflict: .overwriteDestination, tracking: .untracked),
            stores: [store]
        )
    }

    // MARK: Private Instance Interface

    private func assertSetupError(
        _ expected: PersistentKeyMigrationError,
        _ expression: @autoclosure () throws -> PersistentKeyMigrationReport,
        stores: [MigrationFaultStore],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let accessCounts = stores.map(\.accessCount)

        XCTAssertThrowsError(try expression(), file: file, line: line) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, expected, file: file, line: line)
        }
        XCTAssertEqual(
            stores.map(\.accessCount),
            accessCounts,
            "Setup errors must precede store access",
            file: file,
            line: line
        )
    }

    private func key(_ function: String, _ name: String) -> PersistentKey<Int> {
        PersistentKey("\(function).\(name)", defaultValue: 0)
    }
}
