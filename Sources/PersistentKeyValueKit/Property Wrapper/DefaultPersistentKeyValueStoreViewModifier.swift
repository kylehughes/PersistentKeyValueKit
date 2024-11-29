//
//  DefaultPersistentKeyValueStoreViewModifier.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 7/1/24.
//

import SwiftUI

/// A view modifier that sets the `defaultPersistentKeyValueStore` environment value to the given store.
///
/// This modifier allows you to specify a custom `PersistentKeyValueStore` to be used as the default store for all
/// ``PersistentValue`` instances within the modified view hierarchy.
///
/// Using this view modifier is equivalent to:
///
/// ```swift
/// environment(\.defaultPersistentKeyValueStore, store)
/// ```
///
/// - Important: This modifier only affects ``PersistentValue`` instances that don't have a custom store specified.
///   ``PersistentValue`` instances with a custom store will continue to use their specified store.
public struct DefaultPersistentKeyValueStoreViewModifier {
    /// The store that will be set as the default in the environment where the view modifier is applied.
    public let store: any PersistentKeyValueStore
    
    // MARK: Public Initialization
    
    /// Creates a new view modifier with the specified store.
    ///
    /// - Parameter store: The `PersistentKeyValueStore` to be used as the default store in the modified view hierarchy.
    @inlinable
    public init(store: any PersistentKeyValueStore) {
        self.store = store
    }
}

// MARK: - ViewModifier Extension

extension DefaultPersistentKeyValueStoreViewModifier: ViewModifier {
    // MARK: Modifier Body
    
    @inlinable
    public func body(content: Content) -> some View {
        content
            .environment(\.defaultPersistentKeyValueStore, store)
    }
}

// MARK: - Extension for View

extension View {
    // MARK: Public Instance Interface
    
    /// Sets the default persistent key-value store for ``PersistentValue`` instances within this view.
    ///
    /// Use this modifier to specify a custom ``PersistentKeyValueStore`` to be used as the default store for all
    /// ``PersistentValue`` instances within the modified view hierarchy that don't have a custom store specified.
    ///
    /// Using this view modifier is equivalent to:
    ///
    /// ```swift
    /// environment(\.defaultPersistentKeyValueStore, store)
    /// ```
    ///
    /// - Important: This modifier only affects ``PersistentValue`` instances that don't have a custom store specified.
    ///   ``PersistentValue`` instances with a custom store will continue to use their specified store.
    /// - Parameter store: The `PersistentKeyValueStore` to use as the default store for ``PersistentValue`` instances.
    /// - Returns: A view with the default persistent key-value store set to the specified store.
    @inlinable
    public func defaultPersistentKeyValueStore(
        _ store: any PersistentKeyValueStore
    ) -> ModifiedContent<Self, DefaultPersistentKeyValueStoreViewModifier> {
        modifier(DefaultPersistentKeyValueStoreViewModifier(store: store))
    }
}
