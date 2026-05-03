//
//  ObservablePersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/2/26.
//

import Foundation
import PersistentKeyValueKit

final class ObservablePersistentKeyValueStore: PersistentKeyValueStore, @unchecked Sendable {
    private var deregistrations: Int
    private let lock: NSLock
    private var observations: [Observation]
    private var registrationHandler: (() -> Void)?
    private var registrations: Int
    private var storage: [String: Any]

    init() {
        deregistrations = 0
        lock = NSLock()
        observations = []
        registrationHandler = nil
        registrations = 0
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
        withLock {
            deregistrations += 1
            observations.removeAll {
                $0.observer === observer && $0.keyID == key.id && $0.context == context
            }
        }
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        let storedValue = withLock {
            storage[key.id]
        }

        return storedValue as? Key.Value ?? key.defaultValue
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

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        let handler = withLock {
            registrations += 1
            observations.append(
                Observation(
                    observer: observer,
                    keyID: key.id,
                    context: context
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
    }
}
