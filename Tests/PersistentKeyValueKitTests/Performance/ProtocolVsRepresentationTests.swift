//
//  ProtocolVsRepresentationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class ProtocolVsRepresentationTests: XCTestCase {}

// MARK: - Optional Tests

extension ProtocolVsRepresentationTests {
    // MARK: Tests
    
    func test_optional_protocol_endToEnd_many() {
        let value: String? = "test"
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 1 ... 1_000 {
                let _ = String?.deserialize(from: value.serialize())
            }
        }
    }
    
    func test_optional_protocol_endToEnd_once() {
        let value: String? = "test"
        
        measure(metrics: [XCTClockMetric()]) {
            let _ = String?.deserialize(from: value.serialize())
        }
    }
    
    func test_optional_representation_optimized_endToEnd_many() {
        let value: String? = "test"
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 1 ... 1_000 {
                helpTestRepresentation(value)
            }
        }
    }
    
    func test_optional_representation_optimized_endToEnd_once() {
        let value: String? = "test"
        
        measure(metrics: [XCTClockMetric()]) {
            helpTestRepresentation(value)
        }
    }
    
    func test_optional_representation_unoptimized_endToEnd_many() {
        let value: Int? = 2
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 1 ... 1_000 {
                helpTestRepresentation(value)
            }
        }
    }
    
    func test_optional_representation_unoptimized_endToEnd_once() {
        let value: Int? = 2
        
        measure(metrics: [XCTClockMetric()]) {
            helpTestRepresentation(value)
        }
    }
    
    // MARK: Private Instance Interface
    
    private func helpTestRepresentation<Value>(
        _ value: Value
    ) where
        Value: NewKeyValuePersistible,
        Value.PersistentKeyValueRepresentation == ProxyPersistentKeyValueRepresentation<Value, Value>
    {
        let _ = Value.persistentKeyValueRepresentation.deserializing(
            .persistentKeyValueRepresentation.serializing(value)
        )
    }
}
