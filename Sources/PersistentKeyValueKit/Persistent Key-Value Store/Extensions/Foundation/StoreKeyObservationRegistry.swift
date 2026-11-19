//
//  StoreKeyObservationRegistry.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import ObjectiveC

/// A registration that delivers one Foundation store's changes for one key to one observer.
internal protocol StoreKeyObservation: AnyObject {
    /// The context supplied when the observer was registered.
    var context: UnsafeMutableRawPointer? { get }

    /// The identifier of the observed key.
    var keyID: String { get }

    /// The UTF-16 code units of ``keyID``, read once when the observation is created.
    ///
    /// The registry compares these with its lock held, so the observation must not read them from ``keyID`` on demand.
    var literalKeyID: [UInt16] { get }

    /// The registered observer, or `nil` after it has been deallocated.
    var observer: NSObject? { get }

    /// Starts delivering changes to the observer.
    ///
    /// The registry calls this once, after the observation is registered, so a callback delivered during activation
    /// can deregister it. Activation must have no lasting effect when ``invalidate()`` is called before or during it.
    func activate()

    /// Stops delivering changes to the observer.
    ///
    /// The registry calls this once, after the observation is removed. It can run before, during, or after
    /// ``activate()``, on any thread.
    func invalidate()
}

/// The observations registered with one Foundation store instance that are not delivered by key-value observation.
///
/// Registrations are tracked per observer, key, and context so deregistering one key leaves the observer's other
/// registrations intact. Key identifiers are compared literally, as Foundation compares keys, so canonically equivalent
/// spellings are different keys. Registrations whose observer has been deallocated are released on the next
/// registration or deregistration.
///
/// Activation, invalidation, and the release of any observer or observation reference run after the lock is unlocked,
/// because each can deregister from this registry again. Key identifiers are compared by code units read before the
/// lock is taken, because reading an identifier bridged from an `NSString` calls the object's methods, which can do the
/// same.
internal final class StoreKeyObservationRegistry: @unchecked Sendable {
    private let lock: NSLock
    private var observations: [any StoreKeyObservation]

    // MARK: Private Initialization

    private init() {
        lock = NSLock()
        observations = []
    }

    // MARK: Internal Static Interface

    /// Returns the registry for the given store, creating it the first time it is requested.
    ///
    /// The registry is retained by the store, so it lives exactly as long as the store instance.
    internal static func registry(for store: NSObject) -> StoreKeyObservationRegistry {
        creationLock.lock()
        defer {
            creationLock.unlock()
        }

        if let registry = objc_getAssociatedObject(store, associationAddress) as? StoreKeyObservationRegistry {
            return registry
        }

        let registry = StoreKeyObservationRegistry()
        objc_setAssociatedObject(store, associationAddress, registry, .OBJC_ASSOCIATION_RETAIN)

        return registry
    }

    /// Returns whether two key identifiers name the same Foundation store key.
    ///
    /// Foundation compares keys by their UTF-16 code units, while Swift `String` equality treats canonically
    /// equivalent spellings, such as precomposed and decomposed accents, as equal.
    internal static func keyIDsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }

    /// Returns the UTF-16 code units of `keyID`, which name the same Foundation store key exactly when they are equal.
    ///
    /// Reading the code units of an identifier bridged from an `NSString` calls the object's methods, which can run
    /// arbitrary code, such as a subclass's character accessor that accesses a store. Code that compares identifiers
    /// with a lock held therefore reads them first, without the lock, and compares the results.
    internal static func literalKeyID(_ keyID: String) -> [UInt16] {
        Array(keyID.utf16)
    }

    // MARK: Internal Instance Interface

    /// Registers `observation`, then activates it.
    ///
    /// The observation is registered before it is activated, so a callback delivered during activation can deregister
    /// it.
    internal func insert(_ observation: any StoreKeyObservation) {
        let (removed, liveObservers) = withLock {
            let removed = removeObservations { _, _ in
                false
            }

            observations.append(observation)

            return removed
        }

        // Release the observers after the lock is unlocked.
        withExtendedLifetime(liveObservers) {}

        for observation in removed {
            observation.invalidate()
        }

        observation.activate()
    }

    internal func remove(_ observer: NSObject, keyID: String, context: UnsafeMutableRawPointer?) {
        let literalKeyID = Self.literalKeyID(keyID)

        let (removed, liveObservers) = withLock {
            removeObservations { registeredObserver, observation in
                registeredObserver === observer
                    && observation.literalKeyID == literalKeyID
                    && observation.context == context
            }
        }

        // Release the observers after the lock is unlocked.
        withExtendedLifetime(liveObservers) {}

        for observation in removed {
            observation.invalidate()
        }
    }

    // MARK: Private Static Interface

    private static let associationToken = StoreKeyObservationRegistryAssociationKey()

    private static let creationLock = NSLock()

    private static var associationAddress: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(associationToken).toOpaque())
    }

    // MARK: Private Instance Interface

    /// Removes the observations whose observer has been deallocated or that `isRemoved` selects for their live
    /// observer, returning them and every live observer read. Must be called with the lock held.
    ///
    /// Reading a weak observer retains it, and that reference becomes the last one if the observer is released on
    /// another thread. A removed observation can hold the last reference to an identifier bridged from an `NSString`.
    /// Releasing either can run a `deinit` that deregisters, so the caller releases the returned references only after
    /// the lock is unlocked.
    private func removeObservations(
        where isRemoved: (NSObject, any StoreKeyObservation) -> Bool
    ) -> (removed: [any StoreKeyObservation], liveObservers: [NSObject]) {
        var liveObservers: [NSObject] = []
        var removed: [any StoreKeyObservation] = []

        observations.removeAll { observation in
            // An observer that deregisters from its own `deinit` already reads as `nil` here.
            guard let observer = observation.observer else {
                removed.append(observation)

                return true
            }

            liveObservers.append(observer)

            guard isRemoved(observer, observation) else {
                return false
            }

            removed.append(observation)

            return true
        }

        return (removed, liveObservers)
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return body()
    }
}

// A stable object address gives Objective-C associations an immutable process-local key without a mutable global.
private final class StoreKeyObservationRegistryAssociationKey: Sendable {
}
