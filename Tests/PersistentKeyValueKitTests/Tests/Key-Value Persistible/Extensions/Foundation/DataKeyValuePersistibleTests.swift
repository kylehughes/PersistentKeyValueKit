//
//  DataKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/30/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class DataKeyValuePersistibleTests: AbstractPrimitiveKeyValuePersistibleTests<Data> {
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [Data] {
        [
            Data(),
            "Hello, World!".data(using: .utf8)!,
            Data([0, 1, 2, 3, 4, 5]),
        ]
    }
}
