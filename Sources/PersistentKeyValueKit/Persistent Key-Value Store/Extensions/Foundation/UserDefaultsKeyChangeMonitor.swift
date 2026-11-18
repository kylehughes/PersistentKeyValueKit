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
/// A key's first registration reads the key's first comparison value before it returns, so every later change is
/// compared with it, even while another caller is reconciling. One caller reconciles at a time. A change reported while
/// another caller reconciles, including one made by an overridden getter, an equality check, or an observer during the
/// reconciliation, is reconciled by that caller before it finishes. Each key's comparison value is replaced only by a
/// later read, so a stale read can never suppress a later change.
///
/// The lock is never held while running code that can access the store or its observations. Reads, comparisons, and
/// observer callbacks run after it is unlocked, and no reference whose release can deinitialize an observer is released
/// while it is held.
///
/// - Important: This type is manually `Sendable` because notifications are delivered on the posting thread. Access to
///   mutable state is protected by `lock`, except each key's comparison value, which only the reconciling caller
///   accesses, and `userDefaults` is a weak reference.
internal final class UserDefaultsKeyChangeMonitor: NSObject, @unchecked Sendable {
    private let lock: NSLock

    /// The number of changes reported, which tells a registration whether a change was reported during its first read.
    private var changeCount: Int
    private var hasPendingChange: Bool
    private var isReconciling: Bool
    private var observedKeys: [ObservedKey]

    // The instance retains its monitor, so a strong reference would form a cycle.
    private weak var userDefaults: UserDefaults?

    // MARK: Private Initialization

    private init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults

        changeCount = 0
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
    ///
    /// When `observation` is the first registration for its key, the key's first comparison value is read before this
    /// returns.
    internal func add(_ observation: UserDefaultsKeyChangeObservation) {
        let changeCountBeforeRead: Int? = withLock {
            guard !observation.isInvalidated, !appendToObservedKey(observation) else {
                return nil
            }

            return changeCount
        }

        guard let changeCountBeforeRead else {
            return
        }

        // Read without the lock held: an overridden getter can write the store and report a change synchronously.
        let object = userDefaults?.object(forKey: observation.keyID)

        let isChangedDuringRead = withLock {
            // The observation can be invalidated, or another registration can add its key, during the read.
            guard !observation.isInvalidated, !appendToObservedKey(observation) else {
                return false
            }

            observedKeys.append(ObservedKey(observation: observation, lastObject: object))

            guard changeCount == changeCountBeforeRead else {
                // A change reported during the read was reconciled without this key, so reconcile again.
                hasPendingChange = true

                return true
            }

            return false
        }

        if isChangedDuringRead {
            reconcile()
        }
    }

    /// Stops delivering changes to `observation`.
    internal func remove(_ observation: UserDefaultsKeyChangeObservation) {
        let released = withLock {
            observation.isInvalidated = true

            guard let index = observedKeys.firstIndex(where: { $0.observations.contains { $0 === observation } }) else {
                return nil as ObservedKey?
            }

            let observedKey = observedKeys[index]

            // The caller holds `observation`, so removing it from the key does not release it.
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

    /// Adds `observation` to the registrations of its observed key and returns `true`, or returns `false` when its key
    /// is not observed. Must be called with the lock held.
    private func appendToObservedKey(_ observation: UserDefaultsKeyChangeObservation) -> Bool {
        let observedKey = observedKeys.first {
            StoreKeyObservationRegistry.keyIDsMatch($0.keyID, observation.keyID)
        }

        observedKey?.observations.append(observation)

        return observedKey != nil
    }

    /// Reads and compares observed keys until no change is pending.
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

        // Read and compare without the lock held: an overridden getter or `isEqual(_:)` can write the store, report a
        // change synchronously, or deregister.
        let object = userDefaults.object(forKey: observedKey.keyID)

        guard observedKey.recordRead(object) else {
            return
        }

        let observations = withLock {
            observedKey.observations
        }

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

    /// Returns every observed key to read after a change, or releases reconciliation and returns `nil` when no change
    /// is pending.
    ///
    /// A key is read even when its observers have been deallocated, so its comparison value stays current until its
    /// registrations are removed.
    private func takePendingKeys() -> [ObservedKey]? {
        withLock {
            guard hasPendingChange else {
                // Release reconciliation while holding the lock so a concurrent change cannot be recorded between the
                // final check and the release.
                isReconciling = false

                return nil
            }

            hasPendingChange = false

            return observedKeys
        }
    }

    @objc
    private func userDefaultsDidChange(_ notification: Notification) {
        withLock {
            changeCount &+= 1
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
    /// `observations` is protected by the monitor's lock. The last read value is set before the key is observed, and
    /// then only the reconciling caller reads and replaces it, without the lock held.
    private final class ObservedKey {
        let keyID: String
        var observations: [UserDefaultsKeyChangeObservation]

        private var lastObject: Any?

        init(observation: UserDefaultsKeyChangeObservation, lastObject: Any?) {
            keyID = observation.keyID
            observations = [observation]

            self.lastObject = lastObject
        }

        /// Records a read and returns whether it differs from the previous read.
        ///
        /// The latest read is kept even when it is equal, so the next read of an unchanged value is the same object.
        func recordRead(_ object: Any?) -> Bool {
            let previousObject = lastObject
            lastObject = object

            return !Self.isSameObject(previousObject, object)
                && !PropertyListMigrationStorage.equal(previousObject, object)
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
