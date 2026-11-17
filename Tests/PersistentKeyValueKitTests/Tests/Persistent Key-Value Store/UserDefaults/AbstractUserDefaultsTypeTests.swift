//
//  AbstractUserDefaultsTypeTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

public class AbstractUserDefaultsTypeTests<Target>: AbstractPersistentKeyValueStoreTypeTests<Target, UserDefaults>
where
    Target: Equatable & KeyValuePersistible & Sendable
{
    private var _store: UserDefaults!
    private var suiteName: String!
    
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override public var store: UserDefaults {
        _store
    }
    
    // MARK: XCTestCase Implementation
    
    override public func setUp() {
        super.setUp()
        
        suiteName = stableSuiteName("AbstractUserDefaultsTypeTests", function: name)
        _store = UserDefaults(suiteName: suiteName)
    }
    
    override public func tearDown() {
        store.removePersistentDomain(forName: suiteName)
        // The argument domain is volatile process state. Clear it so launch-argument overrides from one test do not
        // leak into the next `UserDefaults` instance.
        store.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        store.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        _store = nil
        suiteName = nil
    }
    
    // MARK: Registration Tests

    @MainActor
    func test_register_defaultValue_readsBackThroughRepresentation() {
        for (index, defaultValue) in zip(testValues.indices, testValues) {
            let key = PersistentKey<Target>("registered.\(index)", defaultValue: defaultValue)
            let arrayKey = PersistentKey<[Target]>("registered.array.\(index)", defaultValue: [defaultValue])
            let dictionaryKey = PersistentKey<[String: Target]>(
                "registered.dictionary.\(index)",
                defaultValue: ["key": defaultValue]
            )

            store.register(key, arrayKey, dictionaryKey)

            // Read through the representation, not the key, so a registered object that fails to decode cannot be
            // hidden by the key's default value.
            XCTAssertEqual(key.representation.get(key.id, from: store), defaultValue)
            XCTAssertEqual(arrayKey.representation.get(arrayKey.id, from: store), [defaultValue])
            XCTAssertEqual(dictionaryKey.representation.get(dictionaryKey.id, from: store), ["key": defaultValue])
        }
    }

    // MARK: Public Class Interface
    
    override public class var isAbstractTestCase: Bool {
        self == AbstractUserDefaultsTypeTests.self
    }
}
