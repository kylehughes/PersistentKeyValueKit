//
//  PersistentValue.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 4/21/22.
//

import Combine
import Foundation
import SwiftUI

/// A property wrapper that provides a value from a ``PersistentKeyValueStore``.
///
/// e.g.
///
/// ```swift
/// @PersistentValue(.isAppStoreRatingEnabled, storage: userDefaults)
/// var isAppStoreRatingEnabled: Bool
/// ```
@available(iOS 14.0, macOS 11.0, watchOS 7.0, *)
@propertyWrapper
public struct PersistentValue<Key>: DynamicProperty where Key: PersistentKeyProtocol {
    private let key: Key
    
    @StateObject private var observer: PersistentKeyObserver<Key>
    
    // MARK: Public Initialization
    
    /// Creates a new property wrapper that provides a value from a ``PersistentKeyValueStore``.
    ///
    /// - Parameter key: The key to observe.
    /// - Parameter storage: The store to observe the key in.
    public init(_ key: Key, storage: some PersistentKeyValueStore) {
        self.key = key
        
        _observer = StateObject(wrappedValue: PersistentKeyObserver(storage: storage, key: key))
    }
    
    // MARK: Property Wrapper Implementation
    
    /// The value of the key in the store.
    ///
    /// This value is updated whenever the value in the store changes.
    @inlinable
    public var projectedValue: Binding<Key.Value> {
        Binding {
            wrappedValue
        } set: {
            wrappedValue = $0
        }
    }
    
    /// The value of the key in the store.
    ///
    /// This value is updated whenever the value in the store changes.
    public var wrappedValue: Key.Value {
        get {
            observer.value
        }
        nonmutating set {
            observer.value = newValue
        }
    }
}
