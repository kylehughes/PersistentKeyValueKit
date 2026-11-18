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
/// subscription emits the current value, followed by subsequent changes. The current value is read when the publisher
/// receives its subscriber, and it is delivered when the subscriber first requests demand, even if the key changed in
/// between; any such change is delivered after it. To observe only changes without the initial value, pass
/// `emitsInitialValue: false`.
///
/// If downstream demand is exhausted, subsequent changes are coalesced. When more demand is requested, the publisher
/// emits the latest current value instead of replaying every intermediate transition.
///
/// Each change value is read from the store after the store reports a change, and values are delivered serially in
/// the order they are read. Changes that occur close together can be observed as one value, and consecutive values can
/// be equal. A representation may write the observed key while decoding; that write is delivered as a later value. A
/// subscription that is cancelled while its value is being read, including by the representation, does not deliver
/// that value.
///
/// - Important: The publisher does not schedule delivery on any queue. Values are delivered synchronously on the
///   thread that requests demand or that reports a store change, which can be a background thread. While one thread
///   is delivering values, changes reported on other threads are delivered by that thread, so a concurrent write can
///   return before its change is delivered. Use `receive(on: DispatchQueue.main)` before updating UI.
/// - Important: Each subscription registers with the store. It deregisters when the subscription is cancelled or
///   released.
/// - Note: For `UserDefaults` keys whose identifiers are empty, begin with `@`, contain a period (`.`) code unit
///   (even inside a combined character) or NUL, or are `valueForKey:` or `ValueForKey:`, only changes made in the
///   current process are observed. Changes made by another process, such as an app extension that shares an app group,
///   might not be delivered, and neither are changes caused only by `addSuite(named:)` or `removeSuite(named:)`.
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

        /// A value reserved for delivery, with its demand already consumed.
        private struct Emission {
            let downstream: Downstream
            let value: EmissionValue
        }

        private enum EmissionValue {
            /// The current value, read after the reservation is made and the lock is released.
            case current
            /// The value read when the subscription was created.
            case initial(Key.Value)
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
            guard let released = markCancelled() else {
                return
            }

            // Releasing the subscriber can run a `deinit` that cancels this subscription again, so release it only
            // after the lock is unlocked.
            withExtendedLifetime(released) {}

            store.deregister(self, for: key, context: nil)
        }

        // MARK: NSObject Implementation

        /// - SeeAlso: https://forums.swift.org/t/crash-when-running-in-swift-6-language-mode/72431/2
        @objc
        internal nonisolated func didReceive(_ notification: Notification) {
            guard
                #available(watchOS 9.0, *),
                NSUbiquitousKeyValueStore.changeNotification(notification, mayAffectKeyID: keyID)
            else {
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

            while let emission = nextEmission() {
                // The emission can hold the last reference to the subscriber after a concurrent cancellation, so keep
                // it alive until the lock is unlocked.
                withExtendedLifetime(emission) {
                    deliver(emission)
                }
            }
        }

        private nonisolated func deliver(_ emission: Emission) {
            let value: Key.Value

            switch emission.value {
            case .current:
                // Read outside the lock: decoding can write the observed key and report a change synchronously.
                value = store.get(key)
            case let .initial(initialValue):
                value = initialValue
            }

            // Decoding runs consumer code that can cancel this subscription.
            guard !withLock({ isCancelled }) else {
                return
            }

            let additionalDemand = emission.downstream.receive(value)

            withLock {
                if !isCancelled {
                    demand += additionalDemand
                }
            }
        }

        /// Marks the subscription cancelled and returns the references it released, or `nil` if it was already
        /// cancelled.
        ///
        /// The caller releases the returned references after the lock is unlocked, because their deinitializers can
        /// run consumer code.
        private nonisolated func markCancelled() -> (Downstream?, Key.Value?)? {
            withLock {
                guard !isCancelled else {
                    return nil
                }

                let released = (downstream, pendingInitialValue)

                demand = .none
                downstream = nil
                hasPendingChange = false
                isCancelled = true
                pendingInitialValue = nil

                return released
            }
        }

        private nonisolated func nextEmission() -> Emission? {
            lock.lock()
            defer {
                lock.unlock()
            }

            guard canEmit(), let downstream else {
                // Release emitter ownership while holding the state lock so a concurrent callback cannot queue a
                // change between the final emission check and ownership release.
                isEmitting = false

                return nil
            }

            let value: EmissionValue

            if let initialValue = pendingInitialValue {
                pendingInitialValue = nil
                value = .initial(initialValue)
            } else {
                hasPendingChange = false
                value = .current
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

        private nonisolated func withLock<Result>(_ body: () -> Result) -> Result {
            lock.lock()
            defer {
                lock.unlock()
            }

            return body()
        }
    }
}
