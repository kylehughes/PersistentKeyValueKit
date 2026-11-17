//
//  UserDefaultsKeyChangeMonitor.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import ObjectiveC

// MARK: - UserDefaultsKeyChangeObservation Definition

/// Delivers changes to a defaults key that key-value observation cannot observe.
///
/// The observation joins the ``UserDefaultsKeyChangeMonitor`` of its `UserDefaults` instance when it is activated, and
/// leaves it when it is invalidated.
///
/// - Important: This type is manually `Sendable` because its monitor delivers changes on the thread that reconciles
///   them. Its stored properties are immutable after initialization except `isInvalidated`, which is protected by the
///   monitor's lock, and `observer` is a weak reference.
internal final class UserDefaultsKeyChangeObservation: NSObject, StoreKeyObservation, @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    let keyID: String
    private(set) weak var observer: NSObject?

    /// Whether the observation has been invalidated. Protected by the monitor's lock.
    fileprivate var isInvalidated: Bool

    private let monitor: UserDefaultsKeyChangeMonitor

    // MARK: Internal Initialization

    init(
        observer: NSObject,
        keyID: String,
        context: UnsafeMutableRawPointer?,
        monitor: UserDefaultsKeyChangeMonitor
    ) {
        self.context = context
        self.keyID = keyID
        self.monitor = monitor
        self.observer = observer

        isInvalidated = false

        super.init()
    }

    // MARK: StoreKeyObservation Implementation

    func activate() {
        monitor.add(self)
    }

    func invalidate() {
        monitor.remove(self)
    }
}

// MARK: - UserDefaultsKeyChangeMonitor Definition

/// Reconciles the observed defaults keys of one `UserDefaults` instance after every in-process defaults change.
///
/// Foundation posts `UserDefaults.didChangeNotification` for changes made in the current process, from any instance.
/// Instances for the same suite share values, so the monitor listens to every instance and rereads each observed key,
/// notifying its observers only when the key's property-list value differs from the last value read. Registrations for
/// the same key share one read and one comparison value.
///
/// One caller reconciles at a time. A change reported while another caller reconciles, including one made by an
/// overridden getter or an observer during the reconciliation, is reconciled by that caller before it finishes. Reads
/// and observer callbacks run without the lock held, so they can access the store and its observations again. Each
/// key's comparison value is replaced only by a later read, so a stale read can never suppress a later change.
///
/// - Important: This type is manually `Sendable` because notifications are delivered on the posting thread. Access to
///   mutable state is protected by `lock`, and `userDefaults` is a weak reference.
internal final class UserDefaultsKeyChangeMonitor: NSObject, @unchecked Sendable {
    private let lock: NSLock

    private var hasPendingChange: Bool
    private var isReconciling: Bool
    private var observedKeys: [ObservedKey]

    // The instance retains its monitor, so a strong reference would form a cycle.
    private weak var userDefaults: UserDefaults?

    // MARK: Private Initialization

    private init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults

        hasPendingChange = false
        isReconciling = false
        lock = NSLock()
        observedKeys = []

        super.init()

        // The monitor listens before any key is read, so every change after a key's first read is reconciled.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    // MARK: Deinitialization

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Internal Static Interface

    /// Returns the monitor for the given instance, creating it the first time it is requested.
    ///
    /// The monitor is retained by the instance, so it lives exactly as long as the instance.
    internal static func monitor(for userDefaults: UserDefaults) -> UserDefaultsKeyChangeMonitor {
        creationLock.lock()
        defer {
            creationLock.unlock()
        }

        if let monitor = objc_getAssociatedObject(userDefaults, associationAddress) as? UserDefaultsKeyChangeMonitor {
            return monitor
        }

        let monitor = UserDefaultsKeyChangeMonitor(userDefaults: userDefaults)
        objc_setAssociatedObject(userDefaults, associationAddress, monitor, .OBJC_ASSOCIATION_RETAIN)

        return monitor
    }

    // MARK: Internal Instance Interface

    /// Starts delivering changes to `observation`, unless it has already been invalidated.
    internal func add(_ observation: UserDefaultsKeyChangeObservation) {
        let isAdded = withLock {
            guard !observation.isInvalidated else {
                return false
            }

            if let observedKey = observedKey(for: observation.keyID) {
                observedKey.observations.append(observation)
            } else {
                observedKeys.append(ObservedKey(observation: observation))
            }

            return true
        }

        guard isAdded else {
            return
        }

        // A new key's first read becomes its comparison value without notifying observers.
        reconcile()
    }

    /// Stops delivering changes to `observation`.
    internal func remove(_ observation: UserDefaultsKeyChangeObservation) {
        let released = withLock {
            observation.isInvalidated = true

            guard let index = observedKeys.firstIndex(where: { $0.observations.contains { $0 === observation } }) else {
                return nil as ObservedKey?
            }

            let observedKey = observedKeys[index]

            observedKey.observations.removeAll {
                $0 === observation
            }

            guard observedKey.observations.isEmpty else {
                return nil
            }

            observedKeys.remove(at: index)

            return observedKey
        }

        // Release the key's comparison value after the lock is unlocked.
        withExtendedLifetime(released) {}
    }

    // MARK: Private Static Interface

    private static let associationToken = UserDefaultsKeyChangeMonitorAssociationKey()

    private static let creationLock = NSLock()

    private static var associationAddress: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(associationToken).toOpaque())
    }

    // MARK: Private Instance Interface

    /// Returns the observed key with the given identifier. Must be called with the lock held.
    private func observedKey(for keyID: String) -> ObservedKey? {
        observedKeys.first {
            StoreKeyObservationRegistry.keyIDsMatch($0.keyID, keyID)
        }
    }

    /// Reads and compares observed keys until no reconciliation is pending.
    ///
    /// Only one caller reconciles at a time. Another caller records its work and returns, and the reconciling caller
    /// performs it before finishing.
    private func reconcile() {
        guard beginReconciling() else {
            return
        }

        while let pendingKeys = takePendingKeys() {
            for observedKey in pendingKeys {
                reconcile(observedKey)
            }
        }
    }

    private func reconcile(_ observedKey: ObservedKey) {
        guard let userDefaults else {
            return
        }

        // Read without the lock held: an overridden getter can write the store and report a change synchronously.
        let object = userDefaults.object(forKey: observedKey.keyID)

        let (observations, replacedObject) = withLock {
            observedKey.record(object)
        }

        // Release the replaced comparison value after the lock is unlocked.
        withExtendedLifetime(replacedObject) {}

        for observation in observations {
            // An observer notified earlier in this loop can deregister a later one.
            guard let observer = observation.observer, !withLock({ observation.isInvalidated }) else {
                continue
            }

            observer.observeValue(
                forKeyPath: observedKey.keyID,
                of: userDefaults,
                change: [.kindKey: NSKeyValueChange.setting.rawValue],
                context: observation.context
            )
        }
    }

    /// Returns whether the caller became responsible for reconciling.
    private func beginReconciling() -> Bool {
        withLock {
            guard !isReconciling else {
                return false
            }

            isReconciling = true

            return true
        }
    }

    /// Returns the keys to read next, or releases reconciliation and returns `nil` when none remain.
    ///
    /// After a change, every key with a live observer is read. Otherwise, only keys without a comparison value are.
    private func takePendingKeys() -> [ObservedKey]? {
        withLock {
            let isChange = hasPendingChange
            hasPendingChange = false

            let pendingKeys = observedKeys.filter { observedKey in
                guard observedKey.hasLiveObserver else {
                    // Without a live observer the key is not read, so its comparison value would become stale.
                    observedKey.invalidateLastObject()

                    return false
                }

                return isChange || !observedKey.hasLastObject
            }

            guard !pendingKeys.isEmpty else {
                // Release reconciliation while holding the lock so a concurrent change cannot be recorded between the
                // final check and the release.
                isReconciling = false

                return nil
            }

            return pendingKeys
        }
    }

    @objc
    private func userDefaultsDidChange(_ notification: Notification) {
        withLock {
            hasPendingChange = true
        }

        reconcile()
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return body()
    }
}

// MARK: - ObservedKey Definition

extension UserDefaultsKeyChangeMonitor {
    /// The registrations for one key and the key's last read property-list value.
    ///
    /// Every property is protected by the monitor's lock, except the immutable `keyID`.
    private final class ObservedKey {
        let keyID: String
        var observations: [UserDefaultsKeyChangeObservation]

        private(set) var hasLastObject: Bool
        private var lastObject: Any?

        init(observation: UserDefaultsKeyChangeObservation) {
            keyID = observation.keyID
            observations = [observation]

            hasLastObject = false
            lastObject = nil
        }

        var hasLiveObserver: Bool {
            observations.contains {
                $0.observer != nil
            }
        }

        /// Makes the next read the key's comparison value without notifying observers.
        ///
        /// The previous value is kept until that read replaces it, so it is never released with the lock held.
        func invalidateLastObject() {
            hasLastObject = false
        }

        /// Records a read and returns the observations to notify, plus the replaced value for release after unlocking.
        func record(_ object: Any?) -> ([UserDefaultsKeyChangeObservation], Any?) {
            let replacedObject = lastObject

            // Keep the latest read even when it is equal, so the next read of an unchanged value is the same object.
            lastObject = object

            guard hasLastObject else {
                hasLastObject = true

                return ([], replacedObject)
            }

            guard
                !Self.isSameObject(replacedObject, object),
                !PropertyListMigrationStorage.equal(replacedObject, object)
            else {
                return ([], replacedObject)
            }

            return (observations, replacedObject)
        }

        /// Returns whether two reads returned the same object, which makes a recursive comparison unnecessary.
        ///
        /// `UserDefaults` returns immutable values and keeps returning its cached object until the value changes, so
        /// an unrelated change usually rereads the identical object. Numbers are always compared by value, because
        /// tagged-pointer numbers are not documented to keep their types distinct by identity.
        private static func isSameObject(_ lhs: Any?, _ rhs: Any?) -> Bool {
            guard let lhs = lhs as AnyObject?, let rhs = rhs as AnyObject?, !(lhs is NSNumber) else {
                return false
            }

            return lhs === rhs
        }
    }
}

// MARK: - UserDefaultsKeyChangeMonitorAssociationKey Definition

// A stable object address gives Objective-C associations an immutable process-local key without a mutable global.
private final class UserDefaultsKeyChangeMonitorAssociationKey: Sendable {
}
