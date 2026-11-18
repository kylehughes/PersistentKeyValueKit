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
        let copy = try XCTUnwrap(PropertyListMigrationStorage.immutableCopy(of: original) as? NSArray)
        let dictionary = try XCTUnwrap(copy[0] as? NSDictionary)
        let array = try XCTUnwrap(copy[1] as? NSArray)

        XCTAssertFalse(copy is NSMutableArray)
        XCTAssertFalse(dictionary is NSMutableDictionary)
        XCTAssertFalse(dictionary["string"] is NSMutableString)
        XCTAssertFalse(dictionary["data"] is NSMutableData)
        XCTAssertFalse(array is NSMutableArray)
        XCTAssertTrue(equal(copy, original))
        XCTAssertTrue(type(of: PropertyListMigrationStorage.immutableCopy(of: 1.5)) is AnyClass)
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
    func testUbiquitousSnapshotRejectsBooleanReplacedByEqualNumber() throws {
        try assertTypeChangeIsDetected(in: StrictMigrationUbiquitousStore())
    }

    @available(watchOS 9.0, *)
    func testUbiquitousSnapshotRejectsSingleReplacedByEqualDouble() throws {
        try assertWidthChangeIsDetected(in: StrictMigrationUbiquitousStore())
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

// MARK: - Unchecked Store Definition

/// Carries a thread-safe store into a `@Sendable` transform that runs synchronously on the calling thread.
private final class UncheckedStore: @unchecked Sendable {
    let store: any PersistentKeyValueStore

    init(_ store: any PersistentKeyValueStore) {
        self.store = store
    }
}
