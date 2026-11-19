import Foundation
import PersistentKeyValueKit

// This fixture must compile with the failing fixtures' flags, so a broken module path or flag cannot make every
// fixture fail.

struct WrappingStore<Base: PersistentKeyValueStore> {
    let base: Base
}

// MARK: - PersistentKeyValueStore Extension

extension WrappingStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            try base.migrationEndpoint
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

let source = WrappingStore(base: InMemoryPersistentKeyValueStore())
let destination = InMemoryPersistentKeyValueStore()
let key = PersistentKey("key", defaultValue: 0)
let old = PersistentKey("old", defaultValue: 0)
let new = PersistentKey("new", defaultValue: 0)
_ = try? source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
_ = try? source.copy(items: [.key(old, to: new)], to: destination, onConflict: .overwriteDestination, tracking: .untracked)
