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
    private let _store = UserDefaults()
    
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override public var store: UserDefaults {
        _store
    }
    
    // MARK: XCTestCase Implementation
    
    override public func tearDown() {
        store.dictionaryRepresentation().keys.forEach(store.removeObject)
        store.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
    }
    
    // MARK: Public Class Interface
    
    override public class var isAbstractTestCase: Bool {
        self == AbstractUserDefaultsTypeTests.self
    }
}
