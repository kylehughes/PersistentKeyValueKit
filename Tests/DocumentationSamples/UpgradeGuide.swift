// Release notes samples: upgrading custom conformances to 2.0.0.
//
// Each stub carries the 1.x members a pre-existing conformance already has, so the samples show only what 2.0.0 adds.

import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

struct LayoutValue {
    let serializedString: String

    init?(parsing string: String) {
        serializedString = string
    }
}

struct CustomRepresentation {
    typealias Value = LayoutValue

    func get(from propertyListArray: [Any]) -> [Value]? {
        nil
    }

    func set(_ values: [Value], to propertyListArray: inout [Any]) {
    }

    func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value? {
        nil
    }

    func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any]) {
    }

    func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        nil
    }

    func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
    }

    @available(watchOS 9.0, *)
    func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        nil
    }

    @available(watchOS 9.0, *)
    func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
    }
}

struct CustomPrimitive {
    let rawValue: Int

    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }

    static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        nil
    }

    static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
    }

    @available(watchOS 9.0, *)
    static func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Self? {
        nil
    }

    @available(watchOS 9.0, *)
    static func set(_ ubiquitousStoreKey: String, to value: Self, in ubiquitousStore: NSUbiquitousKeyValueStore) {
    }
}

struct ForwardingStore {
    let base: UserDefaults

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

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        base.register(observer: observer, for: key, with: context, and: selector)
    }
}

// MARK: - Samples

extension CustomRepresentation: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value {
        guard let string = storageObject as? String, let value = Value(parsing: string) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }
        return value
    }

    func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any? {
        value.serializedString
    }
}

extension CustomPrimitive: PrimitiveKeyValuePersistible {
    static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self {
        guard let number = storageObject as? NSNumber else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }
        return Self(rawValue: number.intValue)
    }

    func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        NSNumber(value: rawValue)
    }
}

extension ForwardingStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            try base.migrationEndpoint
        }
    }
}
