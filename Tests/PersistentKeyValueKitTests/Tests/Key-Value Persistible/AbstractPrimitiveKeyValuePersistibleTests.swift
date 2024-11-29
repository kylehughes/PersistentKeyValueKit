//
//  AbstractPrimitiveKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/30/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

public class AbstractPrimitiveKeyValuePersistibleTests<Target>:
    AbstractKeyValuePersistibleTests<Target, Target, Target, Target>
where
    Target: Equatable & KeyValuePersistible
{
    // MARK: Public Abstract Interface
    
    public var targets: [Target] {
        fatalError("`targets` needs to be implemented in a concrete subclass.")
    }
    
    // MARK: AbstractKeyValuePersistibleTests Implementation
    
    override public var expectations: [Expectation] {
        targets.map { Expectation($0) }
    }
}
