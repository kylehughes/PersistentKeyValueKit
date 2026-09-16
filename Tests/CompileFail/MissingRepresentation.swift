import Foundation
import PersistentKeyValueKit

struct MissingRepresentation {
}

// MARK: - PersistentKeyValueRepresentation Extension

extension MissingRepresentation: PersistentKeyValueRepresentation {
    typealias Value = Int

    func get(from values: [Any]) -> [Int]? {
        values as? [Int]
    }

    func get(_ key: String, from dictionary: [String: Any]) -> Int? {
        dictionary[key] as? Int
    }

    func get(_ key: String, from defaults: UserDefaults) -> Int? {
        defaults.object(forKey: key) as? Int
    }

    @available(watchOS 9.0, *)
    func get(_ key: String, from store: NSUbiquitousKeyValueStore) -> Int? {
        store.object(forKey: key) as? Int
    }

    func set(_ values: [Int], to propertyListArray: inout [Any]) {
        propertyListArray = values
    }

    func set(_ key: String, to value: Int, in dictionary: inout [String: Any]) {
        dictionary[key] = value
    }

    func set(_ key: String, to value: Int, in defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    @available(watchOS 9.0, *)
    func set(_ key: String, to value: Int, in store: NSUbiquitousKeyValueStore) {
        store.set(value, forKey: key)
    }
}

_ = MissingRepresentation()
