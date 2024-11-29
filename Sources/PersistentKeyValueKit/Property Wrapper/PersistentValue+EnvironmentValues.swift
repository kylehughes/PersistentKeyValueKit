//
//  PersistentValue+EnvironmentValues.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 7/1/24.
//

import SwiftUI

// MARK: - Extension for EnvironmentValues

extension EnvironmentValues {
    /// The default persistent key-value store for the environment.
    ///
    /// This property allows you to read and write to the default ``PersistentKeyValueStore`` used by
    /// ``PersistentValue`` property wrappers in the current environment.
    ///
    /// You can set a custom default store for a view hierarchy using the `defaultPersistentKeyValueStore(_:)` modifier:
    ///
    /// ```swift
    /// ContentView()
    ///     .defaultPersistentKeyValueStore(.ubiquitous)
    /// ```
    ///
    /// If you don't set a custom default store, this value is set to `UserDefaults.standard`.
    ///
    /// - SeeAlso: ``PersistentKeyValueStore``
    /// - SeeAlso: ``PersistentValue``
    public var defaultPersistentKeyValueStore: any PersistentKeyValueStore {
        get { self[DefaultPersistentKeyValueStoreKey.self] }
        set { self[DefaultPersistentKeyValueStoreKey.self] = newValue }
    }
}

// MARK: - EnvironmentKey Definition

private struct DefaultPersistentKeyValueStoreKey: EnvironmentKey {
    // MARK: Internal Static Interface
    
    @usableFromInline
    internal static var defaultValue: any PersistentKeyValueStore {
        UserDefaults.standard
    }
}
