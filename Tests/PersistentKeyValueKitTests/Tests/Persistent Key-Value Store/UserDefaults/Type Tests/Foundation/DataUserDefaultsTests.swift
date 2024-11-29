//
//  DataUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation

final class DataUserDefaultsTests: AbstractUserDefaultsTypeTests<Data> {
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
