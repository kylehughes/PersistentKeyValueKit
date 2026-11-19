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
/// If you don't specify a store, `PersistentValue` reads `defaultPersistentKeyValueStore` from the SwiftUI
/// environment, which defaults to `UserDefaults.standard`.
///
/// When a view is updated with a different key, a different store, or a different environment store, the property
/// reads, writes, and observes the new key and store from that update onward.
///
/// - Important: Using this property wrapper with `NSUbiquitousKeyValueStore` requires local (in-app) mutations to be
///   performed through ``PersistentKeyValueStore``, `PersistentValue`, or store migration. Foundation does not post
///   `NSUbiquitousKeyValueStore.didChangeExternallyNotification` for local writes, so
///   `PersistentKeyValueKit` posts `NSUbiquitousKeyValueStore.didChangeInternallyNotification` for local writes and
///   removals.
/// - Note: For `UserDefaults` keys whose identifiers are empty, begin with `@`, contain a period (`.`) code unit
///   (even inside a combined character) or NUL, or are `valueForKey:` or `ValueForKey:`, only changes made in the
///   current process request a read of the key. Changes made by another process, such as an app extension that shares
///   an app group, or caused only by `addSuite(named:)` or `removeSuite(named:)`, are not delivered by themselves and
///   can become visible when a later in-process change is read.
///   For other `UserDefaults` keys, key-value observation does not report a write of a value that Foundation considers
///   equal to the stored value, such as an `Int64` over an equal `Int32` or `-0.0` over `0.0`, so the observed value
///   can remain the previous, numerically equal value.
/// - Attention: We use `@preconcurrency` to conform to `DynamicProperty` because otherwise `update()` is forced to
///   be nonisolated in order to meet the conformance. Apple uses `@preconcurrency` for their `@MainActor`-isolated
///   property wrappers as of 2024-10-22.
@propertyWrapper
@MainActor
public struct PersistentValue<Key> where Key: PersistentKeyProtocol {
    @Environment(\.defaultPersistentKeyValueStore) private var defaultStore
    
    @StateObject private var observer: PersistentKeyUIObservableObject<Key>

    /// The key from the most recent initialization. `@StateObject` keeps its first observer, so `update()` passes
    /// this key to it.
    private let key: Key

    /// The explicit store supplied by the most recent view update, or `nil` to use the environment's store.
    private let store: (any PersistentKeyValueStore)?
    
    // MARK: Public Initialization
    
    /// Creates a property that can read and write to a value in a ``PersistentKeyValueStore``.
    ///
    /// - Parameter key: The key to read and write to in the persistent store.
    /// - Parameter store: The ``PersistentKeyValueStore`` to read and write to. If `nil`, `PersistentValue` uses the
    ///   `defaultPersistentKeyValueStore` from the environment.
    public init(_ key: Key, store: (any PersistentKeyValueStore)? = nil) {
        self.key = key
        self.store = store

        _observer = StateObject(wrappedValue: PersistentKeyUIObservableObject(store: store, key: key))
    }
    
    // MARK: Property Wrapper Implementation
    
    /// A binding to the underlying value referenced by the persistent value property.
    ///
    /// This property allows SwiftUI to automatically update the value when used in controls like `TextField`.
    /// To get the `projectedValue`, use the `$` operator on the property variable.
    ///
    /// The binding reads and writes the key and store that the property uses when the binding is created. A binding
    /// that is kept after the view is updated with a different key or store, such as one captured by an escaping
    /// closure, keeps reading and writing its original key and store. While the observation that existed when the
    /// binding was created is current, a write through the binding invalidates the view directly. After a different key
    /// identifier or store replaces that observation, such a write does not itself update the view, and the view
    /// updates only when its current store reports a change to its current key. The binding keeps its store alive, but
    /// not the property's later stores or the view's state.
    public var projectedValue: Binding<Key.Value> {
        let observer = observer
        let key = observer.key
        let store = observer.store
        let registration = observer.registrationCount

        // The observer adopts the view's later keys and stores, so the binding references it weakly and invalidates
        // the view only while the observer still observes the key and store that the binding writes.
        return Binding {
            PersistentKeyUIObservableObject.value(for: key, in: store)
        } set: { [weak observer] newValue in
            if let observer, observer.registrationCount == registration {
                observer.objectWillChange.send()
            }

            PersistentKeyUIObservableObject.setValue(newValue, for: key, in: store)
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
        observer.update(key: key, store: store ?? defaultStore)
    }
}
