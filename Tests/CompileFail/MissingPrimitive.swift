import Foundation
import PersistentKeyValueKit

enum MissingPrimitive {
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension MissingPrimitive: PrimitiveKeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }

    static func get(from values: [Any]) -> [Self]? {
        nil
    }

    static func get(_ key: String, from dictionary: [String: Any]) -> Self? {
        nil
    }

    static func get(_ key: String, from defaults: UserDefaults) -> Self? {
        nil
    }

    @available(watchOS 9.0, *)
    static func get(_ key: String, from store: NSUbiquitousKeyValueStore) -> Self? {
        nil
    }

    static func set(_ values: [Self], to array: inout [Any]) {
    }

    static func set(_ key: String, to value: Self, in dictionary: inout [String: Any]) {
    }

    static func set(_ key: String, to value: Self, in defaults: UserDefaults) {
    }

    @available(watchOS 9.0, *)
    static func set(_ key: String, to value: Self, in store: NSUbiquitousKeyValueStore) {
    }
}

_ = MissingPrimitive.self
