//
//  StableUserDefaultsSuiteName.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import XCTest

/// Returns a suite name that is stable across runs and unique to the calling test, with its domain cleared.
///
/// `UserDefaults` leaves a preferences file behind for every suite name, so unique-per-run names accumulate files
/// forever. Stable names reuse the same file. The domain is cleared up front in case a previous run crashed; tests
/// still clear it again when they finish.
///
/// - Parameters:
///   - prefix: The test class and any discriminator for tests that need several suites.
///   - function: The calling test, which keeps names unique between tests.
func stableSuiteName(_ prefix: String, function: String = #function) -> String {
    let name = "\(prefix).\(function)"

    UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    UserDefaults(suiteName: name.lowercased())?.removePersistentDomain(forName: name.lowercased())

    return name
}

/// Returns user defaults for the suite that ``stableSuiteName(_:function:)`` names, and that name.
///
/// The domain starts cleared. Tests still clear it when they finish, with
/// `removePersistentDomain(forName:)` and the returned name.
///
/// - Parameters:
///   - prefix: The test class and any discriminator for tests that need several suites.
///   - function: The calling test, which keeps names unique between tests.
func makeStableUserDefaults(
    _ prefix: String,
    function: String = #function
) throws -> (userDefaults: UserDefaults, suiteName: String) {
    let suiteName = stableSuiteName(prefix, function: function)
    let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

    return (userDefaults, suiteName)
}
