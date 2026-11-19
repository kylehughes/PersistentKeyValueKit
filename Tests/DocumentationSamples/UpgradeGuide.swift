// Release notes samples: upgrading custom conformances to 2.0.0.
//
// Each stub carries the members a conformance needs besides the ones the samples show. The store-specific `get` and
// `set` methods are omitted because 2.0.0 provides defaults for them.

import Foundation
import PersistentKeyValueKit

// MARK: - Stubs

nonisolated struct LayoutValue {
    let serializedString: String

    init?(parsing string: String) {
        serializedString = string
    }
}

nonisolated struct CustomRepresentation {
    typealias Value = LayoutValue
}

nonisolated struct CustomPrimitive {
    let rawValue: Int

    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
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

nonisolated extension CustomRepresentation: PersistentKeyValueRepresentation {
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

nonisolated extension CustomPrimitive: PrimitiveKeyValuePersistible {
    static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self {
        Self(rawValue: try Int.decode(storageObject: storageObject, format: format))
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
