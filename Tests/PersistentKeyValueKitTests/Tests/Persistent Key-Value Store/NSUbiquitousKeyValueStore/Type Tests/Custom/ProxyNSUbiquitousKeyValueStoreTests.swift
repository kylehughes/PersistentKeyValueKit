//
//  ProxyNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

@available(watchOS 9.0, *)
final class ProxyNSUbiquitousKeyValueStoreTests:
    AbstractNSUbiquitousKeyValueStoreTypeTests<CustomPersistibleType.Proxy>
{
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [CustomPersistibleType.Proxy] {
        [
            .distantFuture,
            .distantPast,
        ]
    }
}
