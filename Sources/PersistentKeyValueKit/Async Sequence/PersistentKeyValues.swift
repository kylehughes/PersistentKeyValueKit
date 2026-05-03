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
/// consumers receive the latest pending change rather than every intermediate value. To observe only changes without the
/// initial value, pass `emitsInitialValue: false`.
///
/// e.g.
///
/// ```swift
/// for await isEnabled in PersistentKeyValues(.featureFlag, store: store, emitsInitialValue: false) {
///     handleChange(isEnabled: isEnabled)
/// }
/// ```
///
/// - Important: The sequence continues producing values until the iteration is cancelled or the `Task` is cancelled.
///   Always iterate within a cancellable context.
/// - Important: By default, pending changes are buffered with `.bufferingNewest(1)` so slow consumers receive the latest
///   observed value without accumulating an unbounded backlog. Pass `.unbounded` if every observed transition must be
///   delivered.
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

// MARK: - Iterator Definition

extension PersistentKeyValues {
    /// The iterator that produces values from the underlying store.
    public struct Iterator: AsyncIteratorProtocol {
        private let observer: Observer<Key>

        private var pendingInitialValue: Key.Value?

        private var streamIterator: AsyncStream<Key.Value>.Iterator

        // MARK: Internal Initialization

        @usableFromInline
        internal init(
            key: Key,
            store: any PersistentKeyValueStore,
            emitsInitialValue: Bool,
            bufferingPolicy: BufferingPolicy
        ) {
            observer = Observer(key: key, store: store)
            streamIterator = observer.makeStream(bufferingPolicy: bufferingPolicy).makeAsyncIterator()
            pendingInitialValue = emitsInitialValue ? store.get(key) : nil
        }

        // MARK: AsyncIteratorProtocol Implementation

        public mutating func next() async -> Key.Value? {
            if let pendingInitialValue {
                self.pendingInitialValue = nil

                return pendingInitialValue
            }

            return await streamIterator.next()
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

    internal func makeStream(bufferingPolicy: PersistentKeyValues<Key>.BufferingPolicy) -> AsyncStream<Key.Value> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            state.setContinuation(continuation)

            continuation.onTermination = { [weak self] _ in
                self?.deregister()
            }

            store.register(
                observer: self,
                for: key,
                with: nil,
                and: #selector(didReceive(_:))
            )
        }
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

        yieldCurrentValue()
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

        yieldCurrentValue()
    }

    // MARK: Private Instance Interface

    private nonisolated func deregister() {
        guard state.markDeregistered() else {
            return
        }

        store.deregister(self, for: key, context: nil)
    }

    private nonisolated func yieldCurrentValue() {
        guard let continuation = state.currentContinuation() else {
            return
        }

        continuation.yield(store.get(key))
    }
}

// MARK: - State Definition

extension Observer {
    /// Mutable state protected by `NSLock`.
    private final class State: @unchecked Sendable {
        private let lock: NSLock
        private var continuation: AsyncStream<Key.Value>.Continuation?
        private var isDeregistered: Bool

        init() {
            lock = NSLock()
            continuation = nil
            isDeregistered = false
        }

        func currentContinuation() -> AsyncStream<Key.Value>.Continuation? {
            withLock {
                continuation
            }
        }

        func markDeregistered() -> Bool {
            withLock {
                guard !isDeregistered else {
                    return false
                }

                isDeregistered = true
                continuation = nil

                return true
            }
        }

        func setContinuation(_ continuation: AsyncStream<Key.Value>.Continuation) {
            withLock {
                self.continuation = continuation
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
