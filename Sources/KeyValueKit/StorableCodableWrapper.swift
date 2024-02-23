//
//  StorableCodableWrapper.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 4/16/22.
//

import Foundation

private let decoder = JSONDecoder()
private let encoder = JSONEncoder()

/// Prevents the need to manually implement Codable for all of the types that we want to store in `@AppStorage` as
/// `RawRepresentable` `String`s.
@dynamicMemberLookup
public struct StorableCodableWrapper<Value> where Value: Codable {
    public var storedValue: Value
    
    // MARK: Public Initialization
    
    public init(_ storedValue: Value) {
        self.storedValue = storedValue
    }
    
    // MARK: Public Subscripts
    
    @inlinable
    public subscript<PropertyValue>(dynamicMember keyPath: KeyPath<Value, PropertyValue>) -> PropertyValue {
        storedValue[keyPath: keyPath]
    }
}

// MARK: - Decodable Extension

extension StorableCodableWrapper: Decodable {
    // MARK: Public Initialization
    
    public init(from decoder: Decoder) throws {
        storedValue = try Value(from: decoder)
    }
}

// MARK: - Encodable Extension

extension StorableCodableWrapper: Encodable {
    // MARK: Public Instance Interface
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        try storedValue.encode(to: encoder)
    }
}

// MARK: - RawRepresentable Extension

extension StorableCodableWrapper: RawRepresentable {
    // MARK: Public Initialization
    
    public init?(rawValue: String) {
        guard
            let data = rawValue.data(using: .utf8),
            let color = try? decoder.decode(Self.self, from: data)
        else {
            return nil
        }
        
        self = color
    }
    
    // MARK: Public Instance Interface
    
    public var rawValue: String {
        try! String(data: encoder.encode(self), encoding: .utf8)!
    }
}
