//
//  UserDefaultsKeyChangeObservationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// Tests observation of `UserDefaults` keys whose identifiers contain a period, which key-value observation cannot
/// observe.
final class UserDefaultsKeyChangeObservationTests: XCTestCase {
    private var storage: InstrumentedUserDefaults!
    private var suiteName: String!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("UserDefaultsKeyChangeObservationTests", function: name)
        storage = try XCTUnwrap(InstrumentedUserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        storage.removePersistentDomain(forName: suiteName)
        storage = nil
        suiteName = nil
    }
}

// MARK: - Ordering Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_register_deliversChangeMadeDuringFirstRead() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)

        storage.instrument(key.id)
        storage.afterNextRead { [storage] in
            storage?.set(1, forKey: key.id)
        }

        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        XCTAssertEqual(storage.get(key), 1)
        XCTAssertEqual(observer.observations.count, 1)

        storage.deregister(observer, for: key, context: nil)
    }

    func test_publisher_staleReadDoesNotSuppressLaterChange() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        var values: [Int] = []

        storage.set(0, forKey: key.id)

        let cancellable = storage.publisher(for: key).sink { value in
            values.append(value)
        }

        // The change to `2` is reported while the change to `1` is still being read.
        storage.instrument(key.id)
        storage.afterNextRead { [storage] in
            storage?.set(2, forKey: key.id)
        }

        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.get(key), 2)
        XCTAssertEqual(values.last, 2)

        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.get(key), 1)
        XCTAssertEqual(values.last, 1)

        cancellable.cancel()
    }

    func test_register_callbackDuringRegistrationCanDeregister() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let observer = DeregisteringKeyObserver(store: storage, key: key)

        NotificationObserverInstallationHook.perform(
            afterInstallingObserverFor: UserDefaults.didChangeNotification,
            action: { [storage] in
                storage?.set(1, forKey: key.id)
            },
            during: {
                storage.register(
                    observer: observer,
                    for: key,
                    with: nil,
                    and: #selector(DeregisteringKeyObserver.didReceive(_:))
                )
            }
        )

        storage.set(2, forKey: key.id)
        storage.set(3, forKey: key.id)

        XCTAssertEqual(observer.callbackCount, 1)
    }

    func test_register_concurrentChangesDeliverLatestValue() async {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let recorder = LatestValueRecorder()
        // `UserDefaults` is thread-safe but not declared `Sendable`.
        nonisolated(unsafe) let storage: UserDefaults = storage

        let cancellable = storage.publisher(for: key).sink { value in
            recorder.record(value)
        }

        await withTaskGroup(of: Void.self) { group in
            for writer in 0 ..< 4 {
                group.addTask {
                    for value in 1 ... 50 {
                        storage.set(writer * 100 + value, forKey: key.id)
                    }
                }
            }
        }

        storage.set(-1, forKey: key.id)

        XCTAssertEqual(recorder.latestValue, -1)

        cancellable.cancel()
    }
}

// MARK: - Shared Read Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_register_notifiesOnlyWhenCollectionValueChanges() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: [String]())

        storage.set(key, to: ["first"])
        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.set(1, forKey: "com.example.unrelated.\(#function)")
        storage.set(key, to: ["first"])
        storage.set(2, forKey: "com.example.unrelated.\(#function)")

        XCTAssertTrue(observer.observations.isEmpty)

        storage.set(key, to: ["first", "second"])

        XCTAssertEqual(observer.observations.count, 1)

        storage.deregister(observer, for: key, context: nil)
    }

    func test_register_registrationsForSameKeyShareOneRead() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let observers = (0 ..< 3).map { _ in
            RecordingKeyObserver()
        }

        for observer in observers {
            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        storage.instrument(key.id)
        storage.set(1, forKey: "com.example.unrelated.\(#function)")

        XCTAssertEqual(storage.readCount, 1)
        XCTAssertTrue(observers.allSatisfy { $0.observations.isEmpty })

        storage.instrument(key.id)
        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.readCount, 1)
        XCTAssertTrue(observers.allSatisfy { $0.observations.count == 1 })

        for observer in observers {
            storage.deregister(observer, for: key, context: nil)
        }

        storage.instrument(key.id)
        storage.set(2, forKey: key.id)

        XCTAssertEqual(storage.readCount, 0)
    }

    func test_register_observerDeregisteredByEarlierObserverIsNotNotified() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let laterObserver = RecordingKeyObserver()
        let earlierObserver = DeregisteringKeyObserver(store: storage, key: key, deregistering: laterObserver)

        storage.register(observer: earlierObserver, for: key, with: nil, and: #selector(DeregisteringKeyObserver.didReceive(_:)))
        storage.register(observer: laterObserver, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.set(1, forKey: key.id)

        XCTAssertEqual(earlierObserver.callbackCount, 1)
        XCTAssertTrue(laterObserver.observations.isEmpty)
    }
}

// MARK: - Key Identity Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_deregister_distinguishesCanonicallyEquivalentKeys() {
        let observer = RecordingKeyObserver()
        let composedKey = PersistentKey("caf\u{E9}.\(#function)", defaultValue: 0)
        let decomposedKey = PersistentKey("cafe\u{301}.\(#function)", defaultValue: 0)

        storage.register(observer: observer, for: composedKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.register(observer: observer, for: decomposedKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.deregister(observer, for: composedKey, context: nil)

        storage.set(1, forKey: composedKey.id)

        XCTAssertTrue(observer.observations.isEmpty)

        storage.set(1, forKey: decomposedKey.id)

        XCTAssertEqual(observer.observations.map(\.keyPath), [decomposedKey.id])
        XCTAssertTrue(observer.observations.first?.keyPath?.utf16.elementsEqual(decomposedKey.id.utf16) ?? false)

        storage.deregister(observer, for: decomposedKey, context: nil)
    }
}

// MARK: - Monitor Lifecycle Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_monitor_doesNotActivateInvalidatedObservation() {
        let observer = RecordingKeyObserver()
        let keyID = "com.example.key.\(#function)"
        let observation = UserDefaultsKeyChangeObservation(
            observer: observer,
            keyID: keyID,
            context: nil,
            monitor: .monitor(for: storage)
        )

        // A deregistration that races registration invalidates the observation before it is activated.
        observation.invalidate()
        observation.activate()

        storage.instrument(keyID)
        storage.set(1, forKey: keyID)

        XCTAssertEqual(storage.readCount, 0)
        XCTAssertTrue(observer.observations.isEmpty)
    }

    func test_monitor_ignoresChangesAfterItsInstanceIsReleased() throws {
        let observer = RecordingKeyObserver()
        let keyID = "com.example.key.\(#function)"
        let monitor: UserDefaultsKeyChangeMonitor
        weak var releasedUserDefaults: UserDefaults?

        do {
            let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            releasedUserDefaults = userDefaults
            monitor = .monitor(for: userDefaults)

            monitor.add(
                UserDefaultsKeyChangeObservation(observer: observer, keyID: keyID, context: nil, monitor: monitor)
            )
        }

        XCTAssertNil(releasedUserDefaults)

        storage.set(1, forKey: keyID)

        XCTAssertTrue(observer.observations.isEmpty)
    }
}

// MARK: - DeregisteringKeyObserver Definition

/// An observer that deregisters itself, or another observer, when it receives its first callback.
private final class DeregisteringKeyObserver: NSObject, @unchecked Sendable {
    private(set) var callbackCount = 0

    private let key: PersistentKey<Int>
    private let observerToDeregister: NSObject?
    private let store: UserDefaults

    init(store: UserDefaults, key: PersistentKey<Int>, deregistering observerToDeregister: NSObject? = nil) {
        self.key = key
        self.observerToDeregister = observerToDeregister
        self.store = store
    }

    @objc
    func didReceive(_ notification: Notification) {
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        callbackCount += 1

        store.deregister(observerToDeregister ?? self, for: key, context: nil)
    }
}

// MARK: - LatestValueRecorder Definition

/// Records the latest value delivered on any thread.
private final class LatestValueRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int?

    var latestValue: Int? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return value
    }

    func record(_ value: Int) {
        lock.lock()
        defer {
            lock.unlock()
        }

        self.value = value
    }
}
