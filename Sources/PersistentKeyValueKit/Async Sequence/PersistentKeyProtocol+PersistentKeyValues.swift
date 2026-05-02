//
//  PersistentKeyProtocol+PersistentKeyValues.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 1/1/26.
//

import Foundation

extension PersistentKeyProtocol {
    // MARK: Public Instance Interface

    /// Returns an `AsyncSequence` that produces subsequent values for this key as changes occur in the store.
    ///
    /// The sequence does not emit the current value when iteration starts. Use
    /// ``values(in:emitsInitialValue:bufferingPolicy:)`` when the consumer also needs the current value.
    ///
    /// e.g.
    ///
    /// ```swift
    /// for await username in PersistentKey.username.changes(in: UserDefaults.standard) {
    ///     handleChange(username: username)
    /// }
    /// ```
    ///
    /// - Parameter store: The ``PersistentKeyValueStore`` to observe.
    /// - Parameter bufferingPolicy: The buffering policy to use for pending changes. Defaults to `.bufferingNewest(1)`.
    /// - Returns: A ``PersistentKeyValues`` sequence for this key that skips its initial value.
    @inlinable
    public func changes(
        in store: any PersistentKeyValueStore,
        bufferingPolicy: PersistentKeyValues<Self>.BufferingPolicy = .bufferingNewest(1)
    ) -> PersistentKeyValues<Self> {
        values(
            in: store,
            emitsInitialValue: false,
            bufferingPolicy: bufferingPolicy
        )
    }

    /// Returns an `AsyncSequence` that produces values for this key as changes occur in the store.
    ///
    /// By default, the sequence emits the current value immediately upon iteration, followed by subsequent changes. Slow
    /// consumers receive the latest pending change rather than every intermediate value.
    ///
    /// e.g.
    ///
    /// ```swift
    /// for await username in PersistentKey.username.values(in: UserDefaults.standard) {
    ///     usernameLabel.text = username
    /// }
    /// ```
    ///
    /// - Parameter store: The ``PersistentKeyValueStore`` to observe.
    /// - Parameter emitsInitialValue: Whether to emit the current value immediately. Defaults to `true`.
    /// - Parameter bufferingPolicy: The buffering policy to use for pending changes. Defaults to `.bufferingNewest(1)`.
    /// - Returns: A ``PersistentKeyValues`` sequence for this key.
    @inlinable
    public func values(
        in store: any PersistentKeyValueStore,
        emitsInitialValue: Bool = true,
        bufferingPolicy: PersistentKeyValues<Self>.BufferingPolicy = .bufferingNewest(1)
    ) -> PersistentKeyValues<Self> {
        PersistentKeyValues(
            self,
            store: store,
            emitsInitialValue: emitsInitialValue,
            bufferingPolicy: bufferingPolicy
        )
    }
}
