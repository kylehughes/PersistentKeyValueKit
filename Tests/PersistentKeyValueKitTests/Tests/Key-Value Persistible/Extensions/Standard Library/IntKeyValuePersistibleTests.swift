//
//  IntKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/29/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class IntKeyValuePersistibleTests: AbstractPrimitiveKeyValuePersistibleTests<Int> {
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [Int] {
        [
            .max,
            .min,
            .zero,
        ]
    }
}
