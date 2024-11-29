//
//  DataNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/24/24.
//

import Foundation

@available(watchOS 9.0, *)
final class DataNSUbiquitousKeyValueStoreTests: AbstractNSUbiquitousKeyValueStoreTypeTests<Data> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Data] {
        [
            Data(),
            Data([0xDE, 0xAD, 0xBE, 0xEF]),
            Data(repeating: 0xFF, count: 1024),
            "Hello, World!".data(using: .utf8)!,
        ]
    }
}
