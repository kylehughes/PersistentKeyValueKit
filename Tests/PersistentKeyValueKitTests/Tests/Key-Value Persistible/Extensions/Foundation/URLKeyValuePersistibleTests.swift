//
//  URLKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/30/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class URLKeyValuePersistibleTests: AbstractKeyValuePersistibleTests<URL, String, URL, URL> {
    // MARK: AbstractKeyValuePersistibleTests Implementation
    
    override public var expectations: [Expectation] {
        targets.map {
            Expectation(
                target: $0,
                propertyListRepresentation: \.absoluteString,
                ubiquitousStoreRepresentation: \.self,
                userDefaultsRepresentation: \.self
            )
        }
    }
    
    // MARK: Instance Implementation

    var targets: [URL] {
        [
            URL(string: "https://kylehugh.es")!
        ]
    }
}
