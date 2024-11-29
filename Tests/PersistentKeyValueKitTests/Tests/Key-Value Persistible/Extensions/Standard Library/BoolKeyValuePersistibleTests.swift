//
//  BoolKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/11/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class BoolKeyValuePersistibleTests: AbstractPrimitiveKeyValuePersistibleTests<Bool> {
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [Bool] {
        [
            false,
            true,
        ]
    }
}
