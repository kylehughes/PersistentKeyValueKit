//
//  DictionaryOfPrimitivesKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/11/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class DictionaryOfPrimitivesKeyValuePersistibleTests:
    AbstractPrimitiveKeyValuePersistibleTests<Dictionary<String, String>>
{
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [[String: String]] {
        [
            [
                "distantFuture": "A long time from now…",
                "distantPast": "A long time ago…",
            ]
        ]
    }
}
