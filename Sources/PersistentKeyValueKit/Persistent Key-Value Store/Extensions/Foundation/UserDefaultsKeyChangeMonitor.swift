//
//  UserDefaultsKeyChangeMonitor.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Darwin
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
///   monitor's lock, and `lastObject`, which only the monitor accesses as it describes. `observer` is a weak reference.
internal final class UserDefaultsKeyChangeObservation: NSObject, StoreKeyObservation, @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    let keyID: String
    private(set) weak var observer: NSObject?

    /// Whether the observation has been invalidated. Protected by the monitor's lock.
    fileprivate var isInvalidated: Bool

    /// The key's property-list value when it was last read for this observation, which the next read is compared with.
    ///
    /// The monitor sets it before the observation joins its key, and then only the reconciling caller reads and
    /// replaces it, without the lock held.
    fileprivate var lastObject: Any?

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
        lastObject = nil

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
/// Instances for the same suite share values, so the monitor listens to every instance and, after each change, rereads
/// every observed key once. Each registration keeps its own comparison value, the key's value when it was last read
/// for that registration, and is notified when a read differs from it.
///
/// Changes are sampled rather than queued. A registration reads its first comparison value before it returns, and it
/// is notified only by reads made after it joined its key, so a change already reflected in its first read is never
/// delivered to it as a change. Changes between two reads produce at most one notification, and changes that restore
/// a registration's comparison value produce none. A registration added on the thread that is reading its key for
/// another registration, such as from an overridden getter, shares that read instead of calling the getter again, so
/// its first comparison value is the value that read returns.
///
/// One caller reconciles at a time, and each of its passes reads only the registrations present when the pass begins.
/// A change reported while another caller reconciles, or while a registration reads its first comparison value,
/// including one made by an overridden getter, an equality check, or an observer, is reconciled by a later pass before
/// the reconciling caller finishes. A comparison value is replaced only by a later read, so a stale read can never
/// suppress a later change.
///
/// The lock is never held while running code that can access the store or its observations. Reads, comparisons, and
/// observer callbacks run after it is unlocked, and no reference whose release can deinitialize an observer is released
/// while it is held.
///
/// - Important: This type is manually `Sendable` because notifications are delivered on the posting thread. Access to
///   mutable state is protected by `lock`, except each registration's comparison value, which is set before the
///   registration joins its key and then accessed only by the reconciling caller, and `userDefaults` is a weak
///   reference.
internal final class UserDefaultsKeyChangeMonitor: NSObject, @unchecked Sendable {
    private let lock: NSLock

    /// The number of changes reported, which tells a registration whether a change was reported during its first read.
    private var changeCount: Int
    private var hasPendingChange: Bool
    private var isReconciling: Bool
    private var observedKeys: [ObservedKey]
    private var pendingReads: [PendingRead]

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
        pendingReads = []

        super.init()

        // The monitor listens before any key is read, so every change after a registration's first read is reconciled.
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
    /// The observation's first comparison value is read before this returns, unless this thread is already reading
    /// the key for another registration, in which case the observation shares that read.
    internal func add(_ observation: UserDefaultsKeyChangeObservation) {
        let thread = pthread_self()

        let read: PendingRead? = withLock {
            guard !observation.isInvalidated else {
                return nil
            }

            // An overridden getter that registers its own key would otherwise read, and register, without end.
            if let pendingRead = pendingReads.first(where: { $0.isReading(observation.keyID, on: thread) }) {
                pendingRead.observations.append(observation)

                return nil
            }

            let read = PendingRead(observation: observation, thread: thread, changeCountBeforeRead: changeCount)
            pendingReads.append(read)

            return read
        }

        guard let read else {
            return
        }

        // Read without the lock held: an overridden getter can write the store, report a change, or register.
        let object = userDefaults?.object(forKey: read.keyID)

        let isChangedDuringRead = withLock {
            pendingReads.removeAll {
                $0 === read
            }

            // An observation can be invalidated during the read.
            let observations = read.observations.filter {
                !$0.isInvalidated
            }

            guard !observations.isEmpty else {
                return false
            }

            // The observations have no comparison value yet, so assigning one releases nothing.
            for observation in observations {
                observation.lastObject = object
            }

            let index = observedKeys.firstIndex {
                StoreKeyObservationRegistry.keyIDsMatch($0.keyID, read.keyID)
            }

            if let index {
                observedKeys[index].observations.append(contentsOf: observations)
            } else {
                observedKeys.append(ObservedKey(keyID: read.keyID, observations: observations))
            }

            guard changeCount == read.changeCountBeforeRead else {
                // A change reported during the read was reconciled without these observations, so reconcile again.
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
        withLock {
            observation.isInvalidated = true

            guard let index = observedKeys.firstIndex(where: { $0.observations.contains { $0 === observation } }) else {
                return
            }

            // The caller holds `observation`, so removing it does not release it or its comparison value.
            observedKeys[index].observations.removeAll {
                $0 === observation
            }

            if observedKeys[index].observations.isEmpty {
                observedKeys.remove(at: index)
            }
        }
    }

    // MARK: Private Static Interface

    private static let associationToken = UserDefaultsKeyChangeMonitorAssociationKey()

    private static let creationLock = NSLock()

    private static var associationAddress: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(associationToken).toOpaque())
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

    // MARK: Private Instance Interface

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

    /// Reads `observedKey` once and notifies each of its registrations whose comparison value differs from the read.
    private func reconcile(_ observedKey: ObservedKey) {
        guard let userDefaults else {
            return
        }

        // Read, compare, and notify without the lock held: an overridden getter, `isEqual(_:)`, or an observer can
        // write the store, report a change synchronously, register, or deregister.
        let object = userDefaults.object(forKey: observedKey.keyID)

        // Registrations usually share a comparison value, so an identical one reuses the previous result.
        var previousComparison: (lastObject: Any?, isChanged: Bool)?

        for observation in observedKey.observations {
            let lastObject = observation.lastObject

            // The latest read is kept even when it is equal, so the next read of an unchanged value is the same object.
            observation.lastObject = object

            let isChanged: Bool

            if let previousComparison, Self.isSameObject(previousComparison.lastObject, lastObject) {
                isChanged = previousComparison.isChanged
            } else {
                isChanged = !Self.isSameObject(lastObject, object)
                    && !PropertyListMigrationStorage.equal(lastObject, object)
                previousComparison = (lastObject, isChanged)
            }

            // An observer notified earlier in this loop can deregister a later one.
            guard isChanged, let observer = observation.observer, !withLock({ observation.isInvalidated }) else {
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

    /// Returns the observed keys, with the registrations each has when the pass begins, to read after a change, or
    /// releases reconciliation and returns `nil` when no change is pending.
    ///
    /// A key is read even when its observers have been deallocated, so its comparison values stay current until its
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
    /// The registrations for one key, which share each read of the key.
    private struct ObservedKey {
        let keyID: String
        var observations: [UserDefaultsKeyChangeObservation]
    }
}

// MARK: - PendingRead Definition

extension UserDefaultsKeyChangeMonitor {
    /// A thread's read of a key's first comparison value, and the registrations that share it.
    ///
    /// `observations` is protected by the monitor's lock.
    private final class PendingRead {
        let changeCountBeforeRead: Int
        let keyID: String
        var observations: [UserDefaultsKeyChangeObservation]

        private let thread: pthread_t

        init(observation: UserDefaultsKeyChangeObservation, thread: pthread_t, changeCountBeforeRead: Int) {
            self.changeCountBeforeRead = changeCountBeforeRead
            self.thread = thread

            keyID = observation.keyID
            observations = [observation]
        }

        /// Returns whether this is a read of `keyID` on `thread`.
        ///
        /// The reading thread is running until the read is removed, so its identifier cannot be reused meanwhile.
        func isReading(_ keyID: String, on thread: pthread_t) -> Bool {
            pthread_equal(self.thread, thread) != 0 && StoreKeyObservationRegistry.keyIDsMatch(self.keyID, keyID)
        }
    }
}

// MARK: - UserDefaultsKeyChangeMonitorAssociationKey Definition

// A stable object address gives Objective-C associations an immutable process-local key without a mutable global.
private final class UserDefaultsKeyChangeMonitorAssociationKey: Sendable {
}
