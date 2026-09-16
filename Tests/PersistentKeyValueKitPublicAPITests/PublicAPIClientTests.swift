import Foundation
import Combine
import XCTest
import PersistentKeyValueKit

final class PublicAPIClientTests: XCTestCase {
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
            [key], to: existentialDestination, onConflict: .overwriteDestination)

        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertEqual(secondDestination.get(key), 42)
    }

    func testConsumerAbstractionCanForwardMigrationEndpoint() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
        let key = PersistentKey<Int>("forwarded", defaultValue: 0)
        source.set(key, to: 7)

        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination)

        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertEqual(destination.base.get(key), 7)
    }

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
            completion: .once(id: "migration", recordedIn: recorder))

        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertEqual(destination.get(key), "value")
        XCTAssertTrue(recorder.get(.isMigrationCompleted(id: "migration")))
    }

    func testMigrationCapturesEachEndpointOnce() throws {
        for operation in 0..<4 {
            let source = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
            let destination = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
            let recorder = EndpointForwardingStore(InMemoryPersistentKeyValueStore())
            let key = PersistentKey<Int>("counted-\(operation)", defaultValue: 0)
            source.set(key, to: 9)
            let report: PersistentKeyMigrationReport
            if operation == 0 {
                report = try source.copy(key, to: destination, onConflict: .overwriteDestination,
                    completion: .once(id: "counted-\(operation)", recordedIn: recorder))
            } else if operation == 1 {
                report = try source.copy([key], to: destination, onConflict: .overwriteDestination,
                    completion: .once(id: "counted-\(operation)", recordedIn: recorder))
            } else if operation == 2 {
                report = try source.move(key, to: destination, onConflict: .overwriteDestination,
                    completion: .once(id: "counted-\(operation)", recordedIn: recorder))
            } else {
                report = try source.move([key], to: destination, onConflict: .overwriteDestination,
                    completion: .once(id: "counted-\(operation)", recordedIn: recorder))
            }
            XCTAssertTrue(report.isComplete)
            XCTAssertEqual(destination.get(key), 9)
            XCTAssertTrue(recorder.get(.isMigrationCompleted(id: "counted-\(operation)")))
            XCTAssertEqual(source.endpointAccessCount, 1)
            XCTAssertEqual(destination.endpointAccessCount, 1)
            XCTAssertEqual(recorder.endpointAccessCount, 1)
        }
    }

    func testUserDefaultsNativeStoreForwardsOrdinaryAccessAndObservation() throws {
        let suiteName = "PersistentKeyValueKit.PublicAPI.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let adapter: UserDefaults = try .migratable(suiteName: suiteName)
        let key = PersistentKey<Int>("adapter", defaultValue: 0)
        var values: [Int] = []
        let cancellable = adapter.publisher(for: key, emitsInitialValue: true).sink { values.append($0) }

        adapter.set(key, to: 12)
        XCTAssertEqual(adapter.get(key), 12)
        XCTAssertEqual(defaults.get(key), 12)
        adapter.remove(key)
        XCTAssertEqual(adapter.get(key), 0)
        adapter.set(key, to: 13)
        let source = InMemoryPersistentKeyValueStore()
        source.set(key, to: 14)
        XCTAssertTrue(try source.copy(key, to: adapter, onConflict: .overwriteDestination).isComplete)
        XCTAssertEqual(values, [0, 12, 0, 13, 14])
        cancellable.cancel()
        adapter.set(key, to: 15)
        XCTAssertEqual(values, [0, 12, 0, 13, 14])
    }

    func testUserDefaultsNativeStoreMigrationUsesCustomRepresentations() throws {
        let sourceName = "PersistentKeyValueKit.PublicAPI.source.\(UUID().uuidString)"
        let destinationName = "PersistentKeyValueKit.PublicAPI.destination.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: sourceName)
            UserDefaults.standard.removePersistentDomain(forName: destinationName)
        }
        let source = try UserDefaults.migratable(suiteName: sourceName)
        let destination = try UserDefaults.migratable(suiteName: destinationName)
        let proxyKey = PersistentKey<String>(
            "proxy",
            defaultValue: "",
            representation: PublicProxyRepresentation<String, Int>(to: { Int($0) }, from: { String($0) }))
        let primitiveKey = PersistentKey<PublicPrimitive>("primitive", defaultValue: PublicPrimitive(rawValue: 0))
        source.set(proxyKey, to: "44")
        source.set(primitiveKey, to: PublicPrimitive(rawValue: 55))

        let report = try source.copy(
            [proxyKey, primitiveKey], to: destination, onConflict: .overwriteDestination)

        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(destination.get(proxyKey), "44")
        XCTAssertEqual(destination.get(primitiveKey).rawValue, 55)
    }

    @available(watchOS 9.0, *)
    func testUbiquitousNativeStoreForwardsOrdinaryAccessAndMigration() throws {
        let underlying = PublicMockUbiquitousKeyValueStore()
        let adapter = underlying
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("cloud-adapter", defaultValue: 0)
        var values: [Int] = []
        let cancellable = adapter.publisher(for: key).sink { values.append($0) }

        adapter.set(key, to: 19)
        XCTAssertEqual(adapter.get(key), 19)
        XCTAssertEqual(underlying.object(forKey: key.id) as? Int, 19)

        let report = try adapter.copy(key, to: destination, onConflict: .overwriteDestination)
        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(destination.get(key), 19)
        adapter.remove(key)
        XCTAssertNil(underlying.object(forKey: key.id))
        underlying.set(key, to: 20)
        destination.set(key, to: 21)
        XCTAssertTrue(try destination.copy(key, to: adapter, onConflict: .overwriteDestination).isComplete)
        XCTAssertEqual(values, [0, 19, 0, 20, 21])
        cancellable.cancel()
        adapter.set(key, to: 22)
        XCTAssertEqual(values, [0, 19, 0, 20, 21])
    }

    func testRepresentationCheckedConversionIsPublicAndFormatAware() throws {
        let representation = Int.persistentKeyValueRepresentation
        let object = try representation.encode(21, format: .propertyList)
        XCTAssertEqual(try representation.decode(storageObject: object as Any, format: .propertyList), 21)
    }

    func testConsumerDefinedProxyRepresentationUsesCheckedConversion() throws {
        let representation = PublicProxyRepresentation<String, Int>(
            to: { Int($0) }, from: { String($0) })
        let object = try representation.encode("23", format: .propertyList)

        XCTAssertEqual(try representation.decode(storageObject: object as Any, format: .propertyList), "23")
    }

    func testConsumerDefinedPrimitiveProvidesCheckedConversion() throws {
        let representation = PublicPrimitive.persistentKeyValueRepresentation
        let object = try representation.encode(PublicPrimitive(rawValue: 31), format: .userDefaults)

        XCTAssertEqual(
            try representation.decode(storageObject: object as Any, format: .userDefaults).rawValue,
            31)
    }

    private func migrate<Key, Source, Destination>(
        source: Source, destination: Destination, key: Key
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Source: PersistentKeyValueStore,
          Destination: PersistentKeyValueStore {
        try source.copy(key, to: destination, onConflict: .overwriteDestination)
    }
}

private final class EndpointForwardingStore: PersistentKeyValueStore {
    let base: InMemoryPersistentKeyValueStore
    private(set) var endpointAccessCount = 0

    init(_ base: InMemoryPersistentKeyValueStore) {
        self.base = base
    }

    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        endpointAccessCount += 1
        return base.migrationEndpoint
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        base.get(key)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        base.set(key, to: value)
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        base.remove(key)
    }

    func deregister<Key>(_ observer: NSObject, for key: Key, context: UnsafeMutableRawPointer?)
    where Key: PersistentKeyProtocol {
        base.deregister(observer, for: key, context: context)
    }

    func register<Key>(observer: NSObject, for key: Key, with context: UnsafeMutableRawPointer?, and selector: Selector)
    where Key: PersistentKeyProtocol {
        base.register(observer: observer, for: key, with: context, and: selector)
    }
}

private struct PublicProxyRepresentation<Value, Proxy: KeyValuePersistible>: ProxyPersistentKeyValueRepresentationProtocol {
    let toClosure: @Sendable (Value) -> Proxy?
    let fromClosure: @Sendable (Proxy) -> Value?

    init(to: @Sendable @escaping (Value) -> Proxy?, from: @Sendable @escaping (Proxy) -> Value?) {
        toClosure = to
        fromClosure = from
    }

    func to(_ value: Value) -> Proxy? { toClosure(value) }
    func from(_ proxy: Proxy) -> Value? { fromClosure(proxy) }
}

private struct PublicPrimitive: PrimitiveKeyValuePersistible, Equatable {
    let rawValue: Int

    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }

    static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self {
        guard let value = storageObject as? NSNumber else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }
        return Self(rawValue: value.intValue)
    }

    func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        NSNumber(value: rawValue)
    }

    static func get(_ key: String, from defaults: UserDefaults) -> Self? {
        defaults.object(forKey: key).flatMap { try? decode(storageObject: $0, format: .userDefaults) }
    }

    static func set(_ key: String, to value: Self, in defaults: UserDefaults) {
        defaults.set(value.rawValue, forKey: key)
    }

    @available(watchOS 9.0, *)
    static func get(_ key: String, from store: NSUbiquitousKeyValueStore) -> Self? {
        store.object(forKey: key).flatMap { try? decode(storageObject: $0, format: .ubiquitousKeyValueStore) }
    }

    @available(watchOS 9.0, *)
    static func set(_ key: String, to value: Self, in store: NSUbiquitousKeyValueStore) {
        store.set(value.rawValue, forKey: key)
    }
}

@available(watchOS 9.0, *)
private final class PublicMockUbiquitousKeyValueStore: NSUbiquitousKeyValueStore {
    private var values: [String: Any] = [:]

    override init() {
        super.init()
    }

    override func object(forKey key: String) -> Any? {
        values[key]
    }

    override func set(_ value: Any?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }

    override func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }
}
