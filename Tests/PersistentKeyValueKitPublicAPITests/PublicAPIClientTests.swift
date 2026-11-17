import Combine
import Foundation
import PersistentKeyValueKit
import XCTest

final class PublicAPIClientTests: XCTestCase {
    // MARK: Tests

    func testCompletionRecorderCanBeSelectedIndependentlyOfDestination() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<String>("tracked", defaultValue: "")

        source.set(key, to: "value")

        let report = try source.copy(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: "migration", recordedIn: recorder)
        )

        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertEqual(destination.get(key), "value")
        XCTAssertTrue(recorder.get(.isMigrationCompleted(id: "migration")))
    }

    func testConsumerAbstractionCanForwardMigrationEndpoint() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
        let key = PersistentKey<Int>("forwarded", defaultValue: 0)

        source.set(key, to: 7)

        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertEqual(destination.base.get(key), 7)
    }

    func testConsumerDefinedPrimitiveProvidesCheckedConversion() throws {
        let representation = PublicPrimitive.persistentKeyValueRepresentation
        let object = try representation.encode(PublicPrimitive(rawValue: 31), format: .userDefaults)

        XCTAssertEqual(
            try representation.decode(storageObject: object as Any, format: .userDefaults).rawValue,
            31
        )
    }

    func testConsumerDefinedProxyRepresentationUsesCheckedConversion() throws {
        let representation = PublicProxyRepresentation<String, Int>(
            to: {
                Int($0)
            },
            from: {
                String($0)
            }
        )
        let object = try representation.encode("23", format: .propertyList)

        XCTAssertEqual(try representation.decode(storageObject: object as Any, format: .propertyList), "23")
    }

    func testGenericMigrationAndExistentialMigrationUseTheSameContract() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("value", defaultValue: 0)

        source.set(key, to: 42)

        let genericReport = try migrate(source: source, destination: destination, key: key)

        XCTAssertEqual(genericReport.outcomes.count, 1)
        XCTAssertEqual(destination.get(key), 42)

        let secondDestination = InMemoryPersistentKeyValueStore()
        let existentialSource: any PersistentKeyValueStore = source
        let existentialDestination: any PersistentKeyValueStore = secondDestination
        let report = try existentialSource.copy(
            [key],
            to: existentialDestination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertEqual(secondDestination.get(key), 42)
    }

    func testItemBatchesMixSameKeysMappedKeysAndTransforms() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()

        source.set(.publicTheme, to: "dark")
        source.set(.publicOldLaunchCount, to: 4)
        source.set(.publicLegacyFlag, to: true)

        let report = try source.copy(
            items: [
                .key(.publicTheme),
                .key(.publicOldLaunchCount, to: .publicLaunchCount),
                .key(.publicLegacyFlag, to: .publicMode) {
                    $0 ? .on : .off
                },
            ],
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.copied, .copied, .copied])
        XCTAssertEqual(report.outcome(for: .publicOldLaunchCount)?.destinationKeyID, "PublicAPI.launchCount")
        XCTAssertEqual(destination.get(.publicTheme), "dark")
        XCTAssertEqual(destination.get(.publicLaunchCount), 4)
        XCTAssertEqual(destination.get(.publicMode), .on)

        let renamed = try destination.move(
            .key(.publicLaunchCount, to: .publicOldLaunchCount),
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(renamed.outcomes.map(\.status), [.moved])
        XCTAssertEqual(destination.get(.publicOldLaunchCount), 4)
        XCTAssertEqual(destination.get(.publicLaunchCount), 0)
    }

    func testMigrationCapturesEachEndpointOnce() throws {
        for operation in 0..<8 {
            let source = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
            let destination = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
            let recorder = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
            let key = PersistentKey<Int>("counted-\(operation)", defaultValue: 0)
            let tracking = PersistentKeyMigrationTracking.once(id: "counted-\(operation)", recordedIn: recorder)

            source.set(key, to: 9)
            let report: PersistentKeyMigrationReport

            switch operation {
            case 0:
                report = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: tracking)
            case 1:
                report = try source.copy([key], to: destination, onConflict: .overwriteDestination, tracking: tracking)
            case 2:
                report = try source.copy(
                    .key(key),
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: tracking
                )
            case 3:
                report = try source.copy(
                    items: [.key(key)],
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: tracking
                )
            case 4:
                report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: tracking)
            case 5:
                report = try source.move([key], to: destination, onConflict: .overwriteDestination, tracking: tracking)
            case 6:
                report = try source.move(
                    .key(key),
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: tracking
                )
            default:
                report = try source.move(
                    items: [.key(key)],
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: tracking
                )
            }

            XCTAssertTrue(report.isComplete)
            XCTAssertEqual(destination.get(key), 9)
            XCTAssertTrue(recorder.get(.isMigrationCompleted(id: "counted-\(operation)")))
            XCTAssertEqual(source.endpointAccessCount, 1)
            XCTAssertEqual(destination.endpointAccessCount, 1)
            XCTAssertEqual(recorder.endpointAccessCount, 1)
        }
    }

    func testReportFixturesCanBeBuiltWithPublicInitializers() {
        let failure = PersistentKeyMigrationReport.Outcome(
            sourceKeyID: "old",
            destinationKeyID: "new",
            failedAt: .transform,
            error: PublicMigrationFailure()
        )
        let report = PersistentKeyMigrationReport(
            outcomes: [failure, .init(sourceKeyID: "other", status: .copied)],
            completion: .notRecorded
        )
        let failedCompletion = PersistentKeyMigrationReport(outcomes: [], completionError: PublicMigrationFailure())

        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(report.outcomes.map(\.destinationKeyID), ["new", "other"])
        XCTAssertTrue(report.outcomes[0].error is PublicMigrationFailure)
        XCTAssertEqual(failedCompletion.completion, .failed)
        XCTAssertTrue(failedCompletion.completionError is PublicMigrationFailure)
        XCTAssertEqual(PersistentKeyMigrationIncompleteError(report: report).report.outcomes.count, 2)
    }

    func testRepresentationCheckedConversionIsPublicAndFormatAware() throws {
        let representation = Int.persistentKeyValueRepresentation
        let object = try representation.encode(21, format: .propertyList)

        XCTAssertEqual(try representation.decode(storageObject: object as Any, format: .propertyList), 21)
    }

    func testSendableItemBatchCanMigrateInsideTask() async throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let items: [PersistentKeyMigrationItem] = [
            .key(.publicOldLaunchCount, to: .publicLaunchCount),
            .key(.publicLegacyFlag, to: .publicMode) {
                $0 ? .on : .off
            },
        ]

        source.set(.publicOldLaunchCount, to: 5)

        let report = try await Task.detached {
            try source.move(items: items, to: destination, onConflict: .keepBoth, tracking: .once(id: "task"))
        }.value

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .sourceAbsent])
        XCTAssertEqual(report.completion, .recorded)
        XCTAssertEqual(destination.get(.publicLaunchCount), 5)
    }

    func testThrowIfIncompleteSurfacesTheReport() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()

        source.set(.publicLegacyFlag, to: true)

        do {
            try source.move(
                .key(.publicLegacyFlag, to: .publicMode) { _ in
                    throw PublicMigrationFailure()
                },
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: "incomplete")
            )
            .throwIfIncomplete()
            XCTFail("Expected an incomplete migration")
        } catch let error as PersistentKeyMigrationIncompleteError {
            XCTAssertEqual(error.report.outcome(for: .publicLegacyFlag)?.status, .failed(.transform))
            XCTAssertTrue(error.report.outcome(for: .publicLegacyFlag)?.error is PublicMigrationFailure)
            XCTAssertEqual(error.report.completion, .notRecorded)
        }

        XCTAssertTrue(source.get(.publicLegacyFlag))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: "incomplete")))

        let complete = try source.move(
            .key(.publicLegacyFlag, to: .publicMode) {
                $0 ? .on : .off
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: "incomplete")
        )

        XCTAssertNoThrow(try complete.throwIfIncomplete())
        XCTAssertTrue(destination.get(.isMigrationCompleted(id: "incomplete")))
        XCTAssertFalse(source.get(.isMigrationCompleted(id: "incomplete")))
    }

    @available(watchOS 9.0, *)
    func testUbiquitousNativeStoreForwardsOrdinaryAccessAndMigration() throws {
        let store = PublicMockUbiquitousKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("cloud-adapter", defaultValue: 0)
        var values: [Int] = []
        let cancellable = store.publisher(for: key).sink {
            values.append($0)
        }

        store.set(key, to: 19)

        XCTAssertEqual(store.get(key), 19)
        XCTAssertEqual(store.object(forKey: key.id) as? Int, 19)

        let report = try store.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(destination.get(key), 19)
        store.remove(key)

        XCTAssertNil(store.object(forKey: key.id))
        store.set(key, to: 20)
        destination.set(key, to: 21)

        XCTAssertTrue(
            try destination.copy(key, to: store, onConflict: .overwriteDestination, tracking: .untracked).isComplete
        )
        XCTAssertEqual(values, [0, 19, 0, 20, 21])
        cancellable.cancel()
        store.set(key, to: 22)

        XCTAssertEqual(values, [0, 19, 0, 20, 21])
    }

    func testUserDefaultsMigratableFactoryIsFailableAndNonthrowing() throws {
        let suiteName = "PersistentKeyValueKit.PublicAPI.factory.\(UUID().uuidString)"
        let factory: (String) -> UserDefaults? = UserDefaults.migratable(suiteName:)
        let defaults = try XCTUnwrap(factory(suiteName))

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertNil(factory(""))
        XCTAssertNil(factory(kCFPreferencesAnyApplication as String))
        XCTAssertNil(factory(kCFPreferencesCurrentApplication as String))

        let contextualDefaults: UserDefaults? = .migratable(suiteName: suiteName)

        XCTAssertNotNil(contextualDefaults)
    }

    func testUserDefaultsNativeStoreForwardsOrdinaryAccessAndObservation() throws {
        let suiteName = "PersistentKeyValueKit.PublicAPI.\(UUID().uuidString)"
        let plainDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        defer {
            plainDefaults.removePersistentDomain(forName: suiteName)
        }

        let migratableDefaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let key = PersistentKey<Int>("adapter", defaultValue: 0)
        var values: [Int] = []
        let cancellable = migratableDefaults.publisher(for: key, emitsInitialValue: true).sink {
            values.append($0)
        }

        migratableDefaults.set(key, to: 12)

        XCTAssertEqual(migratableDefaults.get(key), 12)
        XCTAssertEqual(plainDefaults.get(key), 12)
        migratableDefaults.remove(key)

        XCTAssertEqual(migratableDefaults.get(key), 0)
        migratableDefaults.set(key, to: 13)
        let source = InMemoryPersistentKeyValueStore()

        source.set(key, to: 14)

        XCTAssertTrue(
            try source.copy(
                key,
                to: migratableDefaults,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ).isComplete
        )
        XCTAssertEqual(values, [0, 12, 0, 13, 14])
        cancellable.cancel()
        migratableDefaults.set(key, to: 15)

        XCTAssertEqual(values, [0, 12, 0, 13, 14])
    }

    func testUserDefaultsNativeStoreMigrationUsesCustomRepresentations() throws {
        let sourceName = "PersistentKeyValueKit.PublicAPI.source.\(UUID().uuidString)"
        let destinationName = "PersistentKeyValueKit.PublicAPI.destination.\(UUID().uuidString)"

        defer {
            UserDefaults.standard.removePersistentDomain(forName: sourceName)
            UserDefaults.standard.removePersistentDomain(forName: destinationName)
        }

        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))
        let proxyKey = PersistentKey<String>(
            "proxy",
            defaultValue: "",
            representation: PublicProxyRepresentation<String, Int>(
                to: {
                    Int($0)
                },
                from: {
                    String($0)
                }
            )
        )
        let primitiveKey = PersistentKey<PublicPrimitive>("primitive", defaultValue: PublicPrimitive(rawValue: 0))

        source.set(proxyKey, to: "44")
        source.set(primitiveKey, to: PublicPrimitive(rawValue: 55))

        let report = try source.copy(
            [proxyKey, primitiveKey],
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(destination.get(proxyKey), "44")
        XCTAssertEqual(destination.get(primitiveKey).rawValue, 55)
    }

    // MARK: Private Instance Interface

    private func migrate<Key, Source, Destination>(
        source: Source,
        destination: Destination,
        key: Key
    ) throws -> PersistentKeyMigrationReport
    where
        Key: PersistentKeyProtocol,
        Source: PersistentKeyValueStore,
        Destination: PersistentKeyValueStore
    {
        try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
    }
}

// MARK: - Endpoint Forwarding Store Definition

private final class EndpointForwardingStore {
    let base: InMemoryPersistentKeyValueStore
    private(set) var endpointAccessCount = 0

    // MARK: Internal Initialization

    init(_ base: InMemoryPersistentKeyValueStore) {
        self.base = base
    }
}

// MARK: - PersistentKeyValueStore Extension

extension EndpointForwardingStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        endpointAccessCount += 1

        return base.migrationEndpoint
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

// MARK: - Public Proxy Representation Definition

private struct PublicProxyRepresentation<Value, Proxy: KeyValuePersistible> {
    let fromClosure: @Sendable (Proxy) -> Value?
    let toClosure: @Sendable (Value) -> Proxy?

    // MARK: Internal Initialization

    init(to: @Sendable @escaping (Value) -> Proxy?, from: @Sendable @escaping (Proxy) -> Value?) {
        toClosure = to
        fromClosure = from
    }
}

// MARK: - ProxyPersistentKeyValueRepresentationProtocol Extension

extension PublicProxyRepresentation: ProxyPersistentKeyValueRepresentationProtocol {
    func from(_ proxy: Proxy) -> Value? {
        fromClosure(proxy)
    }

    func to(_ value: Value) -> Proxy? {
        toClosure(value)
    }
}

// MARK: - Public Primitive Definition

private struct PublicPrimitive: Equatable {
    let rawValue: Int
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension PublicPrimitive: PrimitiveKeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }

    static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self {
        guard let value = storageObject as? NSNumber else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return Self(rawValue: value.intValue)
    }

    static func get(_ key: String, from defaults: UserDefaults) -> Self? {
        defaults.object(forKey: key).flatMap {
            try? decode(storageObject: $0, format: .userDefaults)
        }
    }

    @available(watchOS 9.0, *)
    static func get(_ key: String, from store: NSUbiquitousKeyValueStore) -> Self? {
        store.object(forKey: key).flatMap {
            try? decode(storageObject: $0, format: .ubiquitousKeyValueStore)
        }
    }

    static func set(_ key: String, to value: Self, in defaults: UserDefaults) {
        defaults.set(value.rawValue, forKey: key)
    }

    @available(watchOS 9.0, *)
    static func set(_ key: String, to value: Self, in store: NSUbiquitousKeyValueStore) {
        store.set(value.rawValue, forKey: key)
    }

    func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        NSNumber(value: rawValue)
    }
}

// MARK: - Public Mock Ubiquitous Key-Value Store Definition

@available(watchOS 9.0, *)
private final class PublicMockUbiquitousKeyValueStore: NSUbiquitousKeyValueStore {
    private var values: [String: Any] = [:]

    // MARK: Internal Initialization

    override init() {
        super.init()
    }

    // MARK: NSUbiquitousKeyValueStore Implementation

    override func object(forKey key: String) -> Any? {
        values[key]
    }

    override func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    override func set(_ value: Any?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }
}

// MARK: - Public Migration Failure Definition

private struct PublicMigrationFailure: Error {
}

// MARK: - Public Mode Definition

private enum PublicMode: String, KeyValuePersistible {
    case off
    case on

    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}

// MARK: - PersistentKeyProtocol Extensions

extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    fileprivate static var publicLegacyFlag: Self {
        Self("PublicAPI.legacyFlag", defaultValue: false)
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<Int> {
    fileprivate static var publicLaunchCount: Self {
        Self("PublicAPI.launchCount", defaultValue: 0)
    }

    fileprivate static var publicOldLaunchCount: Self {
        Self("PublicAPI.oldLaunchCount", defaultValue: 0)
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<PublicMode> {
    fileprivate static var publicMode: Self {
        Self("PublicAPI.mode", defaultValue: .off)
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<String> {
    fileprivate static var publicTheme: Self {
        Self("PublicAPI.theme", defaultValue: "")
    }
}
