import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationNativeStoreTests: XCTestCase {
    func testMigratableFactoryRejectsReservedAndEmptyNames() {
        let names = [
            "",
            UserDefaults.argumentDomain,
            UserDefaults.registrationDomain,
            UserDefaults.globalDomain,
        ]

        for name in names {
            var called = false
            XCTAssertThrowsError(try UserDefaults.migratable(suiteName: name, makeUserDefaults: { _ in
                called = true
                return UserDefaults()
            })) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .invalidStoreIdentifier)
            }
            XCTAssertFalse(called)
        }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            XCTAssertThrowsError(try UserDefaults.migratable(suiteName: bundleIdentifier)) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .invalidStoreIdentifier)
            }
        }
    }

    func testMigratableFactoryReportsFoundationInitializationFailure() {
        XCTAssertThrowsError(
            try UserDefaults.migratable(
                suiteName: "MigrationNativeStoreTests.invalid.\(UUID().uuidString)",
                makeUserDefaults: { _ in nil }
            )
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .storeUnavailable)
        }
    }

    func testMigratableFactoryPassesNameVerbatimAndReturnsInjectedInstance() throws {
        let suiteName = "MigrationNativeStoreTests.verbatim.\(UUID().uuidString)"
        let injected = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let result = try UserDefaults.migratable(
            suiteName: suiteName,
            makeUserDefaults: { name in
                XCTAssertEqual(name, suiteName)
                return injected
            }
        )
        XCTAssertIdentical(result, injected)
        XCTAssertEqual(UserDefaults.migrationDomainMetadata(for: result)?.name, suiteName)
        result.removePersistentDomain(forName: suiteName)
    }

    func testMigratableFactoryReturnsNativeObjectAndAssociatesDomain() throws {
        let suiteName = "MigrationNativeStoreTests.native.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let defaults = try UserDefaults.migratable(suiteName: suiteName)
        let objectAlias: AnyObject = defaults
        let alias: any PersistentKeyValueStore = defaults

        XCTAssertEqual(ObjectIdentifier(type(of: defaults)), ObjectIdentifier(UserDefaults.self))
        let metadata = UserDefaults.migrationDomainMetadata(for: defaults)
        XCTAssertEqual(metadata?.name, suiteName)
        XCTAssertIdentical(metadata, UserDefaults.migrationDomainMetadata(for: objectAlias as! UserDefaults))
        XCTAssertIdentical(metadata, UserDefaults.migrationDomainMetadata(for: alias as AnyObject as! UserDefaults))
        XCTAssertEqual(try alias.migrationEndpoint.backend.migrationIdentity.identifier, suiteName)
    }

    func testSeparateRawInstancesDoNotShareMigrationMetadata() throws {
        let suiteName = "MigrationNativeStoreTests.unconfigured.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let configured = try UserDefaults.migratable(suiteName: suiteName)
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

    func testMigrationMetadataLifetimeFollowsNativeObject() throws {
        let suiteName = "MigrationNativeStoreTests.lifetime.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        weak var weakDefaults: UserDefaults?
        weak var weakMetadata: UserDefaultsMigrationDomain?
        try autoreleasepool {
            let defaults = try UserDefaults.migratable(suiteName: suiteName)
            weakDefaults = defaults
            weakMetadata = UserDefaults.migrationDomainMetadata(for: defaults)
            XCTAssertNotNil(weakMetadata)
        }
        XCTAssertNil(weakDefaults)
        XCTAssertNil(weakMetadata)
    }

    func testUnknownUserDefaultsFailsBeforeMutation() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = "MigrationNativeStoreTests.unknown.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let destination = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        source.set(key, to: 12)

        XCTAssertThrowsError(try source.copy(key, to: destination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }
        XCTAssertNil(destination.persistentDomain(forName: suiteName)?[key.id])
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

    func testFactoryRejectsBundleIdentifierBeforeConstructorRuns() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        var called = false
        XCTAssertThrowsError(
            try UserDefaults.migratable(
                suiteName: identifier,
                makeUserDefaults: { _ in
                    called = true
                    return UserDefaults()
                }
            )
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .invalidStoreIdentifier)
        }
        XCTAssertFalse(called)
    }

    func testFactoryLeavesPreexistingPersistentDataUntouched() throws {
        let suiteName = "MigrationNativeStoreTests.existing.\(UUID().uuidString)"
        let raw = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { raw.removePersistentDomain(forName: suiteName) }
        raw.set("existing", forKey: "value")
        let before = raw.persistentDomain(forName: suiteName)

        let configured = try UserDefaults.migratable(suiteName: suiteName)
        XCTAssertEqual(configured.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary?)
    }

    func testConcurrentFactoryAndEndpointAccess() throws {
        let queue = DispatchQueue(label: #function, attributes: .concurrent)
        let group = DispatchGroup()
        let errors = LockedErrors()
        for index in 0..<32 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    let suiteName = "MigrationNativeStoreTests.concurrent.\(index).\(UUID().uuidString)"
                    let defaults = try UserDefaults.migratable(suiteName: suiteName)
                    _ = try defaults.migrationEndpoint
                    defaults.removePersistentDomain(forName: suiteName)
                } catch {
                    errors.append(error)
                }
            }
        }
        group.wait()
        XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.snapshot())")

        let suiteName = "MigrationNativeStoreTests.shared.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let shared = SharedNativeStore(try UserDefaults.migratable(suiteName: suiteName))
        let sharedGroup = DispatchGroup()
        for _ in 0..<32 {
            sharedGroup.enter()
            queue.async {
                defer { sharedGroup.leave() }
                do {
                    let endpoint = try shared.store.migrationEndpoint
                    guard endpoint.backend.migrationIdentity.identifier == suiteName else {
                        errors.append(NSError(domain: "MigrationNativeStoreTests", code: 1))
                        return
                    }
                } catch {
                    errors.append(error)
                }
            }
        }
        sharedGroup.wait()
        XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors.snapshot())")
    }

    func testMigrationDomainValidationUsesProvidedApplicationIdentifier() {
        XCTAssertFalse(UserDefaults.isValidMigrationDomain("test.bundle", applicationIdentifier: "test.bundle"))
        XCTAssertTrue(UserDefaults.isValidMigrationDomain("test.other", applicationIdentifier: "test.bundle"))
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
}

private final class LockedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Error] = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty
    }

    func append(_ error: Error) {
        lock.lock()
        values.append(error)
        lock.unlock()
    }

    func snapshot() -> [Error] {
        lock.lock()
        defer { lock.unlock() }
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
