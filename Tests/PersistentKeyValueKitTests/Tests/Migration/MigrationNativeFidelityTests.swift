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

        source.set(key, to: 17)
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

    @available(watchOS 9.0, *)
    func testUbiquitousSnapshotRejectsBooleanReplacedByEqualNumber() throws {
        try assertTypeChangeIsDetected(in: StrictMigrationUbiquitousStore())
    }

    @available(watchOS 9.0, *)
    func testUbiquitousSnapshotRejectsSingleReplacedByEqualDouble() throws {
        try assertWidthChangeIsDetected(in: StrictMigrationUbiquitousStore())
    }

    // MARK: Private Instance Interface

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

    /// Compares two values after freezing them, as the native backends do.
    private func equal(_ lhs: Any, _ rhs: Any) -> Bool {
        PropertyListMigrationStorage.equal(
            try? PropertyListMigrationStorage.freeze(lhs),
            try? PropertyListMigrationStorage.freeze(rhs)
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

// MARK: - Unchecked Store Definition

/// Carries a thread-safe store into a `@Sendable` transform that runs synchronously on the calling thread.
private final class UncheckedStore: @unchecked Sendable {
    let store: any PersistentKeyValueStore

    init(_ store: any PersistentKeyValueStore) {
        self.store = store
    }
}
