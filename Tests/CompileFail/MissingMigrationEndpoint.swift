import Foundation
import PersistentKeyValueKit

private struct MissingMigrationEndpointStore: PersistentKeyValueStore {
    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol { key.defaultValue }
    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {}
    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {}
    func deregister<Key>(_ observer: NSObject, for key: Key, context: UnsafeMutableRawPointer?)
    where Key: PersistentKeyProtocol {}
    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {}
}

_ = MissingMigrationEndpointStore.self
