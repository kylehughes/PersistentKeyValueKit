//
//  DictionaryNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/24.
//

import Foundation
import PersistentKeyValueKit

/// - Important: While each type is exhaustively tested in dictionaries in the abstract test class, it is still useful
///   to test nested dictionaries. Here, we do not go for complete exhaustion – every type as nested arrays – because we
///   could then justify an infinite number of dictionary-of-dictionary-of… tests.
@available(watchOS 9.0, *)
final class DictionaryNSUbiquitousKeyValueStoreTests:
    AbstractNSUbiquitousKeyValueStoreTypeTests<Dictionary<String, CustomPersistibleType.Proxy>>
{
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [[String: CustomPersistibleType.Proxy]] {
        [
            [
                "distantFuture": .distantFuture,
                "distantPast": .distantPast,
                "referenceDate": Date(timeIntervalSinceReferenceDate: 0),
            ]
        ]
    }
}
