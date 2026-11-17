import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationNativeEndpointTests: XCTestCase {
    // MARK: Tests

    func testAddedSuiteSourceValueIsAbsentAndDestinationFallbackIsNotAConflict() throws {
        let sourceName = stableSuiteName("MigrationNativeEndpointTests.addedOnlySource")
        let destinationName = stableSuiteName("MigrationNativeEndpointTests.addedOnlyDestination")
        let addedName = stableSuiteName("MigrationNativeEndpointTests.addedOnly")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))
        let added = try XCTUnwrap(UserDefaults(suiteName: addedName))

        defer {
            source.removeSuite(named: addedName)
            destination.removeSuite(named: addedName)
            source.removePersistentDomain(forName: sourceName)
            destination.removePersistentDomain(forName: destinationName)
            added.removePersistentDomain(forName: addedName)
        }

        let key = PersistentKey<Int>(#function, defaultValue: 0)

        added.set(key, to: 11)
        destination.addSuite(named: addedName)
        source.addSuite(named: addedName)

        let report = try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked)

        guard case .sourceAbsent = report.outcomes[0].status else {
            return XCTFail("Expected absent source")
        }

        XCTAssertNil(destination.persistentDomain(forName: destinationName)?[key.id])
        XCTAssertEqual(destination.get(key), 11)
    }

    func testAddedSuiteValuesDoNotMaskMigrationOrCompletionMarker() throws {
        let sourceName = stableSuiteName("MigrationNativeEndpointTests.addedSource")
        let destinationName = stableSuiteName("MigrationNativeEndpointTests.addedDestination")
        let addedName = stableSuiteName("MigrationNativeEndpointTests.added")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))
        let added = try XCTUnwrap(UserDefaults(suiteName: addedName))

        defer {
            source.removeSuite(named: addedName)
            destination.removeSuite(named: addedName)
            source.removePersistentDomain(forName: sourceName)
            destination.removePersistentDomain(forName: destinationName)
            added.removePersistentDomain(forName: addedName)
        }

        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let migrationID = "added-\(UUID().uuidString)"
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: migrationID)

        source.set(key, to: 32)
        added.set(key, to: 99)
        added.set(marker, to: true)
        source.addSuite(named: addedName)
        destination.addSuite(named: addedName)

        XCTAssertTrue(destination.get(marker))
        XCTAssertNil(destination.persistentDomain(forName: destinationName)?[marker.id])

        XCTAssertFalse(
            try source.copy(
                key,
                to: destination,
                onConflict: .keepDestination,
                tracking: .once(id: migrationID, recordedIn: destination)
            ).hasFailures
        )

        XCTAssertEqual(destination.get(key), 32)
        XCTAssertEqual(destination.persistentDomain(forName: destinationName)?[key.id] as? Int, 32)
        XCTAssertEqual(destination.persistentDomain(forName: destinationName)?[marker.id] as? Bool, true)
        XCTAssertEqual(
            try source.migrationEndpoint.backend.migrationIdentity.identifier,
            UserDefaults.migrationDomainIdentifier(sourceName)
        )

        XCTAssertEqual(
            try destination.migrationEndpoint.backend.migrationIdentity.identifier,
            UserDefaults.migrationDomainIdentifier(destinationName)
        )
    }

    func testDistinctNativeInstancesForSameSuiteAreRejectedForEveryPolicy() throws {
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        for policy in [PersistentKeyCopyConflictPolicy.keepDestination, .overwriteDestination] {
            let (source, destination, name) = try makeNativePair()

            defer {
                UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            }

            source.set(key, to: 8)

            XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: policy, tracking: .untracked)) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
            }

            XCTAssertEqual(source.get(key), 8)
        }

        for policy in [
            PersistentKeyMoveConflictPolicy.keepBoth,
            .overwriteDestination,
            .keepDestinationAndRemoveSource,
        ] {
            let (source, destination, name) = try makeNativePair()

            defer {
                UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            }

            source.set(key, to: 8)

            XCTAssertThrowsError(try source.move(key, to: destination, onConflict: policy, tracking: .untracked)) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
            }

            XCTAssertEqual(source.get(key), 8)
        }
    }

    func testEndpointFailureMatrixCoversAllRolesAndInputStates() throws {
        for tracking in EndpointFailureTracking.allCases {
            for role in EndpointFailureRole.allCases where tracking != .untracked || role != .recorder {
                for operation in EndpointFailureOperation.allCases {
                    for input in EndpointFailureInput.allCases
                    where input.isValid(for: operation, tracking: tracking) {
                        let scenario = "role=\(role), operation=\(operation), input=\(input), tracking=\(tracking)"
                        let source = CountingEndpointStore(InMemoryPersistentKeyValueStore())
                        let destination = CountingEndpointStore(InMemoryPersistentKeyValueStore())
                        let recorder = CountingEndpointStore(InMemoryPersistentKeyValueStore())
                        let key: any PersistentKeyProtocol<Int> =
                            input == .disabled
                            ? DisabledMigrationKey(id: "value")
                            : PersistentKey<Int>("value", defaultValue: 0)
                        let keys: [any PersistentKeyProtocol] = input == .empty ? [] : [key]
                        let migrationID = "failure-\(UUID().uuidString)"
                        let marker = PersistentKey<Bool>.isMigrationCompleted(id: migrationID)

                        if input != .absent {
                            source.set(key, to: 23)
                        }

                        destination.set(key, to: 47)

                        if input == .recorded {
                            recorder.set(marker, to: true)
                        }

                        let originalSource = source.base.getOptional(key)
                        let originalDestination = destination.base.getOptional(key)
                        let originalMarker = recorder.base.getOptional(marker)

                        switch role {
                        case .source:
                            source.failsEndpoint = true
                        case .destination:
                            destination.failsEndpoint = true
                        case .recorder:
                            recorder.failsEndpoint = true
                        }

                        let completion = tracking.completion(id: migrationID, recorder: recorder)

                        XCTAssertThrowsError(
                            try perform(
                                operation: operation,
                                keys: keys,
                                key: key,
                                source: source,
                                destination: destination,
                                completion: completion
                            ),
                            "Expected endpoint failure (\(scenario))"
                        ) {
                            XCTAssertEqual($0 as? EndpointFailure, .expected, scenario)
                        }

                        XCTAssertEqual(source.endpointAccessCount, 1, scenario)
                        XCTAssertEqual(destination.endpointAccessCount, role == .source ? 0 : 1, scenario)
                        XCTAssertEqual(
                            recorder.endpointAccessCount,
                            tracking == .tracked && role == .recorder ? 1 : 0,
                            scenario
                        )

                        XCTAssertEqual(source.backend.accessCount, 0, scenario)
                        XCTAssertEqual(destination.backend.accessCount, 0, scenario)
                        XCTAssertEqual(recorder.backend.accessCount, 0, scenario)
                        XCTAssertEqual(source.base.getOptional(key), originalSource, scenario)
                        XCTAssertEqual(destination.base.getOptional(key), originalDestination, scenario)
                        XCTAssertEqual(recorder.base.getOptional(marker), originalMarker, scenario)
                    }
                }
            }
        }
    }

    @available(watchOS 9.0, *)
    func testNativeCloudAndMemoryStoresUseOrdinaryGenericAndExistentialContracts() throws {
        var nativeStoreCount = 0
        let factories: [() throws -> any PersistentKeyValueStore] = [
            {
                InMemoryPersistentKeyValueStore()
            },
            {
                let name = stableSuiteName("MigrationNativeEndpointTests.generic.\(nativeStoreCount)")

                nativeStoreCount += 1

                let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: name))

                self.addTeardownBlock {
                    UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
                }

                return defaults
            },
            {
                StrictMigrationUbiquitousStore()
            },
        ]

        for sourceKind in factories.indices {
            for destinationKind in factories.indices {
                let source = try factories[sourceKind]()
                let destination = try factories[destinationKind]()
                let key = PersistentKey<Int>(#function, defaultValue: 0)

                source.set(key, to: 17)

                if sourceKind == 2, destinationKind == 2 {
                    // Separate native cloud instances still identify the same backing store.
                    XCTAssertThrowsError(try genericCopy(key, from: source, to: destination)) {
                        XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
                    }

                    XCTAssertThrowsError(
                        try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
                    ) {
                        XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
                    }

                    XCTAssertEqual(source.get(key), 17)
                    XCTAssertEqual(destination.get(key), 0)
                    continue
                }

                let copied = try genericCopy(key, from: source, to: destination)

                XCTAssertTrue(copied.isComplete)
                XCTAssertEqual(source.get(key), 17)
                XCTAssertEqual(destination.get(key), 17)

                let moved = try source.move(
                    [key],
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: .untracked
                )

                XCTAssertTrue(moved.isComplete)
                XCTAssertEqual(source.get(key), 0)
                XCTAssertEqual(destination.get(key), 17)
            }
        }
    }

    func testRawUserDefaultsCannotParticipateInAnyEndpointRole() throws {
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let sourceName = stableSuiteName("MigrationNativeEndpointTests.rawSource")
        let destinationName = stableSuiteName("MigrationNativeEndpointTests.rawDestination")

        defer {
            UserDefaults(suiteName: sourceName)?.removePersistentDomain(forName: sourceName)
            UserDefaults(suiteName: destinationName)?.removePersistentDomain(forName: destinationName)
        }

        let rawSource = try XCTUnwrap(UserDefaults(suiteName: sourceName))
        let rawDestination = try XCTUnwrap(UserDefaults(suiteName: destinationName))
        let configuredSource = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let configuredDestination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))

        rawSource.set(21, forKey: key.id)
        rawDestination.set("preserve", forKey: "unrelated")
        let sourceBefore = rawSource.persistentDomain(forName: sourceName) as NSDictionary?
        let destinationBefore = rawDestination.persistentDomain(forName: destinationName) as NSDictionary?

        XCTAssertThrowsError(
            try rawSource.copy(key, to: configuredDestination, onConflict: .overwriteDestination, tracking: .untracked)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }

        XCTAssertThrowsError(
            try configuredSource.copy(key, to: rawDestination, onConflict: .overwriteDestination, tracking: .untracked)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }

        XCTAssertThrowsError(
            try configuredSource.copy(
                key,
                to: configuredDestination,
                onConflict: .overwriteDestination,
                tracking: .once(id: "raw-recorder", recordedIn: rawDestination)
            )
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }

        XCTAssertEqual(rawSource.persistentDomain(forName: sourceName) as NSDictionary?, sourceBefore)
        XCTAssertEqual(rawDestination.persistentDomain(forName: destinationName) as NSDictionary?, destinationBefore)
    }

    func testSuccessfulMigrationResolvesEachEndpointOnce() throws {
        let source = CountingEndpointStore(InMemoryPersistentKeyValueStore())
        let destination = CountingEndpointStore(InMemoryPersistentKeyValueStore())
        let recorder = CountingEndpointStore(InMemoryPersistentKeyValueStore())
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 4)

        XCTAssertFalse(
            try source.copy(
                key,
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: "count-\(#function)", recordedIn: recorder)
            ).hasFailures
        )

        XCTAssertEqual(source.endpointAccessCount, 1)
        XCTAssertEqual(destination.endpointAccessCount, 1)
        XCTAssertEqual(recorder.endpointAccessCount, 1)
    }

    // MARK: Private Instance Interface

    private func genericCopy<Key, Source, Destination>(
        _ key: Key,
        from source: Source,
        to destination: Destination
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Source: PersistentKeyValueStore, Destination: PersistentKeyValueStore {
        try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
    }

    private func makeNativePair(_ function: String = #function) throws -> (UserDefaults, UserDefaults, String) {
        let name = stableSuiteName("MigrationNativeEndpointTests.alias", function: function)
        let first = try XCTUnwrap(UserDefaults.migratable(suiteName: name))
        let second = try XCTUnwrap(UserDefaults.migratable(suiteName: name))

        XCTAssertFalse(first === second)

        return (first, second, name)
    }

    private func perform(
        operation: EndpointFailureOperation,
        keys: [any PersistentKeyProtocol],
        key: any PersistentKeyProtocol,
        source: any PersistentKeyValueStore,
        destination: any PersistentKeyValueStore,
        completion: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport {
        switch operation {
        case .copySingle:
            return try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: completion)
        case .copyBatch:
            return try source.copy(keys, to: destination, onConflict: .overwriteDestination, tracking: completion)
        case .moveSingle:
            return try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: completion)
        case .moveBatch:
            return try source.move(keys, to: destination, onConflict: .overwriteDestination, tracking: completion)
        }
    }
}

private enum EndpointFailureRole: CaseIterable, Equatable {
    case source
    case destination
    case recorder
}

private enum EndpointFailureOperation: CaseIterable, Equatable {
    case copySingle
    case copyBatch
    case moveSingle
    case moveBatch

    var isBatch: Bool {
        switch self {
        case .copyBatch, .moveBatch:
            return true
        case .copySingle, .moveSingle:
            return false
        }
    }
}

private enum EndpointFailureInput: CaseIterable, Equatable {
    case normal
    case empty
    case disabled
    case absent
    case recorded

    func isValid(for operation: EndpointFailureOperation, tracking: EndpointFailureTracking) -> Bool {
        if self == .empty {
            return operation.isBatch
        }

        if self == .recorded {
            return tracking == .tracked
        }

        return true
    }
}

private enum EndpointFailureTracking: CaseIterable, Equatable {
    case untracked
    case tracked

    func completion(id: String, recorder: any PersistentKeyValueStore) -> PersistentKeyMigrationTracking {
        switch self {
        case .untracked:
            return .untracked
        case .tracked:
            return .once(id: id, recordedIn: recorder)
        }
    }
}

private enum EndpointFailure: Error {
    case expected
}

// MARK: - Counting Endpoint Store Definition

private final class CountingEndpointStore {
    let backend: MigrationFaultStore
    let base: InMemoryPersistentKeyValueStore
    private(set) var endpointAccessCount = 0
    var failsEndpoint = false

    // MARK: Internal Initialization

    init(_ base: InMemoryPersistentKeyValueStore) {
        self.base = base
        backend = MigrationFaultStore(base)
    }
}

// MARK: - PersistentKeyValueStore Extension

extension CountingEndpointStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            endpointAccessCount += 1

            if failsEndpoint {
                throw EndpointFailure.expected
            }

            return backend.migrationEndpoint
        }
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

// MARK: - Disabled Migration Key Definition

private struct DisabledMigrationKey {
    let id: String
    let defaultValue = 0
    let representation: any PersistentKeyValueRepresentation<Int> = PrimitivePersistentKeyValueRepresentation<Int>()
}

// MARK: - PersistentKeyProtocol Extension

extension DisabledMigrationKey: PersistentKeyProtocol {
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

private extension InMemoryPersistentKeyValueStore {
    func getOptional<Key>(_ key: Key) -> Key.Value? where Key: PersistentKeyProtocol {
        (try? migrationSnapshot(for: key.id)).flatMap { snapshot in
            try? migrationValue(for: key, in: snapshot)
        }
    }
}
