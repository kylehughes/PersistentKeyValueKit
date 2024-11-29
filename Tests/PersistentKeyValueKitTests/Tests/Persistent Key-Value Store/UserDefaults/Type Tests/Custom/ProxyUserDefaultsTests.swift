//
//  ProxyUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class ProxyUserDefaultsTests: AbstractUserDefaultsTypeTests<CustomPersistibleType.Proxy> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [CustomPersistibleType.Proxy] {
        [
            .distantFuture,
            .distantPast,
        ]
    }
}
