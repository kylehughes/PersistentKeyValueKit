//
//  PersistentKeyValueStore+PersistentKeyValuePublisher.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/2/26.
//

import Combine

extension PersistentKeyValueStore {
    // MARK: Public Instance Interface

    /// Returns a Combine `Publisher` that produces subsequent values for the given key as changes occur.
    ///
    /// The publisher does not emit the current value when demand is first requested. Use
    /// ``publisher(for:emitsInitialValue:)`` when the subscriber also needs the current value.
    ///
    /// e.g.
    ///
    /// ```swift
    /// let cancellable = UserDefaults.standard.changesPublisher(for: .username)
    ///     .sink { username in
    ///         handleChange(username: username)
    ///     }
    /// ```
    ///
    /// - Parameter key: The key to observe.
    /// - Returns: A ``PersistentKeyValuePublisher`` for the key that skips its initial value.
    @inlinable
    public func changesPublisher<Key>(
        for key: Key
    ) -> PersistentKeyValuePublisher<Key> where Key: PersistentKeyProtocol {
        publisher(
            for: key,
            emitsInitialValue: false
        )
    }

    /// Returns a Combine `Publisher` that produces values for the given key as changes occur.
    ///
    /// By default, each subscription emits the current value when demand is first requested, followed by subsequent
    /// changes. If downstream demand is exhausted, later changes are coalesced and the latest current value is emitted
    /// when more demand is requested.
    ///
    /// e.g.
    ///
    /// ```swift
    /// let cancellable = UserDefaults.standard.publisher(for: .username)
    ///     .sink { username in
    ///         usernameLabel.text = username
    ///     }
    /// ```
    ///
    /// - Parameter key: The key to observe.
    /// - Parameter emitsInitialValue: Whether each subscription emits the current value first. Defaults to `true`.
    /// - Returns: A ``PersistentKeyValuePublisher`` for the key.
    @inlinable
    public func publisher<Key>(
        for key: Key,
        emitsInitialValue: Bool = true
    ) -> PersistentKeyValuePublisher<Key> where Key: PersistentKeyProtocol {
        PersistentKeyValuePublisher(
            key,
            store: self,
            emitsInitialValue: emitsInitialValue
        )
    }
}
