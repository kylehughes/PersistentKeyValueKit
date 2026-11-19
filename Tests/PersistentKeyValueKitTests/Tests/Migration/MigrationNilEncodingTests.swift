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
