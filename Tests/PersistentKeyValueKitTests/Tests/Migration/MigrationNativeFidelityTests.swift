import CoreFoundation
import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// Covers native storage identity: literal key lookup, type-exact snapshot verification, and destination checks after
/// synchronous source cleanup.
final class MigrationNativeFidelityTests: XCTestCase {
    private let composed = "caf\u{E9}"
    private let decomposed = "cafe\u{301}"

    // MARK: Tests

    func testCleanupObserverThatChangesDestinationFailsDiscardedSource() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let observer = CallbackObserver {
            destination.set(key, to: 99)
        }

        source.set(key, to: 1)
        destination.set(key, to: 2)
        source.register(observer: observer, for: key, with: nil, and: #selector(CallbackObserver.observeValue))

        defer {
            source.deregister(observer, for: key, context: nil)
        }

        let report = try source.move(
            key,
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes[0].error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
        XCTAssertEqual(destination.get(key), 99)
        // A cleanup failure for a changed destination always follows the source's removal.
        XCTAssertNil(source.object(forKey: key.id))
    }

    func testCleanupObserverThatRemovesDestinationFailsMove() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.cleanup")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let observer = CallbackObserver {
            destination.remove(key)
        }

        defer {
            source.removePersistentDomain(forName: sourceName)
        }

        // The stored value equals the key's default, so only the persisted entry shows whether it was removed.
        source.set(key, to: 0)
        source.register(observer: observer, for: key, with: nil, and: #selector(CallbackObserver.observeValue))

        defer {
            source.deregister(observer, for: key, context: nil)
        }

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: recorder)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes[0].error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertFalse(recorder.get(.isMigrationCompleted(id: #function)))
        XCTAssertFalse(report.isComplete)
        XCTAssertNil(source.persistentDomain(forName: sourceName)?[key.id])
    }

    func testDefaultsDateWithUndefinedIntervalMigratesUnchanged() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.undefinedDate.source")
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.undefinedDate.destination")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))
        let stamp = PersistentKey("key:\(#function).stamp", defaultValue: Stamp.known(0), representation: StampCodec())
        let label = PersistentKey("key:\(#function).label", defaultValue: "missing")

        defer {
            source.removePersistentDomain(forName: sourceName)
            destination.removePersistentDomain(forName: destinationName)
        }

        source.set(stamp, to: .unknown)

        let moved = try source.move(stamp, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(moved.outcomes.map(\.status), [.moved])
        XCTAssertEqual(destination.get(stamp), .unknown)
        XCTAssertNil(source.persistentDomain(forName: sourceName)?[stamp.id])

        source.set(stamp, to: .unknown)

        let renamed = try source.move(
            .key(stamp, to: label) { _ in
                "unknown"
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(renamed.outcomes.map(\.status), [.moved])
        XCTAssertEqual(destination.get(label), "unknown")
        XCTAssertNil(source.persistentDomain(forName: sourceName)?[stamp.id])
    }

    func testDefaultsDestinationRejectsNumberThatStorageWouldChange() throws {
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.storedNumber")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))

        defer {
            destination.removePersistentDomain(forName: destinationName)
        }

        try assertNumbersThatStorageWouldChangeFailBeforeWriting(to: destination) {
            destination.persistentDomain(forName: destinationName)?[$0]
        }
    }

    func testDefaultsDictionaryWithKeysThatSwiftMergesFailsToDecode() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.mergedKeys")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<[String: Int]>("key:\(#function)", defaultValue: [:])

        defer {
            source.removePersistentDomain(forName: sourceName)
        }

        source.set(dictionary(5, 7), forKey: key.id)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.decode)])
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual((source.object(forKey: key.id) as? NSDictionary)?.count, 2)
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func testDefaultsDestinationCommitsEncodingThatValidationCannotConsume() throws {
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.consumingDecoder")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))

        defer {
            destination.removePersistentDomain(forName: destinationName)
        }

        try assertEncodingThatValidationCannotConsumeIsCommitted(to: destination)
    }

    func testDefaultsIntegerWidthMatchesOrdinaryAccess() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.integerWidth.source")
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.integerWidth.destination")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))

        defer {
            source.removePersistentDomain(forName: sourceName)
            destination.removePersistentDomain(forName: destinationName)
        }

        try assertIntegerWidthMatchesOrdinaryAccess(from: source, to: destination)
    }

    func testDefaultsOverwriteKeepsAnObserverWriteDuringFoundationEqualReplacement() throws {
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.equalReplacementObserver")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let observer = CallbackObserver {
            // Replacing a Foundation-equal value removes it first, which observers see as the key being absent.
            if destination.persistentDomain(forName: destinationName)?[key.id] == nil {
                destination.set(key, to: 99)
            }
        }

        defer {
            destination.removePersistentDomain(forName: destinationName)
        }

        source.set(key, to: 1)
        destination.set(PersistentKey<Bool>(key.id, defaultValue: false), to: true)
        destination.register(observer: observer, for: key, with: nil, and: #selector(CallbackObserver.observeValue))

        defer {
            destination.deregister(observer, for: key, context: nil)
        }

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes[0].error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
        XCTAssertEqual(destination.get(key), 99)
        XCTAssertEqual(source.get(key), 1)
    }

    func testDefaultsOverwriteReplacesFoundationEqualValueOfAnotherType() throws {
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.equalReplacement")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))

        defer {
            destination.removePersistentDomain(forName: destinationName)
        }

        try assertOverwriteReplacesFoundationEqualValueOfAnotherType(in: destination) {
            destination.persistentDomain(forName: destinationName)?[$0]
        }
    }

    func testDefaultsDestinationLookupDistinguishesNormalizationForms() throws {
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.destination")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))
        let source = InMemoryPersistentKeyValueStore()
        let oldKey = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let newKey = PersistentKey<Int>(decomposed, defaultValue: 0)

        defer {
            destination.removePersistentDomain(forName: destinationName)
        }

        destination.set(17, forKey: composed)
        source.set(oldKey, to: 28)

        let report = try source.move(
            .key(oldKey, to: newKey),
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(destination.object(forKey: decomposed) as? Int, 28)
        XCTAssertEqual(destination.object(forKey: composed) as? Int, 17)
    }

    func testDefaultsSourceLookupDistinguishesNormalizationForms() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.source")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let composedKey = PersistentKey<Int>(composed, defaultValue: 0)
        let decomposedKey = PersistentKey<Int>(decomposed, defaultValue: 0)

        defer {
            source.removePersistentDomain(forName: sourceName)
        }

        source.set(7, forKey: decomposed)

        let absent = try source.copy(
            composedKey,
            to: InMemoryPersistentKeyValueStore(),
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(absent.outcomes.map(\.status), [.sourceAbsent])

        source.removeObject(forKey: decomposed)
        source.set(5, forKey: composed)

        let decomposedAbsent = try source.copy(
            decomposedKey,
            to: InMemoryPersistentKeyValueStore(),
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(decomposedAbsent.outcomes.map(\.status), [.sourceAbsent])

        source.set(7, forKey: decomposed)

        let composedDestination = InMemoryPersistentKeyValueStore()
        let decomposedDestination = InMemoryPersistentKeyValueStore()

        _ = try source.copy(
            composedKey,
            to: composedDestination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )
        _ = try source.copy(
            decomposedKey,
            to: decomposedDestination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(composedDestination.object(forKey: composed) as? Int, 5)
        XCTAssertEqual(decomposedDestination.object(forKey: decomposed) as? Int, 7)
    }

    func testDefaultsPersistentDomainIsTheUnbridgedFoundationDictionary() throws {
        let suiteName = stableSuiteName("MigrationNativeFidelityTests.unbridged")
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let backend = try XCTUnwrap(defaults.migrationEndpoint.backend as? UserDefaultsMigrationBackend)

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(backend.persistentDomain()?.count ?? 0, 0)

        defaults.set(5, forKey: composed)
        defaults.set(7, forKey: decomposed)
        defaults.set(dictionary(true, 1), forKey: "nested")

        let domain = try XCTUnwrap(backend.persistentDomain())

        XCTAssertFalse(NSStringFromClass(type(of: domain)).contains("Swift"))
        XCTAssertEqual(domain.count, 3)
        XCTAssertEqual(domain.object(forKey: composed as NSString) as? Int, 5)
        XCTAssertEqual(domain.object(forKey: decomposed as NSString) as? Int, 7)
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName)?.count, 2)

        let nested = try XCTUnwrap(backend.migrationSnapshot(for: "nested")?.object as? NSDictionary)
        let composedValue = try XCTUnwrap(nested.object(forKey: composed as NSString) as? NSNumber)
        let decomposedValue = try XCTUnwrap(nested.object(forKey: decomposed as NSString) as? NSNumber)

        XCTAssertEqual(nested.count, 2)
        XCTAssertEqual(CFGetTypeID(composedValue), CFBooleanGetTypeID())
        XCTAssertNotEqual(CFGetTypeID(decomposedValue), CFBooleanGetTypeID())
        XCTAssertTrue(equal(nested, dictionary(true, 1)))
        XCTAssertFalse(equal(nested, dictionary(1, true)))
    }

    func testDefaultsSnapshotExcludesValuesOutsideThePersistentDomain() throws {
        let suiteName = stableSuiteName("MigrationNativeFidelityTests.provenance")
        let addedName = stableSuiteName("MigrationNativeFidelityTests.provenanceAdded")
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let added = try XCTUnwrap(UserDefaults(suiteName: addedName))
        let backend = try XCTUnwrap(defaults.migrationEndpoint.backend as? UserDefaultsMigrationBackend)
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let globalKey = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?.keys.first

        defer {
            defaults.removeSuite(named: addedName)
            defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
            defaults.removePersistentDomain(forName: suiteName)
            added.removePersistentDomain(forName: addedName)
        }

        defaults.set(1, forKey: "persisted")
        defaults.register(defaults: ["registered:\(#function)": 2])
        defaults.setVolatileDomain(
            previousArguments.merging(["argument:\(#function)": 3]) { $1 },
            forName: UserDefaults.argumentDomain
        )
        added.set(4, forKey: "added:\(#function)")
        defaults.addSuite(named: addedName)

        var keys = ["registered:\(#function)", "argument:\(#function)", "added:\(#function)"]
        if let globalKey {
            keys.append(globalKey)
        }

        for key in keys {
            XCTAssertNotNil(defaults.object(forKey: key), key)
            XCTAssertNil(try backend.migrationSnapshot(for: key), key)
        }

        XCTAssertEqual(try backend.migrationSnapshot(for: "persisted")?.object as? Int, 1)
    }

    func testDefaultsSnapshotRejectsBooleanReplacedByEqualNumber() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.boolean")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))

        defer {
            source.removePersistentDomain(forName: sourceName)
        }

        try assertTypeChangeIsDetected(in: source)
    }

    func testDefaultsSnapshotRejectsSingleReplacedByEqualDouble() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.width")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))

        defer {
            source.removePersistentDomain(forName: sourceName)
        }

        try assertWidthChangeIsDetected(in: source)
    }

    func testDefaultsSnapshotVerifiesIntegerReplacedByEqualWiderInteger() throws {
        let sourceName = stableSuiteName("MigrationNativeFidelityTests.integerReplacement")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))

        defer {
            source.removePersistentDomain(forName: sourceName)
        }

        try assertIntegerWidthReplacementVerifiesByValue(in: source)
    }

    func testFileURLThatDefaultsCannotReproduceFailsBeforeMutation() throws {
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.fileURL")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationName))
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: URL(string: "https://example.com")!)
        let optionalKey = PersistentKey<URL?>("key:\(#function).optional", defaultValue: nil)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prospective-\(UUID().uuidString)", isDirectory: true)

        defer {
            destination.removePersistentDomain(forName: destinationName)
        }

        // A defaults path loses a directory's trailing slash and a file URL's host.
        for url in [directory, URL(string: "file://fileserver/shared/folder/doc")!] {
            source.set(key, to: url)
            source.set(optionalKey, to: url)

            let report = try source.move(
                [key, optionalKey],
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare), .failed(.prepare)], url.absoluteString)
            XCTAssertEqual(
                report.outcomes.map { $0.error as? PersistentKeyValueConversionError },
                [.encodingFailed, .encodingFailed],
                url.absoluteString
            )
            XCTAssertEqual(source.get(key), url)
            XCTAssertNil(destination.persistentDomain(forName: destinationName)?[key.id], url.absoluteString)
        }

        let file = directory.appendingPathComponent("file", isDirectory: false)

        source.set(key, to: file)
        source.set(optionalKey, to: nil)

        let report = try source.move([key, optionalKey], to: destination, onConflict: .keepBoth, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved])
        XCTAssertEqual(destination.get(key), file)
        XCTAssertNil(destination.get(optionalKey))
    }

    func testImmutableCopyHoldsOnlyImmutableFoundationObjects() throws {
        let nested = NSMutableDictionary(
            dictionary: [
                "string": NSMutableString(string: "text"),
                "data": NSMutableData(bytes: [1] as [UInt8], length: 1),
            ]
        )
        let original = NSMutableArray(array: [nested, NSMutableArray(array: [1.5])])
        let copy = try XCTUnwrap(PropertyListMigrationStorage.exactCopy(original) as? NSArray)
        let dictionary = try XCTUnwrap(copy[0] as? NSDictionary)
        let array = try XCTUnwrap(copy[1] as? NSArray)

        XCTAssertFalse(copy is NSMutableArray)
        XCTAssertFalse(dictionary is NSMutableDictionary)
        XCTAssertFalse(dictionary["string"] is NSMutableString)
        XCTAssertFalse(dictionary["data"] is NSMutableData)
        XCTAssertFalse(array is NSMutableArray)
        XCTAssertTrue(equal(copy, original))
        XCTAssertTrue(type(of: try PropertyListMigrationStorage.exactCopy(1.5)) is AnyClass)
    }

    func testMemorySourceDecimalEditDuringMoveFailsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = MutableArrayKey(id: "key:\(#function)")
        let original = NSDecimalNumber(string: "1.000000000000000001")

        source.set(key, to: NSMutableArray(object: original))

        // The transform receives the stored array itself, so it can edit the source while migrating a copy.
        let report = try source.move(
            .key(key, to: key) {
                let copy = NSMutableArray(array: Array($0))
                $0.replaceObject(at: 0, with: NSDecimalNumber(string: "1.000000000000000002"))
                return copy
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes[0].error as? PersistentKeyMigrationError, .sourceChanged)
        XCTAssertEqual(source.get(key), [NSDecimalNumber(string: "1.000000000000000002")])
        XCTAssertEqual(destination.get(key), [original])
    }

    func testMemorySourceIntegerWidthEditDuringMoveFailsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = MutableArrayKey(id: "key:\(#function)")
        let destinationKey = PersistentKey("key:\(#function).destination", defaultValue: "absent")
        let observer = CallbackObserver {
            // The edit keeps the value and changes only its width, which a representation can observe.
            source.get(key).replaceObject(at: 0, with: NSNumber(value: Int64(-200_000_023)))
        }

        source.set(key, to: NSMutableArray(object: NSNumber(value: Int32(-200_000_023))))
        destination.register(
            observer: observer,
            for: destinationKey,
            with: nil,
            and: #selector(CallbackObserver.observeValue)
        )

        defer {
            destination.deregister(observer, for: destinationKey, context: nil)
        }

        let report = try source.move(
            .key(key, to: destinationKey) {
                "\(($0.firstObject as? NSNumber).map(CFNumberGetByteSize) ?? 0)"
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes[0].error as? PersistentKeyMigrationError, .sourceChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
        XCTAssertEqual((source.get(key).firstObject as? NSNumber).map(CFNumberGetByteSize), 8)
        XCTAssertEqual(destination.get(destinationKey), "4")
    }

    func testPropertyListEqualityComparesTypesAndLiteralKeys() {
        let date = Date(timeIntervalSinceReferenceDate: 12)
        let url = URL(string: "https://example.com")!

        XCTAssertTrue(equal(true, true))
        XCTAssertFalse(equal(true, false))
        XCTAssertFalse(equal(true, 1))
        XCTAssertFalse(equal(1, true))
        XCTAssertFalse(equal(0, false))
        XCTAssertTrue(equal(1, 1))
        XCTAssertFalse(equal(1, 2))
        XCTAssertTrue(equal(Int32(1), Int64(1)))
        XCTAssertFalse(equal(Int32(1), Int64(2)))
        XCTAssertFalse(equal(1, 1.0))
        XCTAssertTrue(equal(1.5, 1.5))
        XCTAssertFalse(equal(1.5, 2.5))
        XCTAssertFalse(equal(0.0, -0.0))
        XCTAssertTrue(equal(Float(1.25), Float(1.25)))
        XCTAssertFalse(equal(Float(1.25), 1.25))
        XCTAssertFalse(equal(1.25, Float(1.25)))
        XCTAssertFalse(equal([Float(1.25)], [1.25]))
        XCTAssertTrue(equal(Double.nan, Double.nan))
        XCTAssertFalse(equal(Double.nan, 1.0))
        XCTAssertFalse(equal(1.0, Double.nan))
        XCTAssertTrue(equal(composed, composed))
        XCTAssertFalse(equal(composed, decomposed))
        XCTAssertTrue(equal(Data([1]), Data([1])))
        XCTAssertFalse(equal(Data([1]), Data([2])))
        XCTAssertTrue(equal(date, date))
        XCTAssertFalse(equal(date, date.addingTimeInterval(1)))
        XCTAssertTrue(equal(Date(timeIntervalSinceReferenceDate: .nan), Date(timeIntervalSinceReferenceDate: .nan)))
        XCTAssertFalse(equal(Date(timeIntervalSinceReferenceDate: .nan), date))
        XCTAssertFalse(equal(date, Date(timeIntervalSinceReferenceDate: .nan)))
        XCTAssertTrue(equal([1, true] as [Any], [1, true] as [Any]))
        XCTAssertFalse(equal([1, true] as [Any], [true, 1] as [Any]))
        XCTAssertFalse(equal([1], [1, 2]))
        XCTAssertTrue(equal(dictionary(1, true), dictionary(1, true)))
        XCTAssertFalse(equal(dictionary(1, true), dictionary(true, 1)))
        XCTAssertFalse(equal([composed: 1], [decomposed: 1]))
        XCTAssertFalse(equal([composed: 1], dictionary(1, 1)))
        XCTAssertTrue(equal(["nested": [["flag": true]]], ["nested": [["flag": true]]]))
        XCTAssertFalse(equal(["nested": [["flag": true]]], ["nested": [["flag": 1]]]))
        XCTAssertTrue(PropertyListMigrationStorage.equal(url, url))
        XCTAssertFalse(PropertyListMigrationStorage.equal(url, URL(string: "https://example.org")!))
        XCTAssertFalse(equal("1", 1))
        XCTAssertFalse(PropertyListMigrationStorage.equal(nil, 1))
        XCTAssertTrue(PropertyListMigrationStorage.equal(nil, nil))
    }

    func testPropertyListEqualityComparesDecimalsExactly() {
        let decimal = NSDecimalNumber(string: "1.000000000000000001")

        XCTAssertTrue(PropertyListMigrationStorage.equal(decimal, NSDecimalNumber(string: "1.000000000000000001")))
        XCTAssertFalse(PropertyListMigrationStorage.equal(decimal, NSDecimalNumber(string: "1.000000000000000002")))
        XCTAssertFalse(PropertyListMigrationStorage.equal(decimal, NSNumber(value: 1.0)))
        XCTAssertFalse(PropertyListMigrationStorage.equal(NSNumber(value: 1.0), decimal))
        XCTAssertTrue(PropertyListMigrationStorage.equal(NSDecimalNumber.notANumber, NSDecimalNumber.notANumber))
        XCTAssertFalse(PropertyListMigrationStorage.equal(NSDecimalNumber.notANumber, decimal))
    }

    func testPropertyListEqualityDistinguishingIntegerWidthsComparesWidthsRecursively() {
        let int32 = NSNumber(value: Int32(-200_000_023))
        let int64 = NSNumber(value: Int64(-200_000_023))

        func equalWidths(_ lhs: Any, _ rhs: Any) -> Bool {
            PropertyListMigrationStorage.equal(lhs, rhs, distinguishingIntegerWidths: true)
        }

        XCTAssertTrue(PropertyListMigrationStorage.equal([int32] as NSArray, [int64] as NSArray))
        XCTAssertTrue(PropertyListMigrationStorage.equal(["field": int32] as NSDictionary, ["field": int64] as NSDictionary))
        XCTAssertTrue(equalWidths(int32, NSNumber(value: Int32(-200_000_023))))
        XCTAssertTrue(equalWidths(int64, NSNumber(value: Int64(-200_000_023))))
        XCTAssertFalse(equalWidths(int32, int64))
        XCTAssertFalse(equalWidths(int64, int32))
        XCTAssertFalse(equalWidths(int32, NSNumber(value: Int32(-200_000_024))))
        XCTAssertFalse(equalWidths([int32] as NSArray, [int64] as NSArray))
        XCTAssertFalse(equalWidths(["field": [int32]] as NSDictionary, ["field": [int64]] as NSDictionary))
        XCTAssertTrue(equalWidths(["field": [int64]] as NSDictionary, ["field": [int64]] as NSDictionary))
        XCTAssertFalse(equalWidths(true, NSNumber(value: Int8(1))))
        XCTAssertFalse(equalWidths(1, 1.0))
        XCTAssertFalse(equalWidths(Float(1.25), 1.25))
        XCTAssertTrue(equalWidths(1.25, 1.25))
    }

    func testSelfReferentialEncodingFailsBeforeMutation() throws {
        let destinationName = stableSuiteName("MigrationNativeFidelityTests.selfReferential")
        let finished = DispatchSemaphore(value: 0)

        defer {
            UserDefaults(suiteName: destinationName)?.removePersistentDomain(forName: destinationName)
        }

        // A regression recurses into the array, so the migration runs where a timeout can report it.
        DispatchQueue.global().async {
            defer {
                finished.signal()
            }

            let source = InMemoryPersistentKeyValueStore()
            let legacy = PersistentKey("key:\(#function).legacy", defaultValue: "")
            let looped = PersistentKey("key:\(#function)", defaultValue: "", representation: SelfReferentialCodec())

            source.set(legacy, to: "preserved")

            guard let destination = UserDefaults.migratable(suiteName: destinationName) else {
                return XCTFail("The destination suite is unavailable.")
            }

            do {
                let report = try source.move(
                    .key(legacy, to: looped),
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: .once(id: #function)
                )

                XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)])
                XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyValueConversionError, .encodingFailed)
                XCTAssertEqual(report.completion, .notRecorded)
                XCTAssertEqual(source.get(legacy), "preserved")
                XCTAssertNil(destination.persistentDomain(forName: destinationName)?[looped.id])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(finished.wait(timeout: .now() + 10), .success)
    }

    @available(watchOS 9.0, *)
    func testUbiquitousDestinationCommitsEncodingThatValidationCannotConsume() throws {
        try assertEncodingThatValidationCannotConsumeIsCommitted(to: StrictMigrationUbiquitousStore())
    }

    @available(watchOS 9.0, *)
    func testUbiquitousDestinationRejectsNumberThatStorageWouldChange() throws {
        let destination = StrictMigrationUbiquitousStore()

        try assertNumbersThatStorageWouldChangeFailBeforeWriting(to: destination) {
            destination.storedValue(for: $0)
        }
    }

    @available(watchOS 9.0, *)
    func testUbiquitousIntegerWidthMatchesOrdinaryAccess() throws {
        try assertIntegerWidthMatchesOrdinaryAccess(
            from: StrictMigrationUbiquitousStore(),
            to: StrictMigrationUbiquitousStore()
        )
    }

    @available(watchOS 9.0, *)
    func testUbiquitousOverwriteReplacesFoundationEqualValueOfAnotherType() throws {
        let destination = StrictMigrationUbiquitousStore()

        try assertOverwriteReplacesFoundationEqualValueOfAnotherType(in: destination, rawValue: destination.storedValue(for:))
    }

    @available(watchOS 9.0, *)
    func testUbiquitousSnapshotRejectsBooleanReplacedByEqualNumber() throws {
        try assertTypeChangeIsDetected(in: StrictMigrationUbiquitousStore())
    }

    @available(watchOS 9.0, *)
    func testUbiquitousSnapshotRejectsSingleReplacedByEqualDouble() throws {
        try assertWidthChangeIsDetected(in: StrictMigrationUbiquitousStore())
    }

    @available(watchOS 9.0, *)
    func testUbiquitousSnapshotVerifiesIntegerReplacedByEqualWiderInteger() throws {
        try assertIntegerWidthReplacementVerifiesByValue(in: StrictMigrationUbiquitousStore())
    }

    // MARK: Private Instance Interface

    /// Moves a value over an ordinary destination value with a representation whose decoder empties a writable
    /// encoding, as migration write validation decodes it.
    private func assertEncodingThatValidationCannotConsumeIsCommitted<Store>(
        to destination: Store,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Store: PersistentKeyValueStore {
        let source = InMemoryPersistentKeyValueStore()
        let legacy = PersistentKey("key:\(#function).legacy", defaultValue: "")
        let packet = PersistentKey("key:\(#function)", defaultValue: "missing", representation: PacketCodec())

        source.set(legacy, to: "actual")
        destination.set(packet, to: "ordinary")

        XCTAssertEqual(destination.get(packet), "ordinary", file: file, line: line)

        let report = try source.move(
            .key(legacy, to: packet),
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved], file: file, line: line)
        XCTAssertEqual(report.completion, .recorded, file: file, line: line)
        XCTAssertEqual(destination.get(packet), "actual", file: file, line: line)
        XCTAssertNil(source.object(forKey: legacy.id), file: file, line: line)
        destination.remove(packet)
        destination.remove(.isMigrationCompleted(id: #function))
    }

    /// Moves integers whose width a format-aware representation observes, expecting migration to read and write them as
    /// ordinary `get` and `set` do in the same process.
    private func assertIntegerWidthMatchesOrdinaryAccess<Store>(
        from source: Store,
        to destination: Store,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Store: PersistentKeyValueStore {
        let field = PersistentKey(
            "key:\(#function).field",
            defaultValue: SignedField.int64(0),
            representation: SignedFieldCodec()
        )
        let ordinary = PersistentKey(
            "key:\(#function).ordinary",
            defaultValue: SignedField.int64(0),
            representation: SignedFieldCodec()
        )
        let count = PersistentKey("key:\(#function).count", defaultValue: 0)
        let text = PersistentKey("key:\(#function).text", defaultValue: "missing")

        source.set(field, to: .int32(-200_000_023))
        destination.set(ordinary, to: .int32(-200_000_023))

        XCTAssertEqual(source.get(field), .int32(-200_000_023), file: file, line: line)

        let sourceReport = try source.move(
            .key(field, to: text) {
                "\($0)"
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(sourceReport.outcomes.map(\.status), [.moved], file: file, line: line)
        XCTAssertEqual(destination.get(text), "int32(-200000023)", file: file, line: line)

        source.set(count, to: -200_000_023)

        let destinationReport = try source.move(
            .key(count, to: field) {
                .int32(Int32($0))
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(destinationReport.outcomes.map(\.status), [.moved], file: file, line: line)
        XCTAssertEqual(destination.get(field), destination.get(ordinary), file: file, line: line)
        XCTAssertEqual(destination.get(field), .int32(-200_000_023), file: file, line: line)
        destination.remove(field)
        destination.remove(ordinary)
        destination.remove(text)
    }

    /// Moves a 32-bit integer while the transform replaces it with the same value as a 64-bit integer, expecting the
    /// source to verify and be removed, because the store does not preserve integer width across processes.
    private func assertIntegerWidthReplacementVerifiesByValue<Store>(
        in source: Store,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Store: PersistentKeyValueStore {
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: SignedField.int64(0), representation: SignedFieldCodec())
        let sourceBox = UncheckedStore(source)

        source.set(key, to: .int32(-200_000_023))

        let report = try source.move(
            .key(key, to: key) {
                // Removing first keeps the store from ignoring a replacement that Core Foundation considers equal.
                sourceBox.store.remove(key)
                sourceBox.store.set(key, to: .int64(-200_000_023))
                XCTAssertEqual(sourceBox.store.get(key), .int64(-200_000_023), file: file, line: line)
                return $0
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved], file: file, line: line)
        // The source returns the key's default once the move removes it.
        XCTAssertEqual(source.get(key), .int64(0), file: file, line: line)
        XCTAssertEqual(destination.get(key), .int32(-200_000_023), file: file, line: line)
    }

    /// Moves counts whose encoded decimal a binary property list would store as a double, then an exact unsigned count.
    ///
    /// The double rounds `9_007_199_254_740_993` and cannot hold `UInt64.max` as an integer. Even `42` would come back
    /// as a double rather than a decimal, which a format-aware representation can tell apart.
    private func assertNumbersThatStorageWouldChangeFailBeforeWriting<Store>(
        to destination: Store,
        storedObject: (String) -> Any?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Store: PersistentKeyValueStore {
        let source = InMemoryPersistentKeyValueStore()
        let legacy = PersistentKey("key:\(#function).legacy", defaultValue: "")
        let decimal = PersistentKey<UInt64>("key:\(#function)", defaultValue: 0, representation: CounterCodec.decimal)
        let unsigned = PersistentKey<UInt64>(
            "key:\(#function).unsigned",
            defaultValue: 0,
            representation: CounterCodec.unsigned
        )

        for count: UInt64 in [42, 9_007_199_254_740_993, .max] {
            source.set(legacy, to: String(count))

            let report = try source.move(
                .key(legacy, to: decimal, transform: CounterCodec.parse),
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: "\(#function).\(count)")
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)], "\(count)", file: file, line: line)
            XCTAssertEqual(
                report.outcomes[0].error as? PersistentKeyValueConversionError,
                .encodingFailed,
                "\(count)",
                file: file,
                line: line
            )
            XCTAssertEqual(report.completion, .notRecorded, "\(count)", file: file, line: line)
            XCTAssertFalse(destination.get(.isMigrationCompleted(id: "\(#function).\(count)")), file: file, line: line)
            XCTAssertEqual(source.get(legacy), String(count), file: file, line: line)
            XCTAssertNil(storedObject(decimal.id), "\(count)", file: file, line: line)
        }

        source.set(legacy, to: String(UInt64.max))

        let report = try source.move(
            .key(legacy, to: unsigned, transform: CounterCodec.parse),
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved], file: file, line: line)
        XCTAssertEqual(destination.get(unsigned), .max, file: file, line: line)
        XCTAssertNil(source.object(forKey: legacy.id), file: file, line: line)
        destination.remove(unsigned)
    }

    /// Moves a value while the transform replaces it in the source with a value that Core Foundation considers equal.
    ///
    /// `UserDefaults` ignores a write that Core Foundation considers equal to the stored value, so the replacement
    /// removes the value first, as a write from another process can.
    /// Moves the integer `1` over a stored `true`, which Foundation considers equal to it, and checks that the
    /// destination then stores an integer.
    private func assertOverwriteReplacesFoundationEqualValueOfAnotherType<Store>(
        in destination: Store,
        rawValue: (String) -> Any?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Store: PersistentKeyValueStore {
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)

        source.set(key, to: 1)
        destination.set(PersistentKey<Bool>(key.id, defaultValue: false), to: true)

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.moved], file: file, line: line)
        XCTAssertEqual(destination.get(key), 1, file: file, line: line)

        let raw = try XCTUnwrap(rawValue(key.id) as? NSNumber, file: file, line: line)

        XCTAssertNotEqual(CFGetTypeID(raw), CFBooleanGetTypeID(), file: file, line: line)
    }

    private func assertReplacementIsDetected<Store, Value>(
        in source: Store,
        original: Value,
        replacement: Value,
        representation: some PersistentKeyValueRepresentation<Value>,
        file: StaticString,
        line: UInt
    ) throws where Store: PersistentKeyValueStore, Value: Equatable & Sendable {
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: replacement, representation: representation)
        let sourceBox = UncheckedStore(source)

        source.set(key, to: original)

        let report = try source.move(
            .key(key, to: key) {
                sourceBox.store.remove(key)
                sourceBox.store.set(key, to: replacement)
                return $0
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)], file: file, line: line)
        XCTAssertEqual(
            report.outcomes[0].error as? PersistentKeyMigrationError,
            .sourceChanged,
            file: file,
            line: line
        )
        XCTAssertEqual(source.get(key), replacement, file: file, line: line)
        XCTAssertEqual(destination.get(key), original, file: file, line: line)
        source.remove(key)
    }

    /// Moves a boolean setting while the transform replaces it with a numerically equal integer setting.
    private func assertTypeChangeIsDetected<Store>(
        in source: Store,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Store: PersistentKeyValueStore {
        try assertReplacementIsDetected(
            in: source,
            original: Setting.enabled(true),
            replacement: .limit(1),
            representation: SettingCodec(),
            file: file,
            line: line
        )
    }

    /// Moves a single-precision setting while the transform replaces it with an equal double-precision setting.
    private func assertWidthChangeIsDetected<Store>(
        in source: Store,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Store: PersistentKeyValueStore {
        try assertReplacementIsDetected(
            in: source,
            original: Width.single,
            replacement: .double,
            representation: WidthCodec(),
            file: file,
            line: line
        )
    }

    /// Returns a dictionary whose keys Swift's `String` would merge: the composed and decomposed spellings of "café".
    private func dictionary(_ composedValue: Any, _ decomposedValue: Any) -> NSDictionary {
        NSDictionary(
            objects: [composedValue, decomposedValue],
            forKeys: [composed as NSString, decomposed as NSString]
        )
    }

    /// Compares exact copies of two values, as the native backends do.
    private func equal(_ lhs: Any, _ rhs: Any) -> Bool {
        PropertyListMigrationStorage.equal(
            try? PropertyListMigrationStorage.exactCopy(lhs),
            try? PropertyListMigrationStorage.exactCopy(rhs)
        )
    }
}

// MARK: - Callback Observer Definition

private final class CallbackObserver: NSObject {
    private let callback: () -> Void

    // MARK: Internal Initialization

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    // MARK: Internal Instance Interface

    @objc
    func observeValue() {
        callback()
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        callback()
    }
}

// MARK: - Counter Codec Definition

/// Encodes a count as an exact decimal or as an unsigned integer, and decodes any number that holds it exactly.
private struct CounterCodec: PersistentKeyValueRepresentation {
    static let decimal = CounterCodec(encodesDecimal: true)
    static let unsigned = CounterCodec(encodesDecimal: false)

    let encodesDecimal: Bool

    // MARK: Internal Static Interface

    @Sendable
    static func parse(_ text: String) throws -> UInt64 {
        guard let count = UInt64(text) else {
            throw PersistentKeyValueConversionError.invalidValue
        }

        return count
    }

    // MARK: Internal Instance Interface

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> UInt64 {
        guard let number = storageObject as? NSNumber, let count = UInt64(exactly: number) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return count
    }

    func encode(_ value: UInt64, format: PersistentKeyValueStorageFormat) throws -> Any? {
        encodesDecimal ? NSDecimalNumber(string: String(value)) : NSNumber(value: value)
    }
}

// MARK: - Packet Codec Definition

/// Stores a string as the only field of an array, and consumes that field when it decodes a writable array.
private struct PacketCodec: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> String {
        guard let array = storageObject as? NSArray, let field = array.firstObject as? String else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        (array as? NSMutableArray)?.removeObject(at: 0)
        return field
    }

    func encode(_ value: String, format: PersistentKeyValueStorageFormat) throws -> Any? {
        NSMutableArray(array: [value])
    }
}

// MARK: - Self-Referential Codec Definition

/// Encodes every string as an array that contains itself, which is not a property list.
private struct SelfReferentialCodec: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> String {
        "decoded"
    }

    func encode(_ value: String, format: PersistentKeyValueStorageFormat) throws -> Any? {
        let array = NSMutableArray()
        array.add(array)
        return array
    }
}

// MARK: - Setting Definition

private enum Setting: Equatable, Sendable {
    case enabled(Bool)
    case limit(Int)
}

// MARK: - Setting Codec Definition

/// Decodes a stored boolean as a flag and any other number as a limit.
private struct SettingCodec: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Setting {
        guard let number = storageObject as? NSNumber else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .enabled(number.boolValue)
        }

        return .limit(number.intValue)
    }

    func encode(_ value: Setting, format: PersistentKeyValueStorageFormat) throws -> Any? {
        switch value {
        case .enabled(let isEnabled):
            NSNumber(value: isEnabled)
        case .limit(let limit):
            NSNumber(value: limit)
        }
    }
}

// MARK: - Width Definition

private enum Width: Equatable, Sendable {
    case double
    case single
}

// MARK: - Width Codec Definition

/// Decodes a stored number by its floating-point width, which a binary property list preserves.
private struct WidthCodec: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Width {
        guard let number = storageObject as? NSNumber else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return CFNumberGetByteSize(number) == 4 ? .single : .double
    }

    func encode(_ value: Width, format: PersistentKeyValueStorageFormat) throws -> Any? {
        switch value {
        case .double:
            NSNumber(value: 1.25 as Double)
        case .single:
            NSNumber(value: 1.25 as Float)
        }
    }
}

// MARK: - Signed Field Definition

private enum SignedField: Equatable, Sendable {
    case int32(Int32)
    case int64(Int64)
}

// MARK: - Signed Field Codec Definition

/// Decodes a stored integer by its width as the store returns it.
private struct SignedFieldCodec: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> SignedField {
        guard let number = storageObject as? NSNumber, !CFNumberIsFloatType(number) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return CFNumberGetByteSize(number) == 4 ? .int32(number.int32Value) : .int64(number.int64Value)
    }

    func encode(_ value: SignedField, format: PersistentKeyValueStorageFormat) throws -> Any? {
        switch value {
        case .int32(let value):
            NSNumber(value: value)
        case .int64(let value):
            NSNumber(value: value)
        }
    }
}

// MARK: - Stamp Definition

private enum Stamp: Equatable, Sendable {
    case known(TimeInterval)
    case unknown
}

// MARK: - Stamp Codec Definition

/// Stores an unknown time as a date whose interval is not a number.
private struct StampCodec: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Stamp {
        guard let date = storageObject as? Date else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        let interval = date.timeIntervalSinceReferenceDate
        return interval.isNaN ? .unknown : .known(interval)
    }

    func encode(_ value: Stamp, format: PersistentKeyValueStorageFormat) throws -> Any? {
        switch value {
        case .known(let interval):
            Date(timeIntervalSinceReferenceDate: interval)
        case .unknown:
            Date(timeIntervalSinceReferenceDate: .nan)
        }
    }
}

// MARK: - Unchecked Store Definition

/// Carries a thread-safe store into a `@Sendable` transform that runs synchronously on the calling thread.
private final class UncheckedStore: @unchecked Sendable {
    let store: any PersistentKeyValueStore

    init(_ store: any PersistentKeyValueStore) {
        self.store = store
    }
}
