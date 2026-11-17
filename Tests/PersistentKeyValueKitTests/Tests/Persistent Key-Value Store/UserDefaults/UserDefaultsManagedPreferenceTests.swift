//
//  UserDefaultsManagedPreferenceTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that launch-argument coercion applies only when the launch argument is the visible value.
///
/// `UserDefaults` searches the managed domain before `UserDefaults.argumentDomain`, so an administrator-provided value
/// outranks a launch argument for the same key. A managed string must not be replaced by a parsed launch argument.
final class UserDefaultsManagedPreferenceTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: ManagedUserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.UserDefaultsManagedPreference", function: name)
        userDefaults = try XCTUnwrap(ManagedUserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        // The argument domain is volatile process state shared by every `UserDefaults` instance.
        userDefaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Tests

    func test_get_argumentWithoutManagedValue_parsesArgument() {
        let key = PersistentKey("key:\(#function)", defaultValue: -1)

        userDefaults.setVolatileDomain([key.id: "7"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(userDefaults.get(key), 7)
    }

    func test_get_managedStringDiffersFromArgument_ignoresArgument() {
        let intKey = PersistentKey("key:\(#function).int", defaultValue: -1)
        let urlDefault = URL(string: "https://default.example.com")!
        let urlKey = PersistentKey("key:\(#function).url", defaultValue: urlDefault)

        userDefaults.managedValues = [intKey.id: "0", urlKey.id: "managed"]
        userDefaults.setVolatileDomain(
            [intKey.id: "7", urlKey.id: "https://argument.example.com"],
            forName: UserDefaults.argumentDomain
        )

        XCTAssertEqual(userDefaults.get(intKey), -1)
        XCTAssertEqual(userDefaults.get(urlKey).absoluteString, URL(fileURLWithPath: "managed").absoluteString)
    }

    func test_get_managedStringEqualsArgument_ignoresArgument() {
        let key = PersistentKey("key:\(#function)", defaultValue: -1)

        userDefaults.managedValues = [key.id: "7"]
        userDefaults.setVolatileDomain([key.id: "7"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(userDefaults.get(key), -1)
    }
}

// MARK: - Private Types

/// A `UserDefaults` double whose managed values outrank every other domain, as administrator-provided settings do.
private final class ManagedUserDefaults: UserDefaults {
    var managedValues: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
        managedValues[defaultName] ?? super.object(forKey: defaultName)
    }

    override func objectIsForced(forKey key: String) -> Bool {
        managedValues[key] != nil
    }

    override func url(forKey defaultName: String) -> URL? {
        guard let path = managedValues[defaultName] as? String else {
            return super.url(forKey: defaultName)
        }

        return URL(fileURLWithPath: path)
    }
}
