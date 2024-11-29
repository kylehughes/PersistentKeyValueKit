//
//  DoubleKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/29/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class DoubleKeyValuePersistibleTests: AbstractPrimitiveKeyValuePersistibleTests<Double> {
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [Double] {
        [
            .greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
            .infinity,
            .zero,
        ]
    }
}
