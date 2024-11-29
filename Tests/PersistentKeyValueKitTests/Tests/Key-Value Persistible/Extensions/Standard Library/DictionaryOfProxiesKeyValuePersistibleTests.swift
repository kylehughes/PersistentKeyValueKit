//
//  DictionaryOfProxiesKeyValuePersistibleTests 2.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/27/24.
//


import Foundation
import PersistentKeyValueKit
import XCTest

final class DictionaryOfProxiesKeyValuePersistibleTests:
    AbstractKeyValuePersistibleTests<
        Dictionary<String, CustomPersistibleType.Proxy>,
        Dictionary<String, TimeInterval>,
        Dictionary<String, TimeInterval>,
        Dictionary<String, TimeInterval>
    >
{
    // MARK: AbstractKeyValuePersistibleTests Implementation
    
    override var expectations: [Expectation] {
        [
            [
                "distantFuture": .distantFuture,
                "distantPast": .distantPast,
            ]
        ].map {
            Expectation(
                target: $0,
                propertyListRepresentation: {
                    $0.mapValues(\.timeIntervalSinceReferenceDate)
                },
                ubiquitousStoreRepresentation: {
                    $0.mapValues(\.timeIntervalSinceReferenceDate)
                },
                userDefaultsRepresentation: {
                    $0.mapValues(\.timeIntervalSinceReferenceDate)
                }
            )
        }
    }
}
