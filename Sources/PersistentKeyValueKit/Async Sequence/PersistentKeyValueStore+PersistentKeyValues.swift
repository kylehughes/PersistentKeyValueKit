//
//  PersistentKeyValueStore+PersistentKeyValues.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 1/1/26.
//

import Foundation

extension PersistentKeyValueStore {
    // MARK: Public Instance Interface

    /// Returns an `AsyncSequence` that produces subsequent values for the given key as changes occur.
    ///
    /// The sequence does not emit the current value when iteration starts. Use
    /// ``values(for:emitsInitialValue:bufferingPolicy:)`` when the consumer also needs the current value.
    ///
    /// e.g.
    ///
    /// ```swift
    /// for await username in UserDefaults.standard.changes(for: .username) {
    ///     handleChange(username: username)
    /// }
    /// ```
    ///
    /// - Parameter key: The key to observe.
    /// - Parameter bufferingPolicy: The buffering policy to use for pending changes. Defaults to `.bufferingNewest(1)`.
    /// - Returns: A ``PersistentKeyValues`` sequence for the key that skips its initial value.
    @inlinable
    public func changes<Key>(
        for key: Key,
        bufferingPolicy: PersistentKeyValues<Key>.BufferingPolicy = .bufferingNewest(1)
    ) -> PersistentKeyValues<Key> where Key: PersistentKeyProtocol {
        values(
            for: key,
            emitsInitialValue: false,
            bufferingPolicy: bufferingPolicy
        )
    }

    /// Returns an `AsyncSequence` that produces values for the given key as changes occur.
    ///
    /// By default, the sequence emits the current value immediately upon iteration, followed by subsequent changes. Slow
    /// consumers receive the latest pending change rather than every intermediate value.
    ///
    /// e.g.
    ///
    /// ```swift
    /// for await username in UserDefaults.standard.values(for: .username) {
    ///     usernameLabel.text = username
    /// }
    /// ```
    ///
    /// - Parameter key: The key to observe.
    /// - Parameter emitsInitialValue: Whether to emit the current value immediately. Defaults to `true`.
    /// - Parameter bufferingPolicy: The buffering policy to use for pending changes. Defaults to `.bufferingNewest(1)`.
    /// - Returns: A ``PersistentKeyValues`` sequence for the key.
    @inlinable
    public func values<Key>(
        for key: Key,
        emitsInitialValue: Bool = true,
        bufferingPolicy: PersistentKeyValues<Key>.BufferingPolicy = .bufferingNewest(1)
    ) -> PersistentKeyValues<Key> where Key: PersistentKeyProtocol {
        PersistentKeyValues(
            key,
            store: self,
            emitsInitialValue: emitsInitialValue,
            bufferingPolicy: bufferingPolicy
        )
    }
}
