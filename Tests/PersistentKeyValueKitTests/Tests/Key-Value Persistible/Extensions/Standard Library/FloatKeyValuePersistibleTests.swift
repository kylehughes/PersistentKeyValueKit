//
//  FloatKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/29/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class FloatKeyValuePersistibleTests: AbstractPrimitiveKeyValuePersistibleTests<Float> {
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [Float] {
        [
            .greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
            .infinity,
            .zero,
        ]
    }
}
