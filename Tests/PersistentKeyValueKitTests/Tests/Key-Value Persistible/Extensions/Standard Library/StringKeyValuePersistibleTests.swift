//
//  StringKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/11/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class StringKeyValuePersistibleTests: AbstractPrimitiveKeyValuePersistibleTests<String> {
    // MARK: AbstractPrimitiveKeyValuePersistibleTests Implementation
    
    override var targets: [String] {
        [
            String(),
            "Created by Kyle Hughes on 5/11/24.",
        ]
    }
}
