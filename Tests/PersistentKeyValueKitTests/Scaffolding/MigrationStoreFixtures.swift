import Foundation

@testable import PersistentKeyValueKit

@available(watchOS 9.0, *)
final class StrictMigrationUbiquitousStore: NSUbiquitousKeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var shouldRejectWrites = false
    private var shouldRejectRemovals = false
    private var synchronizationCount = 0

    var rejectWrites: Bool {
        get { lock.withLock { shouldRejectWrites } }
        set { lock.withLock { shouldRejectWrites = newValue } }
    }

    var rejectRemovals: Bool {
        get { lock.withLock { shouldRejectRemovals } }
        set { lock.withLock { shouldRejectRemovals = newValue } }
    }

    var synchronizeCount: Int { lock.withLock { synchronizationCount } }

    override func object(forKey key: String) -> Any? { lock.withLock { values[key] } }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    override func double(forKey key: String) -> Double { object(forKey: key) as? Double ?? 0 }
    override func longLong(forKey key: String) -> Int64 { object(forKey: key) as? Int64 ?? 0 }
    override func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
    override func set(_ object: Any?, forKey key: String) {
        lock.withLock {
            if !shouldRejectWrites, let object, PropertyListSerialization.propertyList(object, isValidFor: .binary) {
                values[key] = object
            }
        }
    }
    override func set(_ value: String?, forKey key: String) { set(value as Any?, forKey: key) }
    override func set(_ value: Data?, forKey key: String) { set(value as Any?, forKey: key) }
    override func set(_ value: [Any]?, forKey key: String) { set(value as Any?, forKey: key) }
    override func set(_ value: [String: Any]?, forKey key: String) { set(value as Any?, forKey: key) }
    override func set(_ value: Int64, forKey key: String) { set(value as Any?, forKey: key) }
    override func set(_ value: Double, forKey key: String) { set(value as Any?, forKey: key) }
    override func set(_ value: Bool, forKey key: String) { set(value as Any?, forKey: key) }
    override func removeObject(forKey key: String) {
        lock.withLock { if !shouldRejectRemovals { values.removeValue(forKey: key) } }
    }
    override func synchronize() -> Bool {
        lock.withLock {
            synchronizationCount += 1
            return true
        }
    }
    func storedValue(for key: String) -> Any? { object(forKey: key) }
}

extension NSLock {
    fileprivate func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
