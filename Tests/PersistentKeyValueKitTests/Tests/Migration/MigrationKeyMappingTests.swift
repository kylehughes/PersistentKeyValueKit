import Foundation
import XCTest

@testable import PersistentKeyValueKit

@available(watchOS 9.0, *)
final class MigrationKeyMappingTests: XCTestCase {
    // MARK: Tests

    func testConflictPolicyAppliesToDestinationKey() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let keys = MappingKeys(#function)

        source.set(keys.oldCount, to: 7)
        destination.set(keys.oldCount, to: 99)

        let unrelated = try source.copy(
            .key(keys.oldCount, to: keys.launchCount),
            to: destination,
            onConflict: .keepDestination,
            tracking: .untracked
        )

        XCTAssertEqual(unrelated.outcomes.map(\.status), [.copied])
        XCTAssertEqual(destination.get(keys.launchCount), 7)
        XCTAssertEqual(destination.get(keys.oldCount), 99)
        destination.set(keys.launchCount, to: 3)

        let conflicting = try source.copy(
            .key(keys.oldCount, to: keys.launchCount),
            to: destination,
            onConflict: .keepDestination,
            tracking: .untracked
        )

        XCTAssertEqual(conflicting.outcomes.map(\.status), [.keptDestination])
        XCTAssertEqual(destination.get(keys.launchCount), 3)

        let overwritten = try source.move(
            .key(keys.oldCount, to: keys.launchCount),
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(overwritten.outcomes.map(\.status), [.moved])
        XCTAssertEqual(destination.get(keys.launchCount), 7)
        XCTAssertEqual(destination.get(keys.oldCount), 99)
        XCTAssertNil(try source.migrationSnapshot(for: keys.oldCount.id))
    }

    func testDisabledSourceOrDestinationKeyIsNotAccessed() throws {
        let enabled = PersistentKey<Int>("\(#function).enabled", defaultValue: 0)
        let disabled = DisabledKey(id: "\(#function).disabled")
        let other = PersistentKey<Int>("\(#function).other", defaultValue: 0)
        let otherDisabled = DisabledKey(id: "\(#function).otherDisabled")

        for item in [PersistentKeyMigrationItem.key(disabled, to: enabled), .key(enabled, to: disabled)] {
            let source = MigrationFaultStore()
            let destination = MigrationFaultStore()
            let counter = CallCounter()
            let transformed = PersistentKeyMigrationItem.key(other, to: otherDisabled) {
                counter.increment()

                return $0
            }

            let report = try source.move(
                items: [item, transformed],
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.keyDisabled, .keyDisabled])
            XCTAssertNil(report.outcomes[0].error)
            XCTAssertEqual(source.accessCount, 0)
            XCTAssertEqual(destination.accessCount, 0)
            XCTAssertEqual(counter.count, 0)
        }
    }

    func testMappedCopyAcrossStorePairs() throws {
        for (source, destination) in try storePairs() {
            let scenario = "\(source.name) -> \(destination.name)"
            let keys = MappingKeys(#function)

            source.store.set(keys.oldCount, to: 7)
            source.store.set(keys.legacyFlag, to: true)
            let report = try source.store.copy(
                items: keys.items,
                to: destination.store,
                onConflict: .keepDestination,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.copied, .copied], scenario)
            XCTAssertEqual(report.outcomes.map(\.sourceKeyID), [keys.oldCount.id, keys.legacyFlag.id], scenario)
            XCTAssertEqual(report.outcomes.map(\.destinationKeyID), [keys.launchCount.id, keys.mode.id], scenario)
            XCTAssertTrue(report.isComplete, scenario)
            assertDestination(destination, keys: keys, scenario: scenario)
            XCTAssertEqual(source.store.get(keys.oldCount), 7, scenario)
            XCTAssertTrue(source.store.get(keys.legacyFlag), scenario)
            XCTAssertFalse(source.hasValue(keys.launchCount.id), scenario)
            XCTAssertFalse(source.hasValue(keys.mode.id), scenario)
        }
    }

    func testMappedMoveAcrossStorePairs() throws {
        for (source, destination) in try storePairs() {
            let scenario = "\(source.name) -> \(destination.name)"
            let keys = MappingKeys(#function)

            source.store.set(keys.oldCount, to: 7)
            source.store.set(keys.legacyFlag, to: true)
            let report = try source.store.move(
                items: keys.items,
                to: destination.store,
                onConflict: .keepBoth,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved], scenario)
            XCTAssertEqual(report.outcomes.map(\.destinationKeyID), [keys.launchCount.id, keys.mode.id], scenario)
            assertDestination(destination, keys: keys, scenario: scenario)
            XCTAssertFalse(source.hasValue(keys.oldCount.id), scenario)
            XCTAssertFalse(source.hasValue(keys.legacyFlag.id), scenario)
        }
    }

    func testMappedPrepareFailureUsesDestinationKeyAndPreservesSource() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = MigrationFaultStore()
        let keys = MappingKeys(#function)

        source.set(keys.oldCount, to: 7)
        destination.failure = .prepare
        destination.failureKey = keys.launchCount.id
        let report = try source.move(
            .key(keys.oldCount, to: keys.launchCount),
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)])
        XCTAssertEqual(report.outcomes[0].destinationKeyID, keys.launchCount.id)
        XCTAssertEqual(
            report.outcomes[0].error as? PersistentKeyValueConversionError,
            .encodingFailed
        )
        XCTAssertEqual(source.get(keys.oldCount), 7)
        XCTAssertNil(try destination.migrationSnapshot(for: keys.launchCount.id))
    }

    func testSameStoreRenameCopy() throws {
        for store in try sameStores() {
            let keys = MappingKeys(#function)

            store.store.set(keys.oldCount, to: 7)
            store.store.set(keys.legacyFlag, to: true)
            let report = try store.store.copy(
                items: keys.items,
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.copied, .copied], store.name)
            assertDestination(store, keys: keys, scenario: store.name)
            XCTAssertEqual(store.store.get(keys.oldCount), 7, store.name)
            XCTAssertTrue(store.store.get(keys.legacyFlag), store.name)
        }
    }

    func testSameStoreRenameMove() throws {
        for store in try sameStores() {
            let keys = MappingKeys(#function)

            store.store.set(keys.oldCount, to: 7)
            store.store.set(keys.legacyFlag, to: true)
            let report = try store.store.move(
                items: keys.items,
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .once(id: "\(#function).\(store.name)")
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved], store.name)
            XCTAssertEqual(report.completion, .recorded, store.name)
            assertDestination(store, keys: keys, scenario: store.name)
            XCTAssertFalse(store.hasValue(keys.oldCount.id), store.name)
            XCTAssertFalse(store.hasValue(keys.legacyFlag.id), store.name)
            XCTAssertTrue(store.store.get(.isMigrationCompleted(id: "\(#function).\(store.name)")), store.name)
        }
    }

    func testSameStoreRenameResolvesConflictsWithDestinationKey() throws {
        let store = InMemoryPersistentKeyValueStore()
        let keys = MappingKeys(#function)

        store.set(keys.oldCount, to: 7)
        store.set(keys.launchCount, to: 3)
        let kept = try store.move(
            .key(keys.oldCount, to: keys.launchCount),
            to: store,
            onConflict: .keepBoth,
            tracking: .untracked
        )

        XCTAssertEqual(kept.outcomes.map(\.status), [.keptDestination])
        XCTAssertEqual(store.get(keys.oldCount), 7)

        let discarded = try store.move(
            .key(keys.oldCount, to: keys.launchCount),
            to: store,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .untracked
        )

        XCTAssertEqual(discarded.outcomes.map(\.status), [.discardedSource])
        XCTAssertEqual(store.get(keys.launchCount), 3)
        XCTAssertNil(try store.migrationSnapshot(for: keys.oldCount.id))
    }

    func testTransformDoesNotRunWithoutAWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let keys = MappingKeys(#function)
        let counter = CallCounter()
        let item = PersistentKeyMigrationItem.key(keys.legacyFlag, to: keys.mode) {
            counter.increment()

            return $0 ? "on" : "off"
        }

        let absent = try source.copy(item, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(absent.outcomes.map(\.status), [.sourceAbsent])
        source.set(keys.legacyFlag, to: true)
        destination.set(keys.mode, to: "existing")

        let keptCopy = try source.copy(item, to: destination, onConflict: .keepDestination, tracking: .untracked)
        let keptMove = try source.move(item, to: destination, onConflict: .keepBoth, tracking: .untracked)

        XCTAssertEqual(keptCopy.outcomes.map(\.status), [.keptDestination])
        XCTAssertEqual(keptMove.outcomes.map(\.status), [.keptDestination])

        let discarded = try source.move(
            item,
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .untracked
        )

        XCTAssertEqual(discarded.outcomes.map(\.status), [.discardedSource])
        XCTAssertEqual(destination.get(keys.mode), "existing")
        XCTAssertNil(try source.migrationSnapshot(for: keys.legacyFlag.id))
        XCTAssertEqual(counter.count, 0)
    }

    func testTransformFailureLeavesSourceUntouched() throws {
        for (source, destination) in try storePairs() {
            let scenario = "\(source.name) -> \(destination.name)"
            let keys = MappingKeys(#function)

            source.store.set(keys.legacyFlag, to: true)
            source.store.set(keys.oldCount, to: 7)
            let report = try source.store.move(
                items: [
                    .key(keys.legacyFlag, to: keys.mode) { _ in
                        throw TransformFailure()
                    },
                    .key(keys.oldCount, to: keys.launchCount),
                ],
                to: destination.store,
                onConflict: .overwriteDestination,
                tracking: .once(id: "\(#function).\(scenario)", recordedIn: InMemoryPersistentKeyValueStore())
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.failed(.transform), .moved], scenario)
            XCTAssertTrue(report.outcomes[0].error is TransformFailure, scenario)
            XCTAssertEqual(report.outcomes[0].sourceKeyID, keys.legacyFlag.id, scenario)
            XCTAssertEqual(report.outcomes[0].destinationKeyID, keys.mode.id, scenario)
            XCTAssertEqual(report.completion, .notRecorded, scenario)
            XCTAssertTrue(source.store.get(keys.legacyFlag), scenario)
            XCTAssertFalse(destination.hasValue(keys.mode.id), scenario)
            XCTAssertEqual(destination.store.get(keys.launchCount), 7, scenario)
        }
    }

    // MARK: Private Instance Interface

    private func assertDestination(_ destination: TestStore, keys: MappingKeys, scenario: String) {
        XCTAssertEqual(destination.store.get(keys.launchCount), 7, scenario)
        XCTAssertEqual(destination.store.get(keys.mode), "on", scenario)

        if destination.storesFoundationObjects {
            // The destination key's representation, not the source key's, determines the stored object.
            XCTAssertEqual(destination.rawValue(keys.launchCount.id) as? String, "7", scenario)
        }
    }

    private func makeCloud() -> TestStore {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "mapping", identifier: UUID().uuidString)
        )

        return TestStore(name: "cloud", rawValue: raw.storedValue(for:), store: store, storesFoundationObjects: true)
    }

    private func makeDefaults(_ suffix: String) throws -> TestStore {
        let name = "MigrationKeyMappingTests.\(suffix).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: name))

        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }

        return TestStore(
            name: "defaults",
            rawValue: {
                defaults.persistentDomain(forName: name)?[$0]
            },
            store: defaults,
            storesFoundationObjects: true
        )
    }

    private func makeMemory() -> TestStore {
        let store = InMemoryPersistentKeyValueStore()

        return TestStore(
            name: "memory",
            rawValue: {
                (try? store.migrationSnapshot(for: $0))?.object
            },
            store: store,
            storesFoundationObjects: false
        )
    }

    private func sameStores() throws -> [TestStore] {
        // A plain NSUbiquitousKeyValueStore instance uses the canonical ubiquitous identity, so it is one store.
        let raw = StrictMigrationUbiquitousStore()

        return [
            makeMemory(),
            try makeDefaults("same"),
            TestStore(name: "cloud", rawValue: raw.storedValue(for:), store: raw, storesFoundationObjects: true),
        ]
    }

    private func storePairs() throws -> [(TestStore, TestStore)] {
        [
            (makeMemory(), makeMemory()),
            (makeMemory(), try makeDefaults("d1")),
            (makeMemory(), makeCloud()),
            (try makeDefaults("s1"), makeMemory()),
            (try makeDefaults("s2"), try makeDefaults("d2")),
            (try makeDefaults("s3"), makeCloud()),
            (makeCloud(), makeMemory()),
            (makeCloud(), try makeDefaults("d3")),
            (makeCloud(), makeCloud()),
        ]
    }
}

// MARK: - Call Counter Definition

private final class CallCounter: @unchecked Sendable {
    // `lock` protects `value`.
    private let lock = NSLock()
    private var value = 0

    // MARK: Internal Instance Interface

    var count: Int {
        lock.lock()

        defer {
            lock.unlock()
        }

        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

// MARK: - Disabled Key Definition

private struct DisabledKey {
    let defaultValue = 0
    let id: String
    let representation: any PersistentKeyValueRepresentation<Int> = PrimitivePersistentKeyValueRepresentation<Int>()
}

// MARK: - PersistentKeyProtocol Extension

extension DisabledKey: PersistentKeyProtocol {
    var isMigrationEnabled: Bool {
        false
    }

    @available(watchOS 9.0, *)
    func get(from store: NSUbiquitousKeyValueStore) -> Int {
        defaultValue
    }

    func get(from userDefaults: UserDefaults) -> Int {
        defaultValue
    }

    @available(watchOS 9.0, *)
    func remove(from store: NSUbiquitousKeyValueStore) {
    }

    func remove(from userDefaults: UserDefaults) {
    }

    @available(watchOS 9.0, *)
    func set(to newValue: Int, in store: NSUbiquitousKeyValueStore) {
    }

    func set(to newValue: Int, in userDefaults: UserDefaults) {
    }
}

// MARK: - Mapping Keys Definition

private struct MappingKeys {
    /// Stores its value as a string, unlike ``oldCount``, so tests can see which representation encoded the value.
    let launchCount: PersistentKey<Int>
    let legacyFlag: PersistentKey<Bool>
    let mode: PersistentKey<String>
    let oldCount: PersistentKey<Int>

    // MARK: Internal Initialization

    init(_ prefix: String) {
        launchCount = PersistentKey(
            "\(prefix).launchCount",
            defaultValue: 0,
            representation: LosslessStringConvertiblePersistentKeyValueRepresentation<Int>()
        )
        legacyFlag = PersistentKey("\(prefix).legacyFlag", defaultValue: false)
        mode = PersistentKey("\(prefix).mode", defaultValue: "")
        oldCount = PersistentKey("\(prefix).oldCount", defaultValue: 0)
    }

    // MARK: Internal Instance Interface

    var items: [PersistentKeyMigrationItem] {
        [
            .key(oldCount, to: launchCount),
            .key(legacyFlag, to: mode) {
                $0 ? "on" : "off"
            },
        ]
    }
}

// MARK: - Test Store Definition

private struct TestStore {
    let name: String
    let rawValue: (String) -> Any?
    let store: any PersistentKeyValueStore
    let storesFoundationObjects: Bool

    // MARK: Internal Instance Interface

    func hasValue(_ id: String) -> Bool {
        rawValue(id) != nil
    }
}

// MARK: - Transform Failure Definition

private struct TransformFailure: Error {
}
