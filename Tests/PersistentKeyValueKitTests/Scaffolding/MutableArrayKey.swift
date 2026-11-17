//
//  MutableArrayKey.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit

/// A key whose value is a Foundation collection proxied through `[Int]`.
///
/// `NSMutableArray` bridges to a Swift array of optionals, so this key exercises stores that must keep the stored object
/// readable as its own type.
struct MutableArrayKey {
    let id: String
}

// MARK: - PersistentKeyProtocol Extension

extension MutableArrayKey: PersistentKeyProtocol {
    var defaultValue: NSMutableArray {
        NSMutableArray()
    }

    var representation: any PersistentKeyValueRepresentation<NSMutableArray> {
        ProxyPersistentKeyValueRepresentation<NSMutableArray, [Int]>(
            to: {
                $0 as? [Int] ?? []
            },
            from: {
                NSMutableArray(array: $0)
            }
        )
    }

    func get(from defaults: UserDefaults) -> NSMutableArray {
        representation.get(id, from: defaults) ?? defaultValue
    }

    @available(watchOS 9.0, *)
    func get(from store: NSUbiquitousKeyValueStore) -> NSMutableArray {
        representation.get(id, from: store) ?? defaultValue
    }

    func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: id)
    }

    @available(watchOS 9.0, *)
    func remove(from store: NSUbiquitousKeyValueStore) {
        store.removeObject(forKey: id)
    }

    func set(to value: NSMutableArray, in defaults: UserDefaults) {
        representation.set(id, to: value, in: defaults)
    }

    @available(watchOS 9.0, *)
    func set(to value: NSMutableArray, in store: NSUbiquitousKeyValueStore) {
        representation.set(id, to: value, in: store)
    }
}
