import Foundation

@testable import PersistentKeyValueKit

@available(watchOS 9.0, *)
final class StrictMigrationUbiquitousStore: NSUbiquitousKeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var shouldRejectWrites = false
    private var shouldRejectRemovals = false
    private var synchronizationCount = 0

    // MARK: Internal Instance Interface

    var rejectRemovals: Bool {
        get {
            lock.withLock {
                shouldRejectRemovals
            }
        }
        set {
            lock.withLock {
                shouldRejectRemovals = newValue
            }
        }
    }

    var rejectWrites: Bool {
        get {
            lock.withLock {
                shouldRejectWrites
            }
        }
        set {
            lock.withLock {
                shouldRejectWrites = newValue
            }
        }
    }

    var synchronizeCount: Int {
        lock.withLock {
            synchronizationCount
        }
    }

    override func array(forKey key: String) -> [Any]? {
        object(forKey: key) as? [Any]
    }

    override func bool(forKey key: String) -> Bool {
        object(forKey: key) as? Bool ?? false
    }

    override func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }

    override func dictionary(forKey key: String) -> [String: Any]? {
        object(forKey: key) as? [String: Any]
    }

    override func double(forKey key: String) -> Double {
        object(forKey: key) as? Double ?? 0
    }

    override func longLong(forKey key: String) -> Int64 {
        object(forKey: key) as? Int64 ?? 0
    }

    override func object(forKey key: String) -> Any? {
        lock.withLock {
            values[key]
        }
    }

    override func removeObject(forKey key: String) {
        lock.withLock {
            if !shouldRejectRemovals {
                values.removeValue(forKey: key)
            }
        }
    }

    override func set(_ object: Any?, forKey key: String) {
        lock.withLock {
            if !shouldRejectWrites, let object, PropertyListSerialization.propertyList(object, isValidFor: .binary) {
                values[key] = object
            }
        }
    }

    override func set(_ value: Bool, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    override func set(_ value: Data?, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    override func set(_ value: Double, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    override func set(_ value: Int64, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    override func set(_ value: String?, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    override func set(_ value: [Any]?, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    override func set(_ value: [String: Any]?, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    func storedValue(for key: String) -> Any? {
        object(forKey: key)
    }

    override func string(forKey key: String) -> String? {
        object(forKey: key) as? String
    }

    override func synchronize() -> Bool {
        lock.withLock {
            synchronizationCount += 1

            return true
        }
    }
}

// MARK: - NSLock Extension

extension NSLock {
    fileprivate func withLock<Result>(_ body: () -> Result) -> Result {
        lock()

        defer {
            unlock()
        }

        return body()
    }
}

// MARK: - UserDefaultsMigrationBackend PersistentKeyValueStore Extension

extension UserDefaultsMigrationBackend: PersistentKeyValueStore {
    public var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        .init(backend: self)
    }

    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        userDefaults.deregister(observer, for: key, context: context)
    }

    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        userDefaults.get(key)
    }

    public func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        userDefaults.register(observer: observer, for: key, with: context, and: selector)
    }

    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        userDefaults.remove(key)
    }

    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        userDefaults.set(key, to: value)
    }
}

// MARK: - UbiquitousKeyValueMigrationBackend PersistentKeyValueStore Extension

@available(watchOS 9.0, *)
extension UbiquitousKeyValueMigrationBackend: PersistentKeyValueStore {
    public var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        .init(backend: self)
    }

    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        ubiquitousStore.deregister(observer, for: key, context: context)
    }

    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        ubiquitousStore.get(key)
    }

    public func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        ubiquitousStore.register(observer: observer, for: key, with: context, and: selector)
    }

    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        ubiquitousStore.remove(key)
    }

    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        ubiquitousStore.set(key, to: value)
    }
}
