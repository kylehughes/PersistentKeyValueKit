//
//  ArrayOfProxiesKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/27/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class ArrayOfProxiesKeyValuePersistibleTests:
    AbstractKeyValuePersistibleTests<
        Array<CustomPersistibleType.Proxy>,
        Array<TimeInterval>,
        Array<TimeInterval>,
        Array<TimeInterval>
    >
{
    // MARK: AbstractKeyValuePersistibleTests Implementation
    
    override var expectations: [Expectation] {
        [
            [
                .distantFuture,
                .distantPast,
            ]
        ].map {
            Expectation(
                target: $0,
                propertyListRepresentation: {
                    $0.map(\.timeIntervalSinceReferenceDate)
                },
                ubiquitousStoreRepresentation: {
                    $0.map(\.timeIntervalSinceReferenceDate)
                },
                userDefaultsRepresentation: {
                    $0.map(\.timeIntervalSinceReferenceDate)
                }
            )
        }
    }
}
