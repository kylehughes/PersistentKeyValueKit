//
//  MigrationNativeStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationNativeStoreTests: XCTestCase {
    // MARK: Tests

    func test_factoryAndEndpoint_concurrentAccess() throws {
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
                    let suiteName = stableSuiteName("MigrationNativeStoreTests.concurrent.\(index)")
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

        let suiteName = stableSuiteName("MigrationNativeStoreTests.shared")

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

    func test_factory_leavesPreexistingPersistentDataUntouched() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.existing")
        let raw = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        defer {
            raw.removePersistentDomain(forName: suiteName)
        }

        raw.set("existing", forKey: "value")
        let before = raw.persistentDomain(forName: suiteName)

        let configured = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))

        XCTAssertEqual(configured.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary?)
    }

    func test_factory_rejectsBundleIdentifierBeforeConstructorRuns() {
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

    func test_migratableFactory_passesNameVerbatimAndReturnsInjectedInstance() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.verbatim")
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

    func test_migratableFactory_rejectsReservedAndEmptyNames() {
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

    func test_migratableFactory_rejectsPathAndPropertyListAliases() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.alias")
        let preferences = try XCTUnwrap(
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        )
        .appendingPathComponent("Preferences")
        .path
        let names = [
            "\(suiteName).plist",
            "\(suiteName).PLIST",
            "\(suiteName).plist.plist",
            "\(preferences)/\(suiteName).plist",
            "\(preferences)/\(suiteName)",
            "\(preferences)/./\(suiteName)",
            "./\(suiteName)",
            "other/../\(suiteName)",
            "\(suiteName)/",
            "~/Library/Preferences/\(suiteName)",
            "~\(suiteName)",
            // Swift reads a delimiter followed by a combining mark, or a `.` preceded by a prepended mark, as part of
            // another character, while Core Foundation still sees the delimiter.
            ".\u{2F}\u{301}\(suiteName)",
            "~\u{301}\(suiteName)",
            "\(suiteName)\u{600}.plist",
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
                ),
                name
            )

            XCTAssertFalse(called, name)
        }

        XCTAssertNil(UserDefaults.migratable(suiteName: "\(preferences)/\(suiteName).plist"))
        XCTAssertNotNil(UserDefaults.migratable(suiteName: "\(suiteName).plistx"))
    }

    /// Foundation ends a suite name at its first NUL, so names that differ only after one share a domain.
    func test_migratableFactory_rejectsNamesContainingNUL() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.nul")
        let names = [
            "\(suiteName)\u{0}first",
            "\(suiteName)\u{0}second",
            "\(suiteName)\u{0}",
            "\u{0}\(suiteName)",
            "\(suiteName)\u{0}\u{301}",
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
                ),
                name.debugDescription
            )

            XCTAssertFalse(called, name.debugDescription)
            XCTAssertNil(UserDefaults.migratable(suiteName: name), name.debugDescription)
        }

        // Foundation keeps other control characters in the domain name, so names containing them are accepted.
        for name in ["\(suiteName)\u{1}first", "\(suiteName)\tfirst", "\(suiteName)\u{7F}first"] {
            defer {
                UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            }

            XCTAssertNotNil(UserDefaults.migratable(suiteName: name), name.debugDescription)
        }
    }

    func test_migratableFactory_reportsFoundationInitializationFailure() {
        var called = false

        XCTAssertNil(
            UserDefaults.migratable(
                suiteName: stableSuiteName("MigrationNativeStoreTests.invalid"),
                makeUserDefaults: { _ in
                    called = true

                    return nil
                }
            )
        )

        XCTAssertTrue(called)
    }

    func test_migratableFactory_returnsNativeObjectAndAssociatesDomain() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.native")

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

    func test_migrationDomainValidation_usesProvidedApplicationIdentifier() {
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

    func test_migrationDomainValidation_ignoresCase() {
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

    func test_suitesThatDifferOnlyByCase_areTheSameStore() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.case")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName.lowercased()))
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)

        defer {
            source.removePersistentDomain(forName: suiteName)
            destination.removePersistentDomain(forName: suiteName.lowercased())
        }

        source.set(key, to: 42)

        XCTAssertThrowsError(
            try source.move(key, to: destination, onConflict: .keepDestinationAndRemoveSource, tracking: .untracked)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
        }

        XCTAssertEqual(source.persistentDomain(forName: suiteName)?[key.id] as? Int, 42)
    }

    func test_suitesThatDifferOnlyByNormalization_areTheSameStore() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.caf\u{E9}")
        let decomposedName = suiteName.decomposedStringWithCanonicalMapping
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: decomposedName))
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)

        defer {
            source.removePersistentDomain(forName: suiteName)
            destination.removePersistentDomain(forName: decomposedName)
        }

        XCTAssertFalse(suiteName.utf8.elementsEqual(decomposedName.utf8))

        source.set(key, to: 42)

        XCTAssertThrowsError(
            try source.move(key, to: destination, onConflict: .keepDestinationAndRemoveSource, tracking: .untracked)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
        }

        XCTAssertEqual(source.get(key), 42)
        XCTAssertFalse(
            UserDefaults.isValidMigrationDomain(
                "test.caf\u{E9}",
                applicationIdentifier: "test.cafe\u{301}"
            )
        )
    }

    func test_migrationMetadataLifetime_followsNativeObject() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.lifetime")

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

    func test_realStandardEndpoint_matchesBundleAvailability() {
        if Bundle.main.bundleIdentifier == nil {
            XCTAssertThrowsError(try UserDefaults.standard.migrationEndpoint) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingApplicationIdentifier)
            }
        } else {
            XCTAssertNoThrow(try UserDefaults.standard.migrationEndpoint)
        }
    }

    func test_separateRawInstances_doNotShareMigrationMetadata() throws {
        let suiteName = stableSuiteName("MigrationNativeStoreTests.unconfigured")

        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let configured = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let raw = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        XCTAssertNotNil(UserDefaults.migrationDomainMetadata(for: configured))
        XCTAssertNil(UserDefaults.migrationDomainMetadata(for: raw))

        let key = PersistentKey<Int>(#function, defaultValue: 0)

        configured.set(key, to: 7)

        XCTAssertThrowsError(
            try raw.copy(key, to: configured, onConflict: .overwriteDestination, tracking: .untracked)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingMigrationDomain)
        }

        XCTAssertEqual(configured.get(key), 7)
    }

    func test_standardDomain_resolution() throws {
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

    func test_unknownUserDefaults_failsBeforeMutation() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationNativeStoreTests.unknown")

        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let destination = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 12)

        XCTAssertThrowsError(
            try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
        ) {
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
