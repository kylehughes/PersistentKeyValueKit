//
//  PersistentKeyValuePublisher.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/2/26.
//

import Combine
import Foundation

/// A Combine `Publisher` that produces values for a key in a ``PersistentKeyValueStore`` as changes occur.
///
/// `PersistentKeyValuePublisher` observes the same store changes as ``PersistentKeyValues``. By default, each
/// subscription emits the current value when demand is requested, followed by subsequent changes. To observe only
/// changes without the initial value, pass `emitsInitialValue: false`.
///
/// If downstream demand is exhausted, subsequent changes are coalesced. When more demand is requested, the publisher
/// emits the latest current value instead of replaying every intermediate transition.
///
/// - Important: Each subscription registers with the store. It deregisters when the subscription is cancelled or
///   released.
/// - SeeAlso: ``PersistentKeyProtocol/changesPublisher(in:)`` for observing only subsequent changes.
/// - SeeAlso: ``PersistentKeyValues`` for observing changes from async code.
public struct PersistentKeyValuePublisher<Key> where Key: PersistentKeyProtocol {
    /// Whether each subscription emits the current value before later changes.
    public let emitsInitialValue: Bool

    /// The key being observed.
    public let key: Key

    /// The store that the key is being observed in.
    public let store: any PersistentKeyValueStore

    // MARK: Public Initialization

    /// Creates a Combine `Publisher` that produces values for a key in a ``PersistentKeyValueStore`` as changes occur.
    ///
    /// - Parameter key: The key to observe.
    /// - Parameter store: The ``PersistentKeyValueStore`` to observe the key in.
    /// - Parameter emitsInitialValue: Whether each subscription emits the current value before later changes. Defaults
    ///   to `true`.
    @inlinable
    public init(
        _ key: Key,
        store: any PersistentKeyValueStore,
        emitsInitialValue: Bool = true
    ) {
        self.key = key
        self.store = store
        self.emitsInitialValue = emitsInitialValue
    }
}

// MARK: - Publisher Extension

extension PersistentKeyValuePublisher: Publisher {
    // MARK: Public Typealiases

    public typealias Failure = Never
    public typealias Output = Key.Value

    // MARK: Publisher Implementation

    public func receive<Downstream>(subscriber: Downstream)
    where
        Downstream: Subscriber,
        Downstream.Failure == Failure,
        Downstream.Input == Output
    {
        let subscription = Subscription(
            downstream: subscriber,
            key: key,
            store: store,
            emitsInitialValue: emitsInitialValue
        )

        subscriber.receive(subscription: subscription)
    }
}

// MARK: - Subscription Definition

extension PersistentKeyValuePublisher {
    /// A subscription that bridges `PersistentKeyValueStore` changes to a Combine subscriber.
    ///
    /// - Important: This type is manually `Sendable` because `PersistentKeyValueStore` cannot require `Sendable`
    ///   conformance from `UserDefaults` or `NSUbiquitousKeyValueStore`. Access to mutable subscription state is
    ///   protected by `lock`, and conforming stores are required to be thread-safe.
    private final class Subscription<Downstream>: NSObject, Combine.Subscription, @unchecked Sendable
    where
        Downstream: Subscriber,
        Downstream.Failure == Never,
        Downstream.Input == Key.Value
    {
        private let key: Key
        private let keyID: String
        private let lock: NSLock

        private var demand: Subscribers.Demand
        private var downstream: Downstream?
        private var hasPendingChange: Bool
        private var isCancelled: Bool
        private var isEmitting: Bool
        private var pendingInitialValue: Key.Value?

        /// The store being observed. Marked `nonisolated(unsafe)` because ``PersistentKeyValueStore`` conforming
        /// types are required to be thread-safe.
        private nonisolated(unsafe) let store: any PersistentKeyValueStore

        // MARK: Emission Definition

        private struct Emission {
            let downstream: Downstream
            let value: Key.Value
        }

        // MARK: Internal Initialization

        internal init(
            downstream: Downstream,
            key: Key,
            store: any PersistentKeyValueStore,
            emitsInitialValue: Bool
        ) {
            self.key = key
            self.keyID = key.id
            self.store = store

            demand = .none
            self.downstream = downstream
            hasPendingChange = false
            isCancelled = false
            isEmitting = false
            lock = NSLock()
            pendingInitialValue = nil

            super.init()

            store.register(
                observer: self,
                for: key,
                with: nil,
                and: #selector(didReceive(_:))
            )

            guard emitsInitialValue else {
                return
            }

            let initialValue = store.get(key)

            lock.lock()
            pendingInitialValue = initialValue
            lock.unlock()
        }

        // MARK: Deinitialization

        deinit {
            cancel()
        }

        // MARK: Subscription Implementation

        internal func request(_ demand: Subscribers.Demand) {
            guard demand > .none else {
                return
            }

            lock.lock()

            guard !isCancelled else {
                lock.unlock()

                return
            }

            self.demand += demand
            lock.unlock()

            emitPendingValues()
        }

        internal func cancel() {
            guard markCancelled() else {
                return
            }

            store.deregister(self, for: key, context: nil)
        }

        // MARK: NSObject Implementation

        /// - SeeAlso: https://forums.swift.org/t/crash-when-running-in-swift-6-language-mode/72431/2
        @objc
        internal nonisolated func didReceive(_ notification: Notification) {
            guard let changedKeyIDs = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
                return
            }

            guard changedKeyIDs.contains(keyID) else {
                return
            }

            queueCurrentValue()
        }

        /// - SeeAlso: https://forums.swift.org/t/crash-when-running-in-swift-6-language-mode/72431/2
        internal nonisolated override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard keyPath == nil || keyPath == keyID else {
                return
            }

            queueCurrentValue()
        }

        // MARK: Private Instance Interface

        private nonisolated func canEmit() -> Bool {
            !isCancelled
                && downstream != nil
                && demand > .none
                && (pendingInitialValue != nil || hasPendingChange)
        }

        private nonisolated func emitPendingValues() {
            lock.lock()

            guard !isEmitting else {
                lock.unlock()

                return
            }

            isEmitting = true
            lock.unlock()

            while true {
                while let emission = nextEmission() {
                    let additionalDemand = emission.downstream.receive(emission.value)

                    lock.lock()

                    if !isCancelled {
                        demand += additionalDemand
                    }

                    lock.unlock()
                }

                lock.lock()

                guard canEmit() else {
                    isEmitting = false
                    lock.unlock()

                    return
                }

                lock.unlock()
            }
        }

        private nonisolated func markCancelled() -> Bool {
            lock.lock()
            defer {
                lock.unlock()
            }

            guard !isCancelled else {
                return false
            }

            demand = .none
            downstream = nil
            hasPendingChange = false
            isCancelled = true
            pendingInitialValue = nil

            return true
        }

        private nonisolated func nextEmission() -> Emission? {
            lock.lock()
            defer {
                lock.unlock()
            }

            guard canEmit(), let downstream else {
                return nil
            }

            let value: Key.Value

            if let initialValue = pendingInitialValue {
                pendingInitialValue = nil
                value = initialValue
            } else {
                hasPendingChange = false
                value = store.get(key)
            }

            if demand != .unlimited {
                demand -= .max(1)
            }

            return Emission(downstream: downstream, value: value)
        }

        private nonisolated func queueCurrentValue() {
            lock.lock()

            guard !isCancelled else {
                lock.unlock()

                return
            }

            hasPendingChange = true
            lock.unlock()

            emitPendingValues()
        }
    }
}
