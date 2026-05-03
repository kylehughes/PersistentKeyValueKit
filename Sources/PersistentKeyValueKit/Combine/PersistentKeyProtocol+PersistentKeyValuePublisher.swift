//
//  PersistentKeyProtocol+PersistentKeyValuePublisher.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/2/26.
//

import Combine

extension PersistentKeyProtocol {
    // MARK: Public Instance Interface

    /// Returns a Combine `Publisher` that produces subsequent values for this key as changes occur in the store.
    ///
    /// The publisher does not emit the current value when demand is first requested. Use
    /// ``publisher(in:emitsInitialValue:)`` when the subscriber also needs the current value.
    ///
    /// e.g.
    ///
    /// ```swift
    /// let cancellable = PersistentKey.username.changesPublisher(in: UserDefaults.standard)
    ///     .sink { username in
    ///         handleChange(username: username)
    ///     }
    /// ```
    ///
    /// - Parameter store: The ``PersistentKeyValueStore`` to observe.
    /// - Returns: A ``PersistentKeyValuePublisher`` for this key that skips its initial value.
    @inlinable
    public func changesPublisher(
        in store: any PersistentKeyValueStore
    ) -> PersistentKeyValuePublisher<Self> {
        publisher(
            in: store,
            emitsInitialValue: false
        )
    }

    /// Returns a Combine `Publisher` that produces values for this key as changes occur in the store.
    ///
    /// By default, each subscription emits the current value when demand is first requested, followed by subsequent
    /// changes. If downstream demand is exhausted, later changes are coalesced and the latest current value is emitted
    /// when more demand is requested.
    ///
    /// e.g.
    ///
    /// ```swift
    /// let cancellable = PersistentKey.username.publisher(in: UserDefaults.standard)
    ///     .sink { username in
    ///         usernameLabel.text = username
    ///     }
    /// ```
    ///
    /// - Parameter store: The ``PersistentKeyValueStore`` to observe.
    /// - Parameter emitsInitialValue: Whether each subscription emits the current value first. Defaults to `true`.
    /// - Returns: A ``PersistentKeyValuePublisher`` for this key.
    @inlinable
    public func publisher(
        in store: any PersistentKeyValueStore,
        emitsInitialValue: Bool = true
    ) -> PersistentKeyValuePublisher<Self> {
        PersistentKeyValuePublisher(
            self,
            store: store,
            emitsInitialValue: emitsInitialValue
        )
    }
}
