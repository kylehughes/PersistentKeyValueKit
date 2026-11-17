import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationNativeStoreTests: XCTestCase {
    // MARK: Tests

    func testConcurrentFactoryAndEndpointAccess() throws {
        let queue = DispatchQueue(label: #function, attributes: .concurrent)
        let group = DispatchGroup()
        let errors = LockedErrors()

        for index in 0..<32 {
            group.enter()
            queue.async {
                defer {
                    group.leave()
                }

                do {
                    let suiteName = "MigrationNativeStoreTests.concurrent.\(index).\(UUID().uuidString)"
                    let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))

                    _ = try defaults.migrationEndpoint
                    defaults.removePersistentDomain(forName: suiteName)
                } catch {
                    errors.append(error)
                }
            }
        }

        guard group.wait(timeout: .now() + 5) == .success else {
            return XCTFail("Factory and endpoint access did not finish")
        }

        XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.snapshot())")

        let suiteName = "MigrationNativeStoreTests.shared.\(UUID().uuidString)"

        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let shared = SharedNativeStore(try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName)))
        let sharedGroup = DispatchGroup()

        for _ in 0..<32 {
            sharedGroup.enter()
            queue.async {
                defer {
                    sharedGroup.leave()
                }

                do {
                    let endpoint = try shared.store.migrationEndpoint

                    let expectedIdentifier = UserDefaults.migrationDomainIdentifier(suiteName)

                    guard endpoint.backend.migrationIdentity.identifier == expectedIdentifier else {
                        errors.append(NSError(domain: "MigrationNativeStoreTests", code: 1))

                        return
                    }
                } catch {
                    errors.append(error)
                }
            }
        }

        guard sharedGroup.wait(timeout: .now() + 5) == .success else {
            return XCTFail("Shared endpoint access did not finish")
        }

        XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.snapshot())")
    }

    func testFactoryLeavesPreexistingPersistentDataUntouched() throws {
        let suiteName = "MigrationNativeStoreTests.existing.\(UUID().uuidString)"
        let raw = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        defer {
            raw.removePersistentDomain(forName: suiteName)
        }

        raw.set("existing", forKey: "value")
        let before = raw.persistentDomain(forName: suiteName)

        let configured = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))

        XCTAssertEqual(configured.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary?)
    }

    func testFactoryRejectsBundleIdentifierBeforeConstructorRuns() {
        guard let identifier = Bundle.main.bundleIdentifier else {
            return
        }

        var called = false

        XCTAssertNil(
            UserDefaults.migratable(
                suiteName: identifier,
                makeUserDefaults: { _ in
                    called = true

                    return UserDefaults()
                }
            )
        )

        XCTAssertFalse(called)
    }

    func testMigratableFactoryPassesNameVerbatimAndReturnsInjectedInstance() throws {
        let suiteName = "MigrationNativeStoreTests.verbatim.\(UUID().uuidString)"
        let injected = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let result = try XCTUnwrap(
            UserDefaults.migratable(
                suiteName: suiteName,
                makeUserDefaults: { name in
                    XCTAssertEqual(name, suiteName)

                    return injected
                }
            )
        )

        XCTAssertIdentical(result, injected)
        XCTAssertEqual(UserDefaults.migrationDomainMetadata(for: result)?.name, suiteName)
        result.removePersistentDomain(forName: suiteName)
    }

    func testMigratableFactoryRejectsReservedAndEmptyNames() {
        let names = [
            "",
            UserDefaults.argumentDomain,
            UserDefaults.registrationDomain,
            UserDefaults.globalDomain,
            kCFPreferencesAnyApplication as String,
            kCFPreferencesCurrentApplication as String,
        ]

        for name in names {
            var called = false

            XCTAssertNil(
                UserDefaults.migratable(
                    suiteName: name,
                    makeUserDefaults: { _ in
                        called = true

                        return UserDefaults()
                    }
                )
            )

            XCTAssertFalse(called)
        }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            XCTAssertNil(UserDefaults.migratable(suiteName: bundleIdentifier))
        }
    }

    func testMigratableFactoryReportsFoundationInitializationFailure() {
        var called = false

        XCTAssertNil(
            UserDefaults.migratable(
                suiteName: "MigrationNativeStoreTests.invalid.\(UUID().uuidString)",
                makeUserDefaults: { _ in
                    called = true

                    return nil
                }
            )
        )

        XCTAssertTrue(called)
    }

    func testMigratableFactoryReturnsNativeObjectAndAssociatesDomain() throws {
        let suiteName = "MigrationNativeStoreTests.native.\(UUID().uuidString)"

        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let objectAlias: AnyObject = defaults
        let alias: any PersistentKeyValueStore = defaults

        XCTAssertEqual(ObjectIdentifier(type(of: defaults)), ObjectIdentifier(UserDefaults.self))

        let metadata = UserDefaults.migrationDomainMetadata(for: defaults)

        XCTAssertEqual(metadata?.name, suiteName)
        XCTAssertIdentical(metadata, UserDefaults.migrationDomainMetadata(for: objectAlias as! UserDefaults))
        XCTAssertIdentical(metadata, UserDefaults.migrationDomainMetadata(for: alias as AnyObject as! UserDefaults))
        XCTAssertEqual(
            try alias.migrationEndpoint.backend.migrationIdentity.identifier,
            UserDefaults.migrationDomainIdentifier(suiteName)
        )
    }

    func testMigrationDomainValidationUsesProvidedApplicationIdentifier() {
        XCTAssertFalse(UserDefaults.isValidMigrationDomain("test.bundle", applicationIdentifier: "test.bundle"))
        XCTAssertFalse(
            UserDefaults.isValidMigrationDomain(
                kCFPreferencesAnyApplication as String,
                applicationIdentifier: "test.bundle"
            )
        )
        XCTAssertFalse(
            UserDefaults.isValidMigrationDomain(
                kCFPreferencesCurrentApplication as String,
                applicationIdentifier: "test.bundle"
            )
        )
        XCTAssertTrue(UserDefaults.isValidMigrationDomain("test.other", applicationIdentifier: "test.bundle"))
    }

    func testMigrationDomainValidationIgnoresCase() {
        XCTAssertFalse(UserDefaults.isValidMigrationDomain("Test.Bundle", applicationIdentifier: "test.bundle"))
        XCTAssertFalse(UserDefaults.isValidMigrationDomain("test.bundle", applicationIdentifier: "Test.Bundle"))
        XCTAssertFalse(
            UserDefaults.isValidMigrationDomain(
                UserDefaults.argumentDomain.uppercased(),
                applicationIdentifier: "test.bundle"
            )
        )
        XCTAssertFalse(
            UserDefaults.isValidMigrationDomain(
                (kCFPreferencesAnyApplication as String).lowercased(),
                applicationIdentifier: "test.bundle"
            )
        )
    }

    func testSuitesThatDifferOnlyByCaseAreTheSameStore() throws {
        let suiteName = "MigrationNativeStoreTests.case.\(UUID().uuidString)"
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName.lowercased()))
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)

        defer {
            source.removePersistentDomain(forName: suiteName)
            destination.removePersistentDomain(forName: suiteName.lowercased())
        }

        source.set(key, to: 42)

        XCTAssertThrowsError(try source.move(key, to: destination, onConflict: .keepDestinationAndRemoveSource)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
        }

        XCTAssertEqual(source.persistentDomain(forName: suiteName)?[key.id] as? Int, 42)
    }

    func testMigrationMetadataLifetimeFollowsNativeObject() throws {
        let suiteName = "MigrationNativeStoreTests.lifetime.\(UUID().uuidString)"

        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        weak var weakDefaults: UserDefaults?
        weak var weakMetadata: UserDefaultsMigrationDomain?
        try autoreleasepool {
            let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))

            weakDefaults = defaults
            weakMetadata = UserDefaults.migrationDomainMetadata(for: defaults)

            XCTAssertNotNil(weakMetadata)
        }

        XCTAssertNil(weakDefaults)
        XCTAssertNil(weakMetadata)
    }

    func testRealStandardEndpointMatchesBundleAvailability() {
        if Bundle.main.bundleIdentifier == nil {
            XCTAssertThrowsError(try UserDefaults.standard.migrationEndpoint) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingApplicationIdentifier)
            }
        } else {
            XCTAssertNoThrow(try UserDefaults.standard.migrationEndpoint)
        }
    }

    func testSeparateRawInstancesDoNotShareMigrationMetadata() throws {
        let suiteName = "MigrationNativeStoreTests.unconfigured.\(UUID().uuidString)"

        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let configured = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let raw = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        XCTAssertNotNil(UserDefaults.migrationDomainMetadata(for: configured))
        XCTAssertNil(UserDefaults.migrationDomainMetadata(for: raw))

        let key = PersistentKey<Int>(#function, defaultValue: 0)

        configured.set(key, to: 7)

        XCTAssertThrowsError(try raw.copy(key, to: configured, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }

        XCTAssertEqual(configured.get(key), 7)
    }

    func testStandardDomainResolution() throws {
        let identifier = "MigrationNativeStoreTests.standard"

        XCTAssertEqual(
            try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: identifier),
            identifier
        )

        XCTAssertThrowsError(
            try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: nil)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingApplicationIdentifier)
        }

        XCTAssertThrowsError(
            try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: "")
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingApplicationIdentifier)
        }
    }

    func testUnknownUserDefaultsFailsBeforeMutation() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = "MigrationNativeStoreTests.unknown.\(UUID().uuidString)"

        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let destination = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 12)

        XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }

        XCTAssertNil(destination.persistentDomain(forName: suiteName)?[key.id])
    }
}

// `lock` protects every access to `values`; snapshots return an array value containing Sendable errors.
private final class LockedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Error] = []

    var isEmpty: Bool {
        lock.lock()

        defer {
            lock.unlock()
        }

        return values.isEmpty
    }

    func append(_ error: Error) {
        lock.lock()
        values.append(error)
        lock.unlock()
    }

    func snapshot() -> [Error] {
        lock.lock()

        defer {
            lock.unlock()
        }

        return values
    }
}

private final class SharedNativeStore: @unchecked Sendable {
    // The reference is immutable and UserDefaults supports concurrent access.
    let store: UserDefaults

    init(_ store: UserDefaults) {
        self.store = store
    }
}
