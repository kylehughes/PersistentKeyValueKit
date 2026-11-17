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

    /// The registered observer, or `nil` after it has been deallocated.
    var observer: NSObject? { get }

    /// Stops delivering changes to the observer.
    func invalidate()
}

/// The observations registered with one Foundation store instance that are not delivered by key-value observation.
///
/// Registrations are tracked per observer, key, and context so deregistering one key leaves the observer's other
/// registrations intact. Registrations whose observer has been deallocated are released on the next registration or
/// deregistration.
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

    // MARK: Internal Instance Interface

    internal func insert(_ observation: any StoreKeyObservation) {
        let released = withLock {
            let released = observations.filter {
                $0.observer == nil
            }

            observations.removeAll {
                $0.observer == nil
            }

            observations.append(observation)

            return released
        }

        for observation in released {
            observation.invalidate()
        }
    }

    internal func remove(_ observer: NSObject, keyID: String, context: UnsafeMutableRawPointer?) {
        let removed = withLock {
            let isRemoved: (any StoreKeyObservation) -> Bool = { observation in
                // An observer that deregisters from its own `deinit` already reads as `nil` here.
                guard let registeredObserver = observation.observer else {
                    return true
                }

                return registeredObserver === observer
                    && observation.keyID == keyID
                    && observation.context == context
            }

            let removed = observations.filter(isRemoved)
            observations.removeAll(where: isRemoved)

            return removed
        }

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
