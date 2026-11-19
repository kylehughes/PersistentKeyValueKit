import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// A value that is not `nil` but that its destination representation encodes as `nil` must fail migration at
/// `.prepare`, while a `nil` optional keeps removing the destination entry.
final class MigrationNilEncodingTests: XCTestCase {
    // MARK: Tests

    func testUserDefaultsDestinationFailsAtPrepare() throws {
        let suite = stableSuiteName("MigrationNilEncodingTests")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let destination = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)

        try assertEveryWritingPolicyFailsAtPrepare(
            destination: destination,
            seed: {
                defaults.set(5, forKey: $0)
            },
            read: {
                defaults.object(forKey: $0) as? Int
            }
        )
    }

    @available(watchOS 9.0, *)
    func testUbiquitousDestinationFailsAtPrepare() throws {
        let raw = StrictMigrationUbiquitousStore()
        let destination = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "nil-encoding", identifier: UUID().uuidString)
        )

        try assertEveryWritingPolicyFailsAtPrepare(
            destination: destination,
            seed: {
                raw.set(Int64(5), forKey: $0)
            },
            read: {
                (raw.storedValue(for: $0) as? NSNumber)?.intValue
            }
        )
    }

    func testOptionalWrappingNonNilValueFailsAtPrepare() throws {
        let suite = stableSuiteName("MigrationNilEncodingTests.optional")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let destination = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<ConversionOnlyValue?>("key:\(#function)", defaultValue: nil)

        source.set(key, to: ConversionOnlyValue(0))
        defaults.set(5, forKey: key.id)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: "migration:\(#function)")
        )

        assertFailedAtPrepare(report)
        XCTAssertEqual(source.get(key), ConversionOnlyValue(0))
        XCTAssertEqual(defaults.object(forKey: key.id) as? Int, 5)
    }

    func testNestedNilOptionalStillRemovesDestination() throws {
        let suite = stableSuiteName("MigrationNilEncodingTests.nested")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let destination = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int??>("key:\(#function)", defaultValue: nil)

        source.set(key, to: .some(nil))
        defaults.set(5, forKey: key.id)

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .moved = report.outcomes[0].status else {
            return XCTFail("expected moved, got \(report.outcomes[0].status)")
        }

        XCTAssertNil(try source.migrationSnapshot(for: key.id))
        XCTAssertNil(defaults.object(forKey: key.id))
    }

    func testBoxedNilDoesNotCountAsNilOptional() throws {
        try assertBoxedNilFailsAtPrepare(
            destinationKey: NilEncodingKey(id: "key:\(#function)"),
            transform: { _ in AnyHashable(Int?.none) }
        )
    }

    func testOptionalWrappingBoxedNilDoesNotCountAsNilOptional() throws {
        try assertBoxedNilFailsAtPrepare(
            destinationKey: OptionalNilEncodingKey(id: "key:\(#function)"),
            transform: { _ in .some(AnyHashable(Int?.none)) }
        )
    }

    func testNilOptionalOfBoxedTypeStillRemovesDestination() throws {
        let suite = stableSuiteName("MigrationNilEncodingTests.nilBoxed")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let destination = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)
        let source = InMemoryPersistentKeyValueStore()
        let sourceKey = PersistentKey<Int>("source:\(#function)", defaultValue: 0)
        let destinationKey = OptionalNilEncodingKey(id: "key:\(#function)")

        source.set(sourceKey, to: 1)
        defaults.set(5, forKey: destinationKey.id)

        let report = try source.move(
            .key(sourceKey, to: destinationKey) { _ in nil },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        guard case .moved = report.outcomes[0].status else {
            return XCTFail("expected moved, got \(report.outcomes[0].status)")
        }

        XCTAssertNil(defaults.object(forKey: destinationKey.id))
    }

    func testInMemoryDestinationStoresValueDirectly() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: ConversionOnlyValue(1))

        source.set(key, to: ConversionOnlyValue(0))

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .moved = report.outcomes[0].status else {
            return XCTFail("expected moved, got \(report.outcomes[0].status)")
        }

        XCTAssertEqual(destination.get(key), ConversionOnlyValue(0))
        XCTAssertNil(try source.migrationSnapshot(for: key.id))
    }

    // MARK: Private Nested Types

    private enum Scenario: CaseIterable {
        case copyOverwrite
        case copyKeepAbsent
        case moveOverwrite
        case moveKeepBothAbsent
        case moveKeepDestinationAndRemoveSourceAbsent
    }

    // MARK: Private Instance Interface

    private func assertEveryWritingPolicyFailsAtPrepare<Destination>(
        destination: Destination,
        seed: (String) -> Void,
        read: (String) -> Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Destination: PersistentKeyValueStore {
        for scenario in Scenario.allCases {
            let source = InMemoryPersistentKeyValueStore()
            let key = PersistentKey("key:\(#function)-\(scenario)", defaultValue: ConversionOnlyValue(1))
            let tracking = PersistentKeyMigrationTracking.once(id: "migration:\(#function)-\(scenario)")
            let expectedDestination: Int?

            source.set(key, to: ConversionOnlyValue(0))

            switch scenario {
            case .copyOverwrite, .moveOverwrite:
                seed(key.id)
                expectedDestination = 5
            case .copyKeepAbsent, .moveKeepBothAbsent, .moveKeepDestinationAndRemoveSourceAbsent:
                expectedDestination = nil
            }

            let report: PersistentKeyMigrationReport

            switch scenario {
            case .copyOverwrite:
                report = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: tracking)
            case .copyKeepAbsent:
                report = try source.copy(key, to: destination, onConflict: .keepDestination, tracking: tracking)
            case .moveOverwrite:
                report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: tracking)
            case .moveKeepBothAbsent:
                report = try source.move(key, to: destination, onConflict: .keepBoth, tracking: tracking)
            case .moveKeepDestinationAndRemoveSourceAbsent:
                report = try source.move(
                    key,
                    to: destination,
                    onConflict: .keepDestinationAndRemoveSource,
                    tracking: tracking
                )
            }

            assertFailedAtPrepare(report, "\(scenario)", file: file, line: line)
            XCTAssertEqual(source.get(key), ConversionOnlyValue(0), "\(scenario)", file: file, line: line)
            XCTAssertNotNil(try source.migrationSnapshot(for: key.id), "\(scenario)", file: file, line: line)
            XCTAssertEqual(read(key.id), expectedDestination, "\(scenario)", file: file, line: line)
        }
    }

    private func assertBoxedNilFailsAtPrepare<DestinationKey>(
        destinationKey: DestinationKey,
        transform: @escaping @Sendable (Int) -> DestinationKey.Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where DestinationKey: PersistentKeyProtocol {
        let sourceKey = PersistentKey<Int>("source:\(destinationKey.id)", defaultValue: 0)

        let suite = stableSuiteName("MigrationNilEncodingTests.boxed.\(destinationKey.id)")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite), file: file, line: line)

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        var destinations: [(String, any PersistentKeyValueStore, () -> Any?)] = [
            (
                "UserDefaults",
                UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite),
                { defaults.object(forKey: destinationKey.id) }
            ),
        ]

        defaults.set(5, forKey: destinationKey.id)

        if #available(watchOS 9.0, *) {
            let raw = StrictMigrationUbiquitousStore()

            raw.set(Int64(5), forKey: destinationKey.id)
            destinations.append(
                (
                    "NSUbiquitousKeyValueStore",
                    UbiquitousKeyValueMigrationBackend(
                        store: raw,
                        identity: .init(namespace: "nil-encoding", identifier: UUID().uuidString)
                    ),
                    { raw.storedValue(for: destinationKey.id) }
                )
            )
        }

        for (name, destination, read) in destinations {
            let source = InMemoryPersistentKeyValueStore()

            source.set(sourceKey, to: 19)

            let report = try source.move(
                .key(sourceKey, to: destinationKey, transform: transform),
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: "migration:\(destinationKey.id)-\(name)")
            )

            guard case .failed(.prepare) = report.outcomes[0].status else {
                return XCTFail(
                    "\(name): expected failed at prepare, got \(report.outcomes[0].status)",
                    file: file,
                    line: line
                )
            }

            XCTAssertEqual(
                report.outcomes[0].error as? PersistentKeyValueConversionError,
                .encodingFailed,
                name,
                file: file,
                line: line
            )
            XCTAssertEqual(report.completion, .notRecorded, name, file: file, line: line)
            XCTAssertEqual(source.get(sourceKey), 19, name, file: file, line: line)
            XCTAssertNotNil(try source.migrationSnapshot(for: sourceKey.id), name, file: file, line: line)
            XCTAssertEqual((read() as? NSNumber)?.intValue, 5, name, file: file, line: line)
        }
    }

    private func assertFailedAtPrepare(
        _ report: PersistentKeyMigrationReport,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failed(.prepare) = report.outcomes[0].status else {
            return XCTFail("expected failed at prepare, got \(report.outcomes[0].status)", file: file, line: line)
        }

        XCTAssertEqual(
            report.outcomes[0].error as? PersistentKeyValueConversionError,
            .encodingFailed,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(report.completion, .notRecorded, message, file: file, line: line)
    }
}

// MARK: - NilEncodingKey

private protocol NilEncodingKeyProtocol: PersistentKeyProtocol {
    var representation: any PersistentKeyValueRepresentation<Value> { get }
}

extension NilEncodingKeyProtocol {
    func get(from defaults: UserDefaults) -> Value {
        representation.get(id, from: defaults) ?? defaultValue
    }

    @available(watchOS 9.0, *)
    func get(from store: NSUbiquitousKeyValueStore) -> Value {
        representation.get(id, from: store) ?? defaultValue
    }

    func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: id)
    }

    @available(watchOS 9.0, *)
    func remove(from store: NSUbiquitousKeyValueStore) {
        store.removeObject(forKey: id)
    }

    func set(to value: Value, in defaults: UserDefaults) {
        representation.set(id, to: value, in: defaults)
    }

    @available(watchOS 9.0, *)
    func set(to value: Value, in store: NSUbiquitousKeyValueStore) {
        representation.set(id, to: value, in: store)
    }
}

/// A key whose value is an `AnyHashable`, which is not `Sendable`, and whose representation encodes every value to
/// `nil`.
private struct NilEncodingKey: NilEncodingKeyProtocol {
    let id: String

    var defaultValue: AnyHashable {
        AnyHashable(-1)
    }

    var representation: any PersistentKeyValueRepresentation<AnyHashable> {
        NilEncodingRepresentation()
    }
}

/// ``NilEncodingKey`` with an optional value.
private struct OptionalNilEncodingKey: NilEncodingKeyProtocol {
    let id: String

    var defaultValue: AnyHashable? {
        nil
    }

    var representation: any PersistentKeyValueRepresentation<AnyHashable?> {
        NilEncodingRepresentation().optionalRepresentation
    }
}

private struct NilEncodingRepresentation: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> AnyHashable {
        throw PersistentKeyValueConversionError.invalidStorageValue
    }

    func encode(_ value: AnyHashable, format: PersistentKeyValueStorageFormat) throws -> Any? {
        nil
    }
}
