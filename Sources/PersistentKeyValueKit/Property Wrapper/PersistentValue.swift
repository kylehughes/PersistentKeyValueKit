//
//  PersistentValue.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/21/22.
//

import Combine
import Foundation
import SwiftUI

/// A property wrapper type that can read and write to a value in a ``PersistentKeyValueStore``.
///
/// Use `PersistentValue` to create a property that can read and write to a value in a ``PersistentKeyValueStore``.
/// The value is automatically synchronized with the store, ensuring that changes in the store are reflected in the
/// property and vice versa.
///
/// You can use `PersistentValue` in a SwiftUI view like this:
///
/// ```swift
/// struct ContentView: View {
///     @PersistentValue(.isAppStoreRatingEnabled, store: userDefaults)
///     var isAppStoreRatingEnabled: Bool
///
///     var body: some View {
///         Toggle("Enable App Store Rating", isOn: $isAppStoreRatingEnabled)
///     }
/// }
/// ```
///
/// If you don't specify a store, `PersistentValue` uses the `defaultPersistentKeyValueStore` from the environment. If
/// you don't specify a default value, `UserDefaults.standard` is used.
///
/// - Important: Using this property wrapper with `NSUbiquitousKeyValueStore` requires all local (i.e. in-app) mutations
///   to be performed through the ``PersistentKeyValueStore`` APIs, or this property wrapper. There is no way to observe
///   local changes performed through the system APIs for `NSUbiquitousKeyValueStore`; notifications only exist for
///   external changes, and key-value observation does not work. We emit a custom notification for internal changes to
///   emulate the external system behavior.
/// - Attention: We use `@preconcurrency` to conform to `DynamicProperty` because otherwise `update()` is forced to
///   be nonisolated in order to meet the conformance. Apple uses `@preconcurrency` for their `@MainActor`-isolated
///   property wrappers as of 2024-10-22.
@propertyWrapper
@MainActor
public struct PersistentValue<Key> where Key: PersistentKeyProtocol {
    @Environment(\.defaultPersistentKeyValueStore) private var defaultStore
    
    @StateObject private var observer: PersistentKeyUIObservableObject<Key>
    
    // MARK: Public Initialization
    
    /// Creates a property that can read and write to a value in a ``PersistentKeyValueStore``.
    ///
    /// - Parameter key: The key to read and write to in the persistent store.
    /// - Parameter store: The ``PersistentKeyValueStore`` to read and write to. If `nil`, `PersistentValue` uses the
    ///   `defaultPersistentKeyValueStore` from the environment.
    public init(_ key: Key, store: (any PersistentKeyValueStore)? = nil) {
        _observer = StateObject(wrappedValue: PersistentKeyUIObservableObject(store: store, key: key))
    }
    
    // MARK: Property Wrapper Implementation
    
    /// A binding to the underlying value referenced by the persistent value property.
    ///
    /// This property allows SwiftUI to automatically update the value when used in controls like `TextField`.
    /// To get the `projectedValue`, use the `$` operator on the property variable.
    @inlinable
    public var projectedValue: Binding<Key.Value> {
        Binding {
            wrappedValue
        } set: {
            wrappedValue = $0
        }
    }
    
    /// The underlying value referenced by the persistent key.
    ///
    /// This property provides primary access to the value. When you use the `@PersistentValue` property wrapper,
    /// the wrapped value is this property.
    ///
    /// Accessing this property reads and writes the value from the underlying ``PersistentKeyValueStore``.
    public var wrappedValue: Key.Value {
        get {
            observer.value
        }
        nonmutating set {
            observer.value = newValue
        }
    }
}

// MARK: - DynamicProperty Extension

extension PersistentValue: @preconcurrency DynamicProperty {
    // MARK: Updating the Value
    
    public func update() {
        guard observer.store == nil else {
            return
        }
        
        observer.store = defaultStore
    }
}
