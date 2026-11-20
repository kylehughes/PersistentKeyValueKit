//
//  MigrationSetupValidationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationSetupValidationTests: XCTestCase {
    // MARK: Tests

    func test_chainedRenameAcrossStores_isAllowed() throws {
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

    func test_duplicateDestinationKey_isRejected() throws {
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

    func test_duplicateSourceKey_isRejectedEvenWithDistinctDestinations() throws {
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

    func test_emptyBatchWithinOneStore_isAllowed() throws {
        let store = InMemoryPersistentKeyValueStore()
        let report = try store.copy(items: [], to: store, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertTrue(report.outcomes.isEmpty)
        XCTAssertTrue(report.isComplete)
    }

    func test_emptyRecorderIdentity_isInternalInconsistency() throws {
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

    func test_emptyTrackingIdentifier_isRejectedForDestinationTracking() throws {
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

    func test_keyIdentifierLimit_isCheckedAgainstTheStoreThatHoldsTheKey() throws {
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

        let defaultsName = stableSuiteName("MigrationSetupValidationTests")
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

    func test_markerIdentifierLimit_isCheckedAgainstTheRecorder() throws {
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

    func test_overlappingKeysWithinOneStore_areRejected() throws {
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

    func test_registry_claimsSourceIDsInSourceAndDestinationIDsInDestination() throws {
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

    func test_reservedDestinationKey_isRejected() throws {
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

    func test_reservedPrefixSpellings_areRejectedBeforeMutationInEveryStore() throws {
        let prefix = "PersistentKeyValueKit_MigrationCompleted_"
        let sourceSuiteName = stableSuiteName("MigrationSetupValidationTests.ReservedPrefix.Source")
        let destinationSuiteName = stableSuiteName("MigrationSetupValidationTests.ReservedPrefix.Destination")
        let defaultsSource = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceSuiteName))
        let defaultsDestination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationSuiteName))
        let ubiquitousSource = UbiquitousKeyValueMigrationBackend(
            store: StrictMigrationUbiquitousStore(),
            identity: .init(namespace: "reserved", identifier: "source")
        )
        let ubiquitousDestination = UbiquitousKeyValueMigrationBackend(
            store: StrictMigrationUbiquitousStore(),
            identity: .init(namespace: "reserved", identifier: "destination")
        )

        addTeardownBlock {
            for name in [sourceSuiteName, destinationSuiteName] {
                UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            }
        }

        // A combining mark or variation selector joins the prefix's final `_` into one character, and KELVIN SIGN is
        // canonically equivalent to `K`.
        for reservedID in [
            prefix + "v1",
            prefix + "\u{301}v1",
            prefix + "\u{FE0F}v1",
            prefix.replacingOccurrences(of: "K", with: "\u{212A}") + "v1",
        ] {
            assertReservedKeyIsRejected(reservedID, from: defaultsSource, to: defaultsDestination)
            assertReservedKeyIsRejected(
                reservedID,
                from: InMemoryPersistentKeyValueStore(),
                to: InMemoryPersistentKeyValueStore()
            )
            assertReservedKeyIsRejected(reservedID, from: ubiquitousSource, to: ubiquitousDestination)
        }

        // A combining mark before the final `_` leaves the identifier outside the reserved namespace.
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let unreserved = PersistentKey("PersistentKeyValueKit_MigrationCompleted\u{301}_v1", defaultValue: 0)

        source.set(unreserved, to: 1)

        let report = try source.move(unreserved, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(destination.get(unreserved), 1)
    }

    func test_sameStore_isRejectedWhenAnyItemMapsAKeyToItself() throws {
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

    private func assertReservedKeyIsRejected<Source, Destination>(
        _ reservedID: String,
        from source: Source,
        to destination: Destination,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where Source: PersistentKeyValueStore, Destination: PersistentKeyValueStore {
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: "reserved-prefix")
        let ordinary = PersistentKey("reserved-prefix.ordinary", defaultValue: 0)
        let reserved = PersistentKey(reservedID, defaultValue: 0)

        for reservedIsSource in [true, false] {
            let input = reservedIsSource ? reserved : ordinary
            let output = reservedIsSource ? ordinary : reserved

            source.set(input, to: 19)
            destination.set(output, to: 27)

            XCTAssertThrowsError(
                try source.move(
                    .key(input, to: output),
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: .once(id: "reserved-prefix")
                ),
                file: file,
                line: line
            ) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .reservedKey(reservedID), file: file, line: line)
            }
            XCTAssertEqual(source.get(input), 19, file: file, line: line)
            XCTAssertEqual(destination.get(output), 27, file: file, line: line)
            XCTAssertFalse(destination.get(marker), file: file, line: line)

            source.remove(input)
            destination.remove(output)
        }
    }

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
