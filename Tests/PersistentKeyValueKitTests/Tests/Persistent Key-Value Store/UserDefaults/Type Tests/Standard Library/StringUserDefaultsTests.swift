//
//  StringUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class StringUserDefaultsTests: AbstractUserDefaultsTypeTests<String> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [String] {
        [
            String(),
            "Created by Kyle Hughes on 5/11/24.",
            String(repeating: "A", count: 1_000),
            "Hello, 世界! 🌍",
        ]
    }
}
