//
//  ArrayOfPrimitivesKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/27/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class ArrayOfPrimitivesKeyValuePersistibleTests:
    AbstractPrimitiveKeyValuePersistibleTests<Array<Bool>>
{
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [[Bool]] {
        [
            [
                false,
                true,
            ]
        ]
    }
}
