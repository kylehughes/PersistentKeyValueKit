//
//  PersistentKeyValues.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 1/1/26.
//

import Foundation

/// An `AsyncSequence` that produces values for a key in a ``PersistentKeyValueStore`` as changes occur.
///
/// Use `PersistentKeyValues` to observe changes to a persistent key in any context, including UIKit and AppKit view
/// controllers.
///
/// e.g.
///
/// ```swift
/// let store = UserDefaults.standard
///
/// for await isEnabled in PersistentKeyValues(.featureFlag, store: store) {
///     updateUI(isEnabled: isEnabled)
/// }
/// ```
///
/// By default, the sequence emits the current value immediately upon iteration, followed by subsequent changes. Slow
/// consumers receive the latest pending change rather than every intermediate value. To observe only changes without
/// the initial value, pass `emitsInitialValue: false`.
///
/// e.g.
///
/// ```swift
/// for await isEnabled in PersistentKeyValues(.featureFlag, store: store, emitsInitialValue: false) {
///     handleChange(isEnabled: isEnabled)
/// }
/// ```
///
/// Each element is the value read from the store after the store reports a change, so the sequence describes the
/// key's current state rather than recording every write. Elements are emitted in the order they are read, and no
/// element is older than one emitted before it. Changes that occur close together, such as a change made by another
/// observer while it handles an earlier change, can be observed as one value, and consecutive elements can be equal.
///
/// - Important: The sequence continues producing values until the iterating `Task` is cancelled or the iterator is
///   released. After cancellation, ``Iterator/next()`` returns `nil` without returning pending values, and the
///   iterator deregisters from the store. Always iterate within a cancellable context.
/// - Important: By default, pending changes are buffered with `.bufferingNewest(1)` so slow consumers receive the
///   latest observed value without accumulating an unbounded backlog. Pass `.unbounded` to keep every observed value.
/// - Note: For `UserDefaults` keys whose identifiers are empty, begin with `@`, contain a period (`.`) code unit
///   (even inside a combined character) or NUL, or are `valueForKey:` or `ValueForKey:`, only changes made in the
///   current process request a read of the key. Changes made by another process, such as an app extension that shares
///   an app group, or caused only by `addSuite(named:)` or `removeSuite(named:)`, are not delivered by themselves and
///   can become visible when a later in-process change is read.
///   For other `UserDefaults` keys, key-value observation does not report a write of a value that Foundation considers
///   equal to the stored value, such as an `Int64` over an equal `Int32` or `-0.0` over `0.0`, so the observed value
///   can remain the previous, numerically equal value.
/// - SeeAlso: ``PersistentKeyProtocol/changes(in:bufferingPolicy:)`` for observing only subsequent changes.
/// - SeeAlso: ``PersistentValue`` for observation relying on SwiftUI `View` and environment.
public struct PersistentKeyValues<Key> where Key: PersistentKeyProtocol {
    /// The buffering policy used for pending changes.
    public typealias BufferingPolicy = AsyncStream<Key.Value>.Continuation.BufferingPolicy

    /// The buffering policy used for pending changes.
    public let bufferingPolicy: BufferingPolicy

    /// Whether the sequence emits the current value immediately upon iteration.
    public let emitsInitialValue: Bool

    /// The key being observed.
    public let key: Key

    /// The store that the key is being observed in.
    public let store: any PersistentKeyValueStore

    // MARK: Public Initialization

    /// Creates an `AsyncSequence` that produces values for a key in a ``PersistentKeyValueStore`` as changes occur.
    ///
    /// - Parameter key: The key to observe.
    /// - Parameter store: The ``PersistentKeyValueStore`` to observe the key in.
    /// - Parameter emitsInitialValue: Whether to emit the current value immediately upon iteration. Defaults to `true`.
    /// - Parameter bufferingPolicy: The buffering policy to use for pending changes. Defaults to `.bufferingNewest(1)`.
    @inlinable
    public init(
        _ key: Key,
        store: any PersistentKeyValueStore,
        emitsInitialValue: Bool = true,
        bufferingPolicy: BufferingPolicy = .bufferingNewest(1)
    ) {
        self.key = key
        self.store = store
        self.emitsInitialValue = emitsInitialValue
        self.bufferingPolicy = bufferingPolicy
    }

    // MARK: AsyncSequence Implementation

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(
            key: key,
            store: store,
            emitsInitialValue: emitsInitialValue,
            bufferingPolicy: bufferingPolicy
        )
    }
}

// MARK: - AsyncSequence Extension

extension PersistentKeyValues: AsyncSequence {
    // MARK: Public Typealiases

    public typealias Element = Key.Value
}

// MARK: - Sendable Extension

/// - Important: This type is manually `Sendable` because `PersistentKeyValueStore` cannot require `Sendable`.
///   `PersistentKeyValues` is immutable, and conforming stores are required to be safe for concurrent use by
///   observation APIs.
extension PersistentKeyValues: @unchecked Sendable where Key.Value: Sendable {}

// MARK: - Iterator Definition

extension PersistentKeyValues {
    /// The iterator that produces values from the underlying store.
    public struct Iterator: AsyncIteratorProtocol {
        private let observer: Observer<Key>

        private var pendingInitialValue: Key.Value?

        /// The iterator of buffered changes, or `nil` after iteration has ended, which releases the buffer.
        private var streamIterator: AsyncStream<Key.Value>.Iterator?

        // MARK: Internal Initialization

        @usableFromInline
        internal init(
            key: Key,
            store: any PersistentKeyValueStore,
            emitsInitialValue: Bool,
            bufferingPolicy: BufferingPolicy
        ) {
            observer = Observer(key: key, store: store)

            let (stream, initialValue) = observer.start(
                bufferingPolicy: bufferingPolicy,
                emitsInitialValue: emitsInitialValue
            )

            pendingInitialValue = initialValue
            streamIterator = stream.makeAsyncIterator()
        }

        // MARK: AsyncIteratorProtocol Implementation

        /// Returns the next value, or `nil` when iteration has ended.
        ///
        /// Iteration ends when the calling task is cancelled, whether cancellation happens before the call or while it
        /// waits. A call made after cancellation returns `nil` without returning the pending initial value or any
        /// buffered change, deregisters from the store, and releases those values, and every later call returns `nil`.
        public mutating func next() async -> Key.Value? {
            guard !Task.isCancelled else {
                return finish()
            }

            if let pendingInitialValue {
                self.pendingInitialValue = nil

                return pendingInitialValue
            }

            // A finished iterator has no stream iterator, so it returns `nil` without waiting.
            let value = await streamIterator?.next()

            // The stream can return a value buffered before a cancellation that happened while this call waited.
            guard let value, !Task.isCancelled else {
                return finish()
            }

            return value
        }

        // MARK: Private Instance Interface

        private mutating func finish() -> Key.Value? {
            pendingInitialValue = nil
            observer.deregister()

            // Deregistration released the continuation, so this releases the stream and its buffered values.
            streamIterator = nil

            return nil
        }
    }
}

// MARK: - Observer Definition

/// An observer that bridges `PersistentKeyValueStore` changes to an `AsyncStream` continuation.
///
/// This class, and the ``PersistentKeyValueStore`` functions it relies upon, implement the two known ways to observe
/// `UserDefaults` and `NSUbiquitousKeyValueStore`. It mirrors the design of the internal observer used by
/// ``PersistentKeyUIObservableObject``, adapted for `AsyncStream` production.
///
/// - SeeAlso: ``PersistentKeyValueStore`` for thread-safety requirements.
/// - SeeAlso: https://forums.swift.org/t/crash-when-running-in-swift-6-language-mode/72431/2
/// - Important: Access to mutable observer state is protected by `state`, and conforming stores are required to be
///   thread-safe.
private final class Observer<Key>: NSObject, Sendable where Key: PersistentKeyProtocol {
    private let key: Key
    private let keyID: String
    private let state: State

    /// The store being observed. Marked `nonisolated(unsafe)` because ``PersistentKeyValueStore`` conforming types
    /// are required to be thread-safe.
    private nonisolated(unsafe) let store: any PersistentKeyValueStore

    // MARK: Internal Initialization

    internal init(key: Key, store: any PersistentKeyValueStore) {
        self.key = key
        self.keyID = key.id
        self.store = store

        state = State()

        super.init()
    }

    // MARK: Deinitialization

    deinit {
        deregister()
    }

    // MARK: Internal Instance Interface

    /// Registers with the store and returns the stream of later observations, plus the initial value when requested.
    ///
    /// The initial value is read while this observer exclusively owns emission, so every value yielded to the stream
    /// is read after it. Changes reported before that read are already reflected in it and are not yielded again.
    internal func start(
        bufferingPolicy: PersistentKeyValues<Key>.BufferingPolicy,
        emitsInitialValue: Bool
    ) -> (stream: AsyncStream<Key.Value>, initialValue: Key.Value?) {
        var initialValue: Key.Value?

        let stream = AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            state.setContinuation(continuation, isEmitting: emitsInitialValue)

            continuation.onTermination = { [weak self] _ in
                self?.deregister()
            }

            store.register(
                observer: self,
                for: key,
                with: nil,
                and: #selector(didReceive(_:))
            )

            guard emitsInitialValue else {
                return
            }

            state.discardPendingChange()
            initialValue = store.get(key)
            emitPendingChanges()
        }

        return (stream, initialValue)
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

        valueDidChange()
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

        valueDidChange()
    }

    /// Stops observing the store. Only the first call deregisters.
    internal nonisolated func deregister() {
        let (isFirstDeregistration, continuation) = state.markDeregistered()

        // Releasing the continuation can release the stream's storage and run its termination handler, which
        // deregisters again, so release it only after the state lock is unlocked.
        withExtendedLifetime(continuation) {}

        guard isFirstDeregistration else {
            return
        }

        store.deregister(self, for: key, context: nil)
    }

    // MARK: Private Instance Interface

    /// Reads and yields the current value until no change is pending.
    ///
    /// Only the emitting caller runs this loop. Reads happen outside the state lock, so a representation that writes
    /// the observed key while decoding queues another read instead of deadlocking or yielding out of order.
    private nonisolated func emitPendingChanges() {
        while let continuation = state.takePendingChange() {
            continuation.yield(store.get(key))
        }
    }

    private nonisolated func valueDidChange() {
        guard state.markPendingChange() else {
            return
        }

        emitPendingChanges()
    }
}

// MARK: - State Definition

extension Observer {
    /// Mutable state protected by `NSLock`.
    private final class State: @unchecked Sendable {
        private let lock: NSLock
        private var continuation: AsyncStream<Key.Value>.Continuation?
        private var hasPendingChange: Bool
        private var isDeregistered: Bool
        private var isEmitting: Bool

        init() {
            lock = NSLock()
            continuation = nil
            hasPendingChange = false
            isDeregistered = false
            isEmitting = false
        }

        /// Discards changes reported before the initial value is read.
        func discardPendingChange() {
            withLock {
                hasPendingChange = false
            }
        }

        /// Marks the observer deregistered, returning whether this call did so and the continuation it released.
        ///
        /// The caller releases the continuation after the lock is unlocked.
        func markDeregistered() -> (isFirstDeregistration: Bool, released: AsyncStream<Key.Value>.Continuation?) {
            withLock {
                guard !isDeregistered else {
                    return (false, nil)
                }

                let released = continuation

                isDeregistered = true
                continuation = nil

                return (true, released)
            }
        }

        /// Records a change and returns whether the caller became responsible for emitting it.
        func markPendingChange() -> Bool {
            withLock {
                guard continuation != nil else {
                    return false
                }

                hasPendingChange = true

                guard !isEmitting else {
                    return false
                }

                isEmitting = true

                return true
            }
        }

        func setContinuation(_ continuation: AsyncStream<Key.Value>.Continuation, isEmitting: Bool) {
            withLock {
                self.continuation = continuation
                self.isEmitting = isEmitting
            }
        }

        /// Consumes the pending change for the emitting caller, or releases emission when none remains.
        func takePendingChange() -> AsyncStream<Key.Value>.Continuation? {
            withLock {
                guard hasPendingChange, let continuation else {
                    // Release emission while holding the lock so a concurrent change cannot be recorded between the
                    // final check and the release.
                    isEmitting = false

                    return nil
                }

                hasPendingChange = false

                return continuation
            }
        }

        @discardableResult
        private func withLock<Result>(_ body: () -> Result) -> Result {
            lock.lock()
            defer {
                lock.unlock()
            }

            return body()
        }
    }
}
