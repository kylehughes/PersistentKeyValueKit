//
//  ObservablePersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/2/26.
//

import Foundation
import PersistentKeyValueKit

final class ObservablePersistentKeyValueStore: PersistentKeyValueStore, @unchecked Sendable {
    private var deregistrationHandler: (() -> Void)?
    private var deregistrations: Int
    private let lock: NSLock
    private var observations: [Observation]
    private var registrationHandler: (() -> Void)?
    private var registrations: Int
    private var retainedObservers: [NSObject]
    private var storage: [String: Any]

    /// Whether the store keeps a strong reference to every registered observer, even after deregistration, so tests
    /// can deliver a notification that races deregistration.
    var retainsObservers: Bool {
        get {
            withLock {
                isRetainingObservers
            }
        }
        set {
            withLock {
                isRetainingObservers = newValue
            }
        }
    }

    private var isRetainingObservers: Bool

    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            throw PersistentKeyMigrationError.missingMigrationDomain
        }
    }

    init() {
        deregistrationHandler = nil
        deregistrations = 0
        lock = NSLock()
        observations = []
        registrationHandler = nil
        isRetainingObservers = false
        registrations = 0
        retainedObservers = []
        storage = [:]
    }

    var deregistrationCount: Int {
        withLock {
            deregistrations
        }
    }

    var registrationCount: Int {
        withLock {
            registrations
        }
    }

    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        let handler = withLock {
            deregistrations += 1
            observations.removeAll {
                $0.observer === observer && $0.keyID == key.id && $0.context == context
            }

            let handler = deregistrationHandler
            deregistrationHandler = nil

            return handler
        }

        handler?()
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        let storedValue = withLock {
            storage[key.id]
        }

        return storedValue as? Key.Value ?? key.defaultValue
    }

    /// Notifies every observer retained by ``retainsObservers``, including deregistered ones.
    func notifyRetainedObservers(keyPath: String?) {
        let observers = withLock {
            retainedObservers
        }

        for observer in observers {
            observer.observeValue(forKeyPath: keyPath, of: self, change: nil, context: nil)
        }
    }

    /// Runs `handler` once, after the next deregistration is removed.
    func onNextDeregistration(_ handler: @escaping () -> Void) {
        withLock {
            deregistrationHandler = handler
        }
    }

    func onNextRegistration(_ handler: @escaping () -> Void) {
        withLock {
            registrationHandler = handler
        }
    }

    func notifyObservers(keyPath: String?) {
        let observations = withLock {
            liveObservations()
        }

        notify(observations, keyPath: keyPath)
    }

    /// Delivers `notification` to every live observer through the selector it registered, without filtering by key.
    func postToObservers(_ notification: Notification) {
        let observations = withLock {
            liveObservations()
        }

        for observation in observations {
            _ = observation.observer?.perform(observation.selector, with: notification)
        }
    }

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        let handler = withLock {
            registrations += 1
            if isRetainingObservers {
                retainedObservers.append(observer)
            }
            observations.append(
                Observation(
                    observer: observer,
                    keyID: key.id,
                    context: context,
                    selector: selector
                )
            )

            let handler = registrationHandler
            registrationHandler = nil

            return handler
        }

        handler?()
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        let observations = withLock {
            storage.removeValue(forKey: key.id)

            return liveObservations(for: key.id)
        }

        notify(observations, keyPath: key.id)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        let observations = withLock {
            storage[key.id] = value

            return liveObservations(for: key.id)
        }

        notify(observations, keyPath: key.id)
    }

    private func liveObservations() -> [Observation] {
        observations.removeAll { $0.observer == nil }

        return observations
    }

    private func liveObservations(for keyID: String) -> [Observation] {
        liveObservations().filter {
            $0.keyID == keyID
        }
    }

    private func notify(_ observations: [Observation], keyPath: String?) {
        for observation in observations {
            observation.observer?.observeValue(
                forKeyPath: keyPath,
                of: self,
                change: nil,
                context: observation.context
            )
        }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return body()
    }
}

extension ObservablePersistentKeyValueStore {
    private struct Observation {
        weak var observer: NSObject?
        let keyID: String
        let context: UnsafeMutableRawPointer?
        let selector: Selector
    }
}
