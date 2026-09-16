import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationNativeEndpointTests: XCTestCase {
    func testDistinctNativeInstancesForSameSuiteAreRejectedForEveryPolicy() throws {
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        for policy in [PersistentKeyCopyConflictPolicy.keepDestination, .overwriteDestination] {
            let (source, destination, name) = try makeNativePair()
            defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
            source.set(key, to: 8)
            XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: policy)) {
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
            defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
            source.set(key, to: 8)
            XCTAssertThrowsError(try source.move(key, to: destination, onConflict: policy)) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
            }
            XCTAssertEqual(source.get(key), 8)
        }
    }

    func testThrowingSourceEndpointFailsAllFourOperationsBeforeMutation() throws {
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let source = ThrowingEndpointStore()
        let destination = InMemoryPersistentKeyValueStore()
        XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertThrowsError(try source.copy([key], to: destination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertThrowsError(try source.move(key, to: destination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertThrowsError(try source.move([key], to: destination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertEqual(destination.get(key), 0)
    }

    func testThrowingDestinationAndRecorderEndpointsFailBeforeMutation() throws {
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        for operation in 0..<4 {
            let source = InMemoryPersistentKeyValueStore()
            let destination: any PersistentKeyValueStore = operation < 2
                ? ThrowingEndpointStore() : InMemoryPersistentKeyValueStore()
            let recorder: any PersistentKeyValueStore = operation < 2
                ? InMemoryPersistentKeyValueStore() : ThrowingEndpointStore()
            source.set(key, to: 15)
            let completion: PersistentKeyMigrationCompletionPolicy? = operation >= 2
                ? .once(id: "recorder-\(operation)", recordedIn: recorder)
                : nil

            switch operation {
            case 0:
                XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: .overwriteDestination)) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
                }
            case 1:
                XCTAssertThrowsError(try source.move([key], to: destination, onConflict: .overwriteDestination)) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
                }
            case 2:
                XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: .overwriteDestination,
                    completion: completion!)) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
                }
            default:
                XCTAssertThrowsError(try source.move([key], to: destination, onConflict: .overwriteDestination,
                    completion: completion!)) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
                }
            }
            XCTAssertEqual(source.get(key), 15)
            XCTAssertEqual(destination.get(key), 0)
        }
    }

    func testEndpointFailureMatrixCoversAllRolesAndInputStates() throws {
        for role in [EndpointFailureRole.source, .destination, .recorder] {
            for operation in 0..<4 {
                for input in ["normal", "empty", "disabled", "absent", "recorded"] {
                    // Empty input is meaningful only for the batch overloads.
                    if input == "empty", operation == 0 || operation == 2 { continue }
                    let source = CountingEndpointStore(InMemoryPersistentKeyValueStore())
                    let destination = CountingEndpointStore(InMemoryPersistentKeyValueStore())
                    let recorder = CountingEndpointStore(InMemoryPersistentKeyValueStore())
                    let key: any PersistentKeyProtocol<Int> = input == "disabled"
                        ? DisabledMigrationKey(id: "value")
                        : PersistentKey<Int>("value", defaultValue: 0)
                    let keys: [any PersistentKeyProtocol] = input == "empty" ? [] : [key]
                    let migrationID = "failure-\(role)-\(operation)-\(UUID().uuidString)"
                    let marker = PersistentKey<Bool>.isMigrationCompleted(id: migrationID)
                    if input != "absent" { source.set(key, to: 23) }
                    destination.set(key, to: 47)
                    if input == "recorded" { recorder.set(marker, to: true) }
                    let originalSource = source.base.getOptional(key)
                    let originalDestination = destination.base.getOptional(key)
                    let originalMarker = recorder.base.getOptional(marker)
                    switch role {
                    case .source: source.failsEndpoint = true
                    case .destination: destination.failsEndpoint = true
                    case .recorder: recorder.failsEndpoint = true
                    }
                    let completion = PersistentKeyMigrationCompletionPolicy.once(
                        id: migrationID, recordedIn: recorder)

                    XCTAssertThrowsError(try perform(
                        operation: operation, keys: keys, key: key, source: source, destination: destination,
                        completion: completion
                    )) {
                        XCTAssertEqual($0 as? EndpointFailure, .expected)
                    }
                    XCTAssertEqual(source.endpointAccessCount, 1)
                    XCTAssertEqual(destination.endpointAccessCount, role == .source ? 0 : 1)
                    XCTAssertEqual(recorder.endpointAccessCount, role == .recorder ? 1 : 0)
                    XCTAssertEqual(source.backend.accessCount, 0)
                    XCTAssertEqual(destination.backend.accessCount, 0)
                    XCTAssertEqual(recorder.backend.accessCount, 0)
                    XCTAssertEqual(source.base.getOptional(key), originalSource)
                    XCTAssertEqual(destination.base.getOptional(key), originalDestination)
                    XCTAssertEqual(recorder.base.getOptional(marker), originalMarker)
                }
            }
        }
    }

    func testSuccessfulMigrationResolvesEachEndpointOnce() throws {
        let source = CountingEndpointStore(InMemoryPersistentKeyValueStore())
        let destination = CountingEndpointStore(InMemoryPersistentKeyValueStore())
        let recorder = CountingEndpointStore(InMemoryPersistentKeyValueStore())
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        source.set(key, to: 4)

        XCTAssertFalse(try source.copy(
            key, to: destination, onConflict: .overwriteDestination,
            completion: .once(id: "count-\(#function)", recordedIn: recorder)).hasFailures)
        XCTAssertEqual(source.endpointAccessCount, 1)
        XCTAssertEqual(destination.endpointAccessCount, 1)
        XCTAssertEqual(recorder.endpointAccessCount, 1)
    }

    func testRawUserDefaultsCannotParticipateInAnyEndpointRole() throws {
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let sourceName = "MigrationNativeEndpointTests.rawSource.\(UUID().uuidString)"
        let destinationName = "MigrationNativeEndpointTests.rawDestination.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: sourceName)?.removePersistentDomain(forName: sourceName)
            UserDefaults(suiteName: destinationName)?.removePersistentDomain(forName: destinationName)
        }
        let rawSource = try XCTUnwrap(UserDefaults(suiteName: sourceName))
        let rawDestination = try XCTUnwrap(UserDefaults(suiteName: destinationName))
        let configuredSource = try UserDefaults.migratable(suiteName: sourceName)
        let configuredDestination = try UserDefaults.migratable(suiteName: destinationName)
        rawSource.set(21, forKey: key.id)
        rawDestination.set("preserve", forKey: "unrelated")
        let sourceBefore = rawSource.persistentDomain(forName: sourceName) as NSDictionary?
        let destinationBefore = rawDestination.persistentDomain(forName: destinationName) as NSDictionary?

        XCTAssertThrowsError(try rawSource.copy(key, to: configuredDestination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertThrowsError(try configuredSource.copy(key, to: rawDestination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertThrowsError(try configuredSource.copy(
            key, to: configuredDestination, onConflict: .overwriteDestination,
            completion: .once(id: "raw-recorder", recordedIn: rawDestination))) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertEqual(rawSource.persistentDomain(forName: sourceName) as NSDictionary?, sourceBefore)
        XCTAssertEqual(rawDestination.persistentDomain(forName: destinationName) as NSDictionary?, destinationBefore)
    }

    func testAddedSuiteValuesDoNotMaskMigrationOrCompletionMarker() throws {
        let sourceName = "MigrationNativeEndpointTests.addedSource.\(UUID().uuidString)"
        let destinationName = "MigrationNativeEndpointTests.addedDestination.\(UUID().uuidString)"
        let addedName = "MigrationNativeEndpointTests.added.\(UUID().uuidString)"
        let source = try UserDefaults.migratable(suiteName: sourceName)
        let destination = try UserDefaults.migratable(suiteName: destinationName)
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

        XCTAssertFalse(try source.copy(
            key, to: destination, onConflict: .keepDestination,
            completion: .once(id: migrationID, recordedIn: destination)).hasFailures)
        XCTAssertEqual(destination.get(key), 32)
        XCTAssertEqual(destination.persistentDomain(forName: destinationName)?[key.id] as? Int, 32)
        XCTAssertEqual(destination.persistentDomain(forName: destinationName)?[marker.id] as? Bool, true)
        XCTAssertEqual(
            try source.migrationEndpoint.backend.migrationIdentity.identifier, sourceName)
        XCTAssertEqual(
            try destination.migrationEndpoint.backend.migrationIdentity.identifier, destinationName)
    }

    func testAddedSuiteSourceValueIsAbsentAndDestinationFallbackIsNotAConflict() throws {
        let sourceName = "MigrationNativeEndpointTests.addedOnlySource.\(UUID().uuidString)"
        let destinationName = "MigrationNativeEndpointTests.addedOnlyDestination.\(UUID().uuidString)"
        let addedName = "MigrationNativeEndpointTests.addedOnly.\(UUID().uuidString)"
        let source = try UserDefaults.migratable(suiteName: sourceName)
        let destination = try UserDefaults.migratable(suiteName: destinationName)
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

        let report = try source.copy(key, to: destination, onConflict: .keepDestination)
        guard case .sourceAbsent = report.outcomes[0].status else { return XCTFail("Expected absent source") }
        XCTAssertNil(destination.persistentDomain(forName: destinationName)?[key.id])
        XCTAssertEqual(destination.get(key), 11)
    }

    @available(watchOS 9.0, *)
    func testNativeCloudAndMemoryStoresUseOrdinaryGenericAndExistentialContracts() throws {
        let factories: [() throws -> any PersistentKeyValueStore] = [
            { InMemoryPersistentKeyValueStore() },
            {
                let name = "MigrationNativeEndpointTests.generic.\(UUID().uuidString)"
                let defaults = try UserDefaults.migratable(suiteName: name)
                self.addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
                return defaults
            },
            { StrictMigrationUbiquitousStore() },
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
                    XCTAssertThrowsError(try source.move(key, to: destination, onConflict: .overwriteDestination)) {
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
                let moved = try source.move([key], to: destination, onConflict: .overwriteDestination)
                XCTAssertTrue(moved.isComplete)
                XCTAssertEqual(source.get(key), 0)
                XCTAssertEqual(destination.get(key), 17)
            }
        }
    }

    private func genericCopy<Key, Source, Destination>(
        _ key: Key, from source: Source, to destination: Destination
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Source: PersistentKeyValueStore, Destination: PersistentKeyValueStore {
        try source.copy(key, to: destination, onConflict: .overwriteDestination)
    }

    private func perform(
        operation: Int,
        keys: [any PersistentKeyProtocol],
        key: any PersistentKeyProtocol,
        source: any PersistentKeyValueStore,
        destination: any PersistentKeyValueStore,
        completion: PersistentKeyMigrationCompletionPolicy
    ) throws -> PersistentKeyMigrationReport {
        switch operation {
        case 0: return try source.copy(key, to: destination, onConflict: .overwriteDestination, completion: completion)
        case 1: return try source.copy(keys, to: destination, onConflict: .overwriteDestination, completion: completion)
        case 2: return try source.move(key, to: destination, onConflict: .overwriteDestination, completion: completion)
        default: return try source.move(keys, to: destination, onConflict: .overwriteDestination, completion: completion)
        }
    }

    private func makeNativePair() throws -> (UserDefaults, UserDefaults, String) {
        let name = "MigrationNativeEndpointTests.alias.\(UUID().uuidString)"
        let first = try UserDefaults.migratable(suiteName: name)
        let second = try UserDefaults.migratable(suiteName: name)
        XCTAssertFalse(first === second)
        return (first, second, name)
    }
}

private final class ThrowingEndpointStore: PersistentKeyValueStore {
    private let base = InMemoryPersistentKeyValueStore()

    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws { throw PersistentKeyMigrationError.missingMigrationDomain }
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol { base.get(key) }
    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol { base.set(key, to: value) }
    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol { base.remove(key) }
    func deregister<Key>(_ observer: NSObject, for key: Key, context: UnsafeMutableRawPointer?)
    where Key: PersistentKeyProtocol { base.deregister(observer, for: key, context: context) }
    func register<Key>(observer: NSObject, for key: Key, with context: UnsafeMutableRawPointer?, and selector: Selector)
    where Key: PersistentKeyProtocol { base.register(observer: observer, for: key, with: context, and: selector) }
}

private enum EndpointFailureRole: String {
    case source, destination, recorder
}

private enum EndpointFailure: Error { case expected }

private final class CountingEndpointStore: PersistentKeyValueStore {
    let base: InMemoryPersistentKeyValueStore
    let backend: MigrationFaultStore
    var failsEndpoint = false
    private(set) var endpointAccessCount = 0

    init(_ base: InMemoryPersistentKeyValueStore) {
        self.base = base
        backend = MigrationFaultStore(base)
    }

    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            endpointAccessCount += 1
            if failsEndpoint { throw EndpointFailure.expected }
            return backend.migrationEndpoint
        }
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol { base.get(key) }
    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol { base.set(key, to: value) }
    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol { base.remove(key) }
    func deregister<Key>(_ observer: NSObject, for key: Key, context: UnsafeMutableRawPointer?)
    where Key: PersistentKeyProtocol { base.deregister(observer, for: key, context: context) }
    func register<Key>(observer: NSObject, for key: Key, with context: UnsafeMutableRawPointer?, and selector: Selector)
    where Key: PersistentKeyProtocol { base.register(observer: observer, for: key, with: context, and: selector) }
}

private struct DisabledMigrationKey: PersistentKeyProtocol {
    let id: String
    let defaultValue = 0
    let representation: any PersistentKeyValueRepresentation<Int> = PrimitivePersistentKeyValueRepresentation<Int>()
    var isMigrationEnabled: Bool { false }

    func get(from userDefaults: UserDefaults) -> Int { defaultValue }
    func remove(from userDefaults: UserDefaults) {}
    func set(to newValue: Int, in userDefaults: UserDefaults) {}
    @available(watchOS 9.0, *) func get(from store: NSUbiquitousKeyValueStore) -> Int { defaultValue }
    @available(watchOS 9.0, *) func remove(from store: NSUbiquitousKeyValueStore) {}
    @available(watchOS 9.0, *) func set(to newValue: Int, in store: NSUbiquitousKeyValueStore) {}
}

private extension InMemoryPersistentKeyValueStore {
    func getOptional<Key>(_ key: Key) -> Key.Value? where Key: PersistentKeyProtocol {
        (try? migrationSnapshot(for: key.id)).flatMap { snapshot in
            try? migrationValue(for: key, in: snapshot)
        }
    }
}
