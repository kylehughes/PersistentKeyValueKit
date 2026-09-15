import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationObservationTests: XCTestCase {
    func testMemoryMovePublishesSourceRemovalAndDestinationTransfer() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let unrelated = PersistentKey<Int>("unrelated-\(#function)", defaultValue: 0)
        source.set(key, to: 7)
        var sourceValues: [Int] = []
        var destinationValues: [Int] = []
        var unrelatedValues: [Int] = []
        var subscriptions = Set<AnyCancellable>()
        source.changesPublisher(for: key).sink { sourceValues.append($0) }.store(in: &subscriptions)
        destination.changesPublisher(for: key).sink { destinationValues.append($0) }.store(
            in: &subscriptions)
        destination.changesPublisher(for: unrelated).sink { unrelatedValues.append($0) }.store(
            in: &subscriptions)
        _ = try source.move(key, to: destination, onConflict: .overwriteDestination)
        XCTAssertEqual(sourceValues, [0])
        XCTAssertEqual(destinationValues, [7])
        XCTAssertTrue(unrelatedValues.isEmpty)
    }

    func testDestinationMemoryObservationCanChangeSourceBeforeCleanup() throws {
        let suiteName = "MigrationObservation.\(UUID().uuidString)"
        let source = UserDefaults(suiteName: suiteName)!
        defer { source.removePersistentDomain(forName: suiteName) }
        let sourceStore = UserDefaultsMigrationStore(
            userDefaults: source, domainName: suiteName)
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        source.set(key, to: 1)
        var subscriptions = Set<AnyCancellable>()
        var changed = false
        destination.changesPublisher(for: key).sink { _ in
            if !changed {
                changed = true
                source.set(key, to: 2)
            }
        }.store(in: &subscriptions)
        let report = try sourceStore.move(key, to: destination, onConflict: .overwriteDestination)
        guard case .failed(.cleanup, let error) = report.outcomes[0].status else {
            return XCTFail("expected sourceChanged")
        }
        XCTAssertEqual(error as? PersistentKeyMigrationError, .sourceChanged)
        XCTAssertEqual(source.get(key), 2)
        XCTAssertEqual(destination.get(key), 1)
    }

    func testUnrelatedMemoryObservationStaysQuiet() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let other = PersistentKey<Int>("other-\(#function)", defaultValue: 0)
        source.set(key, to: 3)
        var values: [Int] = []
        var subscriptions = Set<AnyCancellable>()
        destination.changesPublisher(for: other).sink { values.append($0) }.store(in: &subscriptions)
        _ = try source.copy(key, to: destination, onConflict: .overwriteDestination)
        XCTAssertTrue(values.isEmpty)
    }

    func testUserDefaultsMovePublishesDestinationChange() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suite = "MigrationObservation.\(#function)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let destination = UserDefaultsMigrationStore(userDefaults: defaults, domainName: suite)
        let key = PersistentKey<String>(#function, defaultValue: "")
        source.set(key, to: "migrated")
        var values: [String] = []
        var subscriptions = Set<AnyCancellable>()
        defaults.changesPublisher(for: key).sink { values.append($0) }.store(in: &subscriptions)
        _ = try source.move(key, to: destination, onConflict: .overwriteDestination)
        XCTAssertEqual(values, ["migrated"])
        XCTAssertEqual(source.get(key), "")
    }

    func testUserDefaultsDestinationObserverCausesWriteFailure() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suite = "MigrationObservation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let destination = UserDefaultsMigrationStore(userDefaults: defaults, domainName: suite)
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        source.set(key, to: 1)
        var replaced = false
        var subscriptions = Set<AnyCancellable>()
        defaults.changesPublisher(for: key).sink { _ in
            if !replaced {
                replaced = true
                defaults.set(99, forKey: key.id)
            }
        }.store(in: &subscriptions)
        let report = try source.move(key, to: destination, onConflict: .overwriteDestination)
        guard case .failed(.write, let error) = report.outcomes[0].status else {
            return XCTFail("expected write failure")
        }
        XCTAssertEqual(error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(source.get(key), 1)
    }

    @available(watchOS 9.0, *)
    func testCloudSourceObserverRefillCausesRemovalFailure() throws {
        let raw = StrictMigrationUbiquitousStore()
        let source = UbiquitousKeyValueMigrationStore(
            store: raw, identity: .init(namespace: "observation", identifier: UUID().uuidString))
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        raw.set(Int64(1), forKey: key.id)
        var refilled = false
        var subscriptions = Set<AnyCancellable>()
        raw.changesPublisher(for: key).sink { _ in
            if !refilled {
                refilled = true
                raw.set(Int64(2), forKey: key.id)
            }
        }.store(in: &subscriptions)
        let report = try source.move(key, to: destination, onConflict: .overwriteDestination)
        guard case .failed(.cleanup, let error) = report.outcomes[0].status else {
            return XCTFail("expected cleanup failure")
        }
        XCTAssertEqual(error as? PersistentKeyMigrationError, .removalVerificationFailed)
        XCTAssertEqual(raw.storedValue(for: key.id) as? Int64, 2)
    }

    @available(watchOS 9.0, *)
    func testCloudDestinationObserverCausesWriteFailure() throws {
        let source = InMemoryPersistentKeyValueStore()
        let raw = StrictMigrationUbiquitousStore()
        let destination = UbiquitousKeyValueMigrationStore(
            store: raw, identity: .init(namespace: "observation", identifier: UUID().uuidString))
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        source.set(key, to: 1)
        var replaced = false
        var subscriptions = Set<AnyCancellable>()
        raw.changesPublisher(for: key).sink { _ in
            if !replaced {
                replaced = true
                raw.set(Int64(9), forKey: key.id)
            }
        }.store(in: &subscriptions)
        let report = try source.move(key, to: destination, onConflict: .overwriteDestination)
        guard case .failed(.write, let error) = report.outcomes[0].status else {
            return XCTFail("expected write failure")
        }
        XCTAssertEqual(error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(source.get(key), 1)
    }

    @available(watchOS 9.0, *)
    func testCloudCopyPublishesOneRelatedNotification() throws {
        let source = InMemoryPersistentKeyValueStore()
        let raw = StrictMigrationUbiquitousStore()
        let destination = UbiquitousKeyValueMigrationStore(
            store: raw, identity: .init(namespace: "observation", identifier: UUID().uuidString))
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let other = PersistentKey<Int>("other-\(#function)", defaultValue: 0)
        source.set(key, to: 4)
        var values: [Int] = []
        var unrelated: [Int] = []
        var subscriptions = Set<AnyCancellable>()
        raw.changesPublisher(for: key).sink { values.append($0) }.store(in: &subscriptions)
        raw.changesPublisher(for: other).sink { unrelated.append($0) }.store(in: &subscriptions)
        _ = try source.copy(key, to: destination, onConflict: .overwriteDestination)
        XCTAssertEqual(values, [4])
        XCTAssertTrue(unrelated.isEmpty)
    }

    func testMemoryCopyPublishesExactlyOneDestinationChange() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        source.set(key, to: 9)
        var values: [Int] = []
        var subscriptions = Set<AnyCancellable>()
        destination.changesPublisher(for: key).sink { values.append($0) }.store(in: &subscriptions)
        _ = try source.copy(key, to: destination, onConflict: .overwriteDestination)
        XCTAssertEqual(values, [9])
    }
}
