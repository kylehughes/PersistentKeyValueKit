import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationDomainTests: XCTestCase {
    private func suite(_ suffix: String = #function) -> (UserDefaults, String) {
        let name = "MigrationDomainTests.\(suffix).\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testRegistrationAndArgumentsAreNotCopiedFromSource() throws {
        let (sourceDefaults, sourceName) = suite()
        let (destinationDefaults, destinationName) = suite()
        let previousArguments = sourceDefaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceName)
            destinationDefaults.removePersistentDomain(forName: destinationName)
            sourceDefaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
        }
        let key = PersistentKey("domain.source", defaultValue: 0)
        sourceDefaults.register([key])
        sourceDefaults.setVolatileDomain([key.id: 22], forName: UserDefaults.argumentDomain)
        let source = UserDefaultsMigrationBackend(userDefaults: sourceDefaults, domainName: sourceName)
        let destination = UserDefaultsMigrationBackend(
            userDefaults: destinationDefaults, domainName: destinationName)

        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination)
        XCTAssertEqual(report.outcomes.count, 1)
        if case .sourceAbsent = report.outcomes[0].status {} else { XCTFail("Expected absent source") }
        XCTAssertNil(destinationDefaults.persistentDomain(forName: destinationName)?[key.id])
    }

    func testDestinationRegistrationAndArgumentsDoNotCountAsConflict() throws {
        let (sourceDefaults, sourceName) = suite()
        let (destinationDefaults, destinationName) = suite()
        let previousArguments = destinationDefaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceName)
            destinationDefaults.removePersistentDomain(forName: destinationName)
            destinationDefaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
        }
        let key = PersistentKey("domain.destination", defaultValue: 0)
        sourceDefaults.set(41, forKey: key.id)
        destinationDefaults.register([key])
        destinationDefaults.setVolatileDomain([key.id: 99], forName: UserDefaults.argumentDomain)
        let source = UserDefaultsMigrationBackend(userDefaults: sourceDefaults, domainName: sourceName)
        let destination = UserDefaultsMigrationBackend(
            userDefaults: destinationDefaults, domainName: destinationName)

        _ = try source.copy(key, to: destination, onConflict: .keepDestination)
        XCTAssertEqual(
            destinationDefaults.persistentDomain(forName: destinationName)?[key.id] as? Int, 41)
        XCTAssertEqual(destinationDefaults.integer(forKey: key.id), 99)
    }

    func testAddedSuiteOnlyValueIsExcludedFromSource() throws {
        let (sourceDefaults, sourceName) = suite()
        let (addedDefaults, addedName) = suite()
        let (destinationDefaults, destinationName) = suite()
        defer {
            sourceDefaults.removeSuite(named: addedName)
            sourceDefaults.removePersistentDomain(forName: sourceName)
            addedDefaults.removePersistentDomain(forName: addedName)
            destinationDefaults.removePersistentDomain(forName: destinationName)
        }
        let key = PersistentKey("domain.added", defaultValue: 0)
        addedDefaults.set(7, forKey: key.id)
        sourceDefaults.addSuite(named: addedName)
        let source = UserDefaultsMigrationBackend(userDefaults: sourceDefaults, domainName: sourceName)
        let destination = UserDefaultsMigrationBackend(
            userDefaults: destinationDefaults, domainName: destinationName)

        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination)
        if case .sourceAbsent = report.outcomes[0].status {} else { XCTFail("Expected absent source") }
        XCTAssertNil(destinationDefaults.persistentDomain(forName: destinationName)?[key.id])
    }

    func testCompletionMarkerIgnoresRegisteredAndArgumentValues() throws {
        let (sourceDefaults, sourceName) = suite()
        let (destinationDefaults, destinationName) = suite()
        let previousArguments = destinationDefaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceName)
            destinationDefaults.removePersistentDomain(forName: destinationName)
            destinationDefaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
        }
        let key = PersistentKey("domain.marker", defaultValue: 0)
        let migrationID = "domain-marker-\(UUID().uuidString)"
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: migrationID)
        sourceDefaults.set(12, forKey: key.id)
        destinationDefaults.register(defaults: [marker.id: true])
        destinationDefaults.setVolatileDomain([marker.id: true], forName: UserDefaults.argumentDomain)
        let source = UserDefaultsMigrationBackend(userDefaults: sourceDefaults, domainName: sourceName)
        let destination = UserDefaultsMigrationBackend(
            userDefaults: destinationDefaults, domainName: destinationName)
        let completion: PersistentKeyMigrationCompletionPolicy = .once(
            id: migrationID, recordedIn: destination)

        let first = try source.copy(
            key, to: destination, onConflict: .overwriteDestination, completion: completion)
        if case .recorded = first.completion {} else { XCTFail("Expected recorded completion") }
        XCTAssertEqual(
            destinationDefaults.persistentDomain(forName: destinationName)?[key.id] as? Int, 12)
        XCTAssertEqual(
            destinationDefaults.persistentDomain(forName: destinationName)?[marker.id] as? Bool, true)
        XCTAssertEqual(destinationDefaults.bool(forKey: marker.id), true)

        let second = try source.copy(
            key, to: destination, onConflict: .overwriteDestination, completion: completion)
        if case .alreadyRecorded = second.completion {} else { XCTFail("Expected existing completion") }
        destinationDefaults.removeObject(forKey: marker.id)
        XCTAssertNil(destinationDefaults.persistentDomain(forName: destinationName)?[marker.id])
    }
}
