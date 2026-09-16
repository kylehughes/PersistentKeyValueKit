import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationCoverageEdgeTests: XCTestCase {
    // MARK: Tests

    @available(watchOS 9.0, *)
    func testCloudDestinationRacePreservesNewValue() throws {
        let raw = StrictMigrationUbiquitousStore()
        let destination = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "coverage", identifier: UUID().uuidString)
        )
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let write = try destination.prepareMigrationWrite(1, for: key)

        raw.set(Int64(7), forKey: key.id)

        XCTAssertThrowsError(try destination.commitMigrationWrite(write, replacing: nil)) { error in
            XCTAssertEqual(error as? PersistentKeyMigrationError, .destinationChanged)
        }

        XCTAssertEqual(raw.storedValue(for: key.id) as? Int64, 7)
    }

    func testIntentionalNilMoveRemovesDestination() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suite = "MigrationCoverageEdge.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let destination = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)
        let key = PersistentKey<Int?>(#function, defaultValue: nil)

        source.set(key, to: nil)
        defaults.set(8, forKey: key.id)
        let report = try source.move(key, to: destination, onConflict: .overwriteDestination)

        guard case .moved = report.outcomes[0].status else {
            return XCTFail("expected moved")
        }

        XCTAssertNil(try source.migrationSnapshot(for: key.id))
        XCTAssertNil(defaults.object(forKey: key.id))
    }

    func testPrimitiveArrayRejectsNonArrayStorage() {
        let representation = PrimitivePersistentKeyValueRepresentation<[Int]>()

        XCTAssertThrowsError(
            try representation.decode(storageObject: "not array", format: .propertyList)
        ) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
    }
}
