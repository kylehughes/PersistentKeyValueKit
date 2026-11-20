//
//  MigrationDomainTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationDomainTests: XCTestCase {
    // MARK: Tests

    func test_addedSuiteOnlyValue_isExcludedFromSource() throws {
        let (sourceDefaults, sourceName) = suite("source")
        let (addedDefaults, addedName) = suite("added")
        let (destinationDefaults, destinationName) = suite("destination")

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
            userDefaults: destinationDefaults,
            domainName: destinationName
        )

        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        if case .sourceAbsent = report.outcomes[0].status {
        } else {
            XCTFail("Expected absent source")
        }

        XCTAssertNil(destinationDefaults.persistentDomain(forName: destinationName)?[key.id])
    }

    func test_completionMarker_ignoresRegisteredAndArgumentValues() throws {
        let (sourceDefaults, sourceName) = suite("source")
        let (destinationDefaults, destinationName) = suite("destination")
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
            userDefaults: destinationDefaults,
            domainName: destinationName
        )
        let completion: PersistentKeyMigrationTracking = .once(
            id: migrationID,
            recordedIn: destination
        )

        let first = try source.copy(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: completion
        )
        if case .recorded = first.completion {
        } else {
            XCTFail("Expected recorded completion")
        }

        XCTAssertEqual(
            destinationDefaults.persistentDomain(forName: destinationName)?[key.id] as? Int,
            12
        )

        XCTAssertEqual(
            destinationDefaults.persistentDomain(forName: destinationName)?[marker.id] as? Bool,
            true
        )

        XCTAssertEqual(destinationDefaults.bool(forKey: marker.id), true)

        let second = try source.copy(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: completion
        )
        if case .alreadyRecorded = second.completion {
        } else {
            XCTFail("Expected existing completion")
        }

        destinationDefaults.removeObject(forKey: marker.id)

        XCTAssertNil(destinationDefaults.persistentDomain(forName: destinationName)?[marker.id])
    }

    func test_destinationRegistrationAndArguments_doNotCountAsConflict() throws {
        let (sourceDefaults, sourceName) = suite("source")
        let (destinationDefaults, destinationName) = suite("destination")
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
            userDefaults: destinationDefaults,
            domainName: destinationName
        )

        _ = try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked)

        XCTAssertEqual(
            destinationDefaults.persistentDomain(forName: destinationName)?[key.id] as? Int,
            41
        )

        XCTAssertEqual(destinationDefaults.integer(forKey: key.id), 99)
    }

    func test_registrationAndArguments_areNotCopiedFromSource() throws {
        let (sourceDefaults, sourceName) = suite("source")
        let (destinationDefaults, destinationName) = suite("destination")
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
            userDefaults: destinationDefaults,
            domainName: destinationName
        )

        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.count, 1)
        if case .sourceAbsent = report.outcomes[0].status {
        } else {
            XCTFail("Expected absent source")
        }

        XCTAssertNil(destinationDefaults.persistentDomain(forName: destinationName)?[key.id])
    }

    // MARK: Private Instance Interface

    private func suite(_ role: String, function: String = #function) -> (UserDefaults, String) {
        let name = stableSuiteName("MigrationDomainTests.\(role)", function: function)

        return (UserDefaults(suiteName: name)!, name)
    }
}
